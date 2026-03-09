# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**mb-monitor** is a macOS menubar extension that gives Keepit customers an easy way to see the state and 
status of their Keepit backups in a single region.

It uses the Keepit APIs documented in source/keepit/apiendpoints.


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

- API docs: `~/source/keepit/apiendpoints/api-endpoints.md`
- All responses are XML with versioned Accept headers (e.g. `application/vnd.keepit.v4+xml`)
- Auth: HTTP Basic with base64-encoded `username:password`
- Base URLs: `https://{region}.keepit.com` (e.g. `ws.keepit`, `us-dc`, `dk-co`)
- Key endpoints used: `/users/`, `/users/{id}/devices`, `/users/{id}/devices/{id}/health`
- VPN to `gitlab.off.keepit.com` required for git push/pull
