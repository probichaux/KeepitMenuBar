# Changelog

## 2026-03-09

### Added

- Real-time connector updates via Keepit vqueues SSE API (`SSEClient.swift`)
- Automatic reconnection with exponential backoff on SSE disconnects
- 2-second debounce to coalesce rapid SSE events into a single refresh
- Concurrent refresh guard to prevent duplicate API calls

### Changed

- Connector updates now arrive in near-real-time instead of on a fixed polling interval
- Polling timer retained as a fallback safety net for silent SSE disconnects

## 2026-03-07

### Added

- Initial release: menubar app with connector health monitoring
- Color-coded health indicators (healthy/unhealthy/critical/unknown)
- Anomaly detection with warning badges
- Last backup time in connector tooltips
- Configurable polling interval (1-60 minutes)
- "Show unhealthy only" filter mode
- Click-to-open Keepit web console
- macOS Keychain credential storage
- Multi-region support (AU, CA, DK, DE, UK, US, CH)
