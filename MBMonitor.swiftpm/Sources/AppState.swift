import SwiftUI
import Combine
import os

/// Central app state shared across all views.
///
/// Refresh strategy (MOD01):
///   SSE stream (real-time) ──> debounce 2s ──> refresh()
///   Fallback timer ──────────────────────────> refresh()
///   Manual button ───────────────────────────> refresh()
///   guard !isLoading prevents concurrent refreshes.
@MainActor
final class AppState: ObservableObject {
    @Published var connectors: [Connector] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefresh: Date?

    /// Credentials stored in Keychain (see CredentialStore).
    @Published var isAuthenticated = false
    @Published var regionBaseURL: URL?

    // MARK: - User preferences (persisted via UserDefaults)

    @AppStorage("refreshIntervalMinutes") var refreshIntervalMinutes: Int = 5
    @AppStorage("showUnhealthyOnly") var showUnhealthyOnly: Bool = false

    private var refreshTimer: AnyCancellable?
    private var sseTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let api = KeepitAPIClient()
    private let credentials = CredentialStore()
    private static let logger = Logger(subsystem: "com.keepit.MBMonitor", category: "AppState")

    /// Connectors filtered by the "show unhealthy only" preference.
    var visibleConnectors: [Connector] {
        if showUnhealthyOnly {
            return connectors.filter { $0.health != .healthy || $0.hasAnomaly }
        }
        return connectors
    }

    var devicesURL: URL? {
        regionBaseURL.flatMap { URL(string: "/desktop/devices", relativeTo: $0)?.absoluteURL }
    }

    /// SF Symbol name reflecting overall backup health.
    var statusIcon: String {
        if !isAuthenticated { return "externaldrive.badge.questionmark" }
        if isLoading { return "arrow.triangle.2.circlepath" }
        let hasUnhealthy = connectors.contains { $0.health != .healthy }
        return hasUnhealthy ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark"
    }

    init() {
        if let cred = credentials.load() {
            configureAPI(with: cred)
            regionBaseURL = cred.region.baseURL
            isAuthenticated = true
            startPolling()
            Task {
                do {
                    api.userId = try await api.authenticate()
                    await refresh()
                    startEventStream()
                } catch {
                    self.error = "Re-auth failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func signIn(region: Region, username: String, password: String) async {
        let cred = Credential(region: region, username: username, password: password)
        configureAPI(with: cred)

        do {
            let userId = try await api.authenticate()
            api.userId = userId
            credentials.save(cred)
            regionBaseURL = cred.region.baseURL
            isAuthenticated = true
            startPolling()
            await refresh()
            startEventStream()
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        credentials.delete()
        isAuthenticated = false
        connectors = []
        refreshTimer?.cancel()
        sseTask?.cancel()
        sseTask = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    func refresh() async {
        guard isAuthenticated, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            var loaded = try await api.fetchConnectors()

            // Fetch health, latest snapshot, and anomalies for each connector in parallel
            await withTaskGroup(of: (Int, HealthStatus, String?, Date?, Bool).self) { group in
                for (index, connector) in loaded.enumerated() {
                    group.addTask { [api] in
                        let (health, reason) = (try? await api.fetchConnectorHealth(connectorId: connector.id)) ?? (.unknown, nil)
                        let snapshotTime = try? await api.fetchLatestSnapshot(connectorId: connector.id)
                        let hasAnomaly = (try? await api.fetchHasAnomalies(connectorId: connector.id)) ?? false
                        return (index, health, reason, snapshotTime, hasAnomaly)
                    }
                }
                for await (index, health, reason, snapshotTime, hasAnomaly) in group {
                    loaded[index].health = health
                    loaded[index].healthReason = reason
                    loaded[index].lastSnapshotTime = snapshotTime
                    loaded[index].hasAnomaly = hasAnomaly
                }
            }

            connectors = loaded
            lastRefresh = .now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Restart polling with the current interval setting.
    func restartPolling() {
        startPolling()
    }

    // MARK: - Private

    private func configureAPI(with cred: Credential) {
        api.configure(baseURL: cred.region.baseURL, username: cred.username, password: cred.password)
    }

    private func startPolling() {
        refreshTimer?.cancel()
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        refreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
    }

    // MARK: - SSE Event Stream
    //
    //  startEventStream()
    //  |
    //  v
    //  +---> [create SSEClient] ---> [iterate events()] --+
    //  |                                                    |
    //  |     on event: reset 2s debounce -> refresh()       |
    //  |                                                    |
    //  |     on retryable error (5xx, network):             |
    //  |       backoff 1s,2s,4s...30s max                   |
    //  +---- refresh() on reconnect <-----------------------+
    //  |
    //  |     on non-retryable error (4xx):
    //  +---> set self.error, break

    private func startEventStream() {
        // A6 fix: cancel any existing SSE task before starting a new one
        sseTask?.cancel()
        debounceTask?.cancel()

        guard let request = try? api.vqueueRequest(sources: api.vqueueSources()) else {
            Self.logger.error("Failed to build vqueue request")
            return
        }

        Self.logger.info("Starting SSE event stream")

        sseTask = Task { [weak self] in
            var backoff: UInt64 = 1  // seconds

            while !Task.isCancelled {
                guard let self else { return }

                let client = SSEClient(request: request)
                do {
                    for try await event in client.events() {
                        if Task.isCancelled { break }
                        Self.logger.info("SSE event received: \(event.event)")
                        self.debouncedRefresh()
                    }
                    // Stream ended normally (shouldn't happen for SSE)
                    break
                } catch let error as SSEError {
                    switch error {
                    case .nonRetryable(let code):
                        Self.logger.error("SSE non-retryable error: \(code)")
                        self.error = "Event stream error (HTTP \(code))"
                        return  // stop retry loop
                    case .retryable(let code):
                        Self.logger.warning("SSE retryable error: \(code), backing off \(backoff)s")
                    case .disconnected:
                        Self.logger.info("SSE disconnected, backing off \(backoff)s")
                    }
                } catch {
                    if Task.isCancelled { return }
                    Self.logger.error("SSE unexpected error: \(error.localizedDescription)")
                }

                // Backoff before reconnecting
                do {
                    try await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                } catch {
                    return  // cancelled during sleep
                }
                backoff = min(backoff * 2, 30)

                // Refresh on reconnect to catch events missed during the gap
                if !Task.isCancelled {
                    Self.logger.info("SSE reconnecting, triggering refresh")
                    await self.refresh()
                }
            }
        }
    }

    /// Reset a 2-second debounce timer. When it fires, trigger a full refresh.
    /// Coalesces rapid SSE events (e.g. batch backup completions) into a single refresh.
    private func debouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return  // cancelled — a newer event reset the timer
            }
            await self?.refresh()
        }
    }
}
