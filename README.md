# KeepitMenuBar

A macOS menubar app that gives [Keepit](http://www.keepit.com) customers an at-a-glance view of their backup connector health in a single region.

** Note that this isn't an official product of Keepit A/S, and it's not guaranteed to work. It might steal your
wallet, kiss you on the ear, or run off with your dog. **

## Features

- **Connector health monitoring** — see healthy/unhealthy/critical status for all connectors with color-coded indicators
- **Last backup time** — hover over any connector to see when its last backup completed
- **Anomaly detection** — connectors with anomalies in the last 7 days are flagged with a warning indicator
- **Configurable refresh** — poll every 1–60 minutes (default 5)
- **Unhealthy filter** — toggle to show only connectors that need attention
- **Quick access** — click any connector to open the Keepit web console
- **Secure credentials** — stored in the macOS Keychain

## How it works

**mb-monitor** is a macOS menubar extension that gives Keepit customers an easy way to see the state and 
status of their Keepit backups in a single region. Once you sign in, it polls connector state at a defined interval and 
shows you the health, anomaly status, and last-completed-backup time for each connector. You can change the polling interval, and there's a "lights out" mode that minimizes clutter by only showing you unhealthy or anomalous connectors.

It uses the Keepit APIs documented in source/keepit/apiendpoints.

To use it, you'll need to create a Keepit API token (ideally with restricted righgts) and use it to log in. The
token values you enter will be stored in the macOS Keychain.


## Build & Run

```bash
cd MBMonitor.swiftpm
swift build            # compile
swift run              # run from terminal
open Package.swift     # open in Xcode
```

Or open `MBMonitor.swiftpm` directly in Xcode as a Swift Playground App package.

Requires macOS 14+ and Swift 5.9+.

## Architecture

```
MBMonitor.swiftpm/Sources/
  MBMonitorApp.swift      # @main entry — MenuBarExtra scene + Settings scene
  AppState.swift           # Central ObservableObject: auth, polling, connector list
  Models.swift             # Region, Credential, Connector, ConnectorType, HealthStatus
  KeepitAPIClient.swift    # HTTP client — Basic Auth, XML responses
  XMLParsers.swift         # XMLParser-based parsers for connectors & health
  CredentialStore.swift    # macOS Keychain wrapper for credentials
  MenuBarView.swift        # Menubar popover: connector list with health badges
  SettingsView.swift       # Settings window: sign-in form / account info
```

**Data flow:** SettingsView -> AppState.signIn() -> KeepitAPIClient -> XML parsing -> AppState.connectors -> MenuBarView

**Polling:** AppState starts a 5-minute timer after sign-in. Each tick calls `refresh()` which fetches connectors and updates health.

**Credentials:** Stored in macOS Keychain via `CredentialStore`. Loaded on app launch to auto-authenticate.

## Keepit API

- API docs: These aren't publicly available yet, but will be soon.
- Base URLs: `https://{region}.keepit.com` (e.g. `ws.keepit`, `us-dc`, `dk-co`)
- Key endpoints used: `/users/`, `/users/{id}/devices`, `/users/{id}/devices/{id}/health`

## License

MIT
