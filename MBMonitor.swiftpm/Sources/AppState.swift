import SwiftUI
import Combine

/// Central app state shared across all views.
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
    private let api = KeepitAPIClient()
    private let credentials = CredentialStore()

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
        } catch {
            self.error = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        credentials.delete()
        isAuthenticated = false
        connectors = []
        refreshTimer?.cancel()
    }

    func refresh() async {
        guard isAuthenticated else { return }
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
}
