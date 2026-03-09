import SwiftUI

/// Inline sign-in form displayed directly in the menubar popover.
struct SignInFormView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedRegion: Region = .usDC
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Connect to Keepit", systemImage: "externaldrive.badge.questionmark")
                .font(.headline)

            Picker("Region", selection: $selectedRegion) {
                ForEach(Region.allCases) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.menu)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textContentType(.username)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .onSubmit { signIn() }

            if let error = appState.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Sign In") { signIn() }
                    .buttonStyle(.borderedProminent)
                    .disabled(username.isEmpty || password.isEmpty || isSigningIn)
            }
        }
    }

    private func signIn() {
        isSigningIn = true
        Task {
            await appState.signIn(region: selectedRegion, username: username, password: password)
            isSigningIn = false
            password = ""
        }
    }
}

/// Inline preferences panel shown in the menubar popover.
struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @Binding var showSettings: Bool

    private let intervalOptions = [1, 2, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    showSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            Picker("Refresh interval", selection: $appState.refreshIntervalMinutes) {
                ForEach(intervalOptions, id: \.self) { minutes in
                    Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes)
                }
            }
            .onChange(of: appState.refreshIntervalMinutes) {
                appState.restartPolling()
            }

            Toggle("Show unhealthy only", isOn: $appState.showUnhealthyOnly)

            if appState.showUnhealthyOnly {
                Text("Shows connectors that are unhealthy, critical, unknown, or have an anomaly detected.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Settings scene view (accessible via Cmd-comma if the app has a dock presence).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            if appState.isAuthenticated {
                Section("Account") {
                    LabeledContent("Status", value: "Connected")
                    LabeledContent("Connectors", value: "\(appState.connectors.count)")
                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                    }
                }
            } else {
                SignInFormView()
                    .environmentObject(appState)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 300)
    }
}
