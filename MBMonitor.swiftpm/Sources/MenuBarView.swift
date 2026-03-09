import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.isAuthenticated {
                signInPrompt
            } else if showSettings {
                PreferencesView(showSettings: $showSettings)
                    .environmentObject(appState)
            } else if appState.connectors.isEmpty && appState.isLoading {
                ProgressView("Loading connectors...")
                    .padding()
            } else {
                connectorList
                Divider()
                footer
            }
        }
        .frame(width: 320)
        .padding()
    }

    // MARK: - Subviews

    private var signInPrompt: some View {
        SignInFormView()
            .environmentObject(appState)
    }

    private var connectorList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connectors")
                .font(.headline)
                .padding(.bottom, 4)

            if let error = appState.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if appState.visibleConnectors.isEmpty && appState.showUnhealthyOnly {
                Text("All connectors are healthy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            ForEach(appState.visibleConnectors) { connector in
                ConnectorRow(connector: connector, devicesURL: appState.devicesURL)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
            }

            if let lastRefresh = appState.lastRefresh {
                Text("Updated \(lastRefresh, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(appState.isLoading)

            Button("Sign Out") {
                appState.signOut()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.caption)
    }
}

// MARK: - Connector Row

struct ConnectorRow: View {
    let connector: Connector
    let devicesURL: URL?

    var body: some View {
        HStack {
            connectorIcon
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(connector.name)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                Text(connector.type.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            healthBadge
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = devicesURL {
                NSWorkspace.shared.open(url)
            }
        }
        .help(tooltipText)
    }

    private var tooltipText: String {
        var parts: [String] = [connector.name, connector.type.displayName]
        parts.append("Health: \(connector.health.rawValue.capitalized)")
        if let reason = connector.healthReason, reason != "OK" {
            parts.append("Reason: \(reason)")
        }
        if connector.hasAnomaly {
            parts.append("Anomaly detected")
        }
        if let snapshot = connector.lastSnapshotTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            parts.append("Last backup: \(formatter.localizedString(for: snapshot, relativeTo: .now))")
        } else {
            parts.append("Last backup: unknown")
        }
        return parts.joined(separator: "\n")
    }

    @ViewBuilder
    private var connectorIcon: some View {
        if let nsImage = IconProvider.icon(for: connector.type) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: connector.type.icon)
        }
    }

    private var healthBadge: some View {
        ZStack {
            Circle()
                .fill(healthColor)
                .frame(width: 10, height: 10)
            if connector.hasAnomaly {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .offset(x: 6, y: -6)
            }
        }
    }

    private var healthColor: Color {
        switch connector.health {
        case .healthy: return .green
        case .unhealthy: return .yellow
        case .critical: return .red
        case .unknown: return .gray
        }
    }
}
