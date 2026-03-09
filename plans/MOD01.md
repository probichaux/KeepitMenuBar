# MOD01: Replace polling with SSE-driven refresh via vqueues

## Goal

Replace the fixed-interval polling in `AppState` with Server-Sent Events (SSE) subscriptions to the Keepit vqueues API, reducing unnecessary API calls and providing near-real-time connector status updates.

## Background

Currently `AppState.startPolling()` fires a timer every N minutes that calls `refresh()`, which makes 1 + 3×connectors HTTP requests regardless of whether anything changed. The Keepit vqueues API provides real-time SSE notifications when devices, jobs, or backup history change.

## Architecture

```
                          +-------------------------+
                          |      Keepit API          |
                          |  /vqueues/multiqueue     |
                          +------------+------------+
                                       | SSE stream (text/event-stream)
                                       v
+----------------+        +-------------------------+
| Fallback       | timer  |      SSEClient          |
| Timer          +------->|  pure parser, single    |
| (safety net)   |        |  connection only        |
+----------------+        +------------+------------+
                                       | SSEEvent / throw
                                       v
                          +-------------------------+
                          |      AppState            |
                          |  startEventStream()      |
                          |  +---------------------+ |
                          |  | retry loop (owns     | |
                          |  |   backoff + policy)  | |
                          |  | on event: debounce   | |
                          |  |   then refresh()     | |
                          |  | on reconnect: refresh| |
                          |  | on 4xx: stop, error  | |
                          |  +---------------------+ |
                          +------------+------------+
                                       | @Published
                                       v
                          +-------------------------+
                          |    MenuBarView           |
                          +-------------------------+
```

### SSEClient state machine

```
  SSEClient is a pure single-connection parser.
  It does NOT reconnect -- AppState owns that.

  +----------+  bytes(for:)  +-----------+  EOF/error  +----------+
  |  IDLE    | ------------> | STREAMING | ----------> |  DONE    |
  +----------+               | (yielding |             | (throws) |
                             |  events)  |             +----------+
                             +-----------+
```

### AppState retry loop

```
  startEventStream()
  |
  v
  +---> [create SSEClient] ---> [iterate events()] --+
  |                                                    |
  |     on event: reset 2s debounce -> refresh()       |
  |                                                    |
  |     on retryable error (5xx, network):             |
  |       backoff 1s,2s,4s...30s max                   |
  +---- emit sentinel "reconnected" -> refresh() <-----+
  |
  |     on non-retryable error (4xx):
  +---> set self.error, break
```

### New files

- `Sources/SSEClient.swift` -- Pure SSE stream parser. Single connection, no reconnection logic.

### Modified files

- `AppState.swift` -- Add `startEventStream()` with retry loop, debounce, and fallback timer.
- `KeepitAPIClient.swift` -- Add `vqueueURL(sources:)` helper.

## Review decisions

Decisions made during plan-exit-review:

| # | Decision |
|---|---|
| 1A | Plain `Task` (inherits MainActor), not detached |
| 2A | Sentinel SSEEvent for reconnect notification |
| 3A | 4xx = non-retryable, terminate stream |
| 4A | `guard !isLoading` at top of `refresh()` |
| 5A | AppState owns retry loop, SSEClient is pure parser |
| 6C | Leave "Refresh interval" setting as-is |
| 9A | Manual testing with logging, no XCTest target |
| 10A | 2-second debounce on SSE events |

## Detailed steps

### Step 1: Implement SSEClient

Create `Sources/SSEClient.swift`:

- Struct `SSEEvent { let event: String; let data: String }`.
- Class `SSEClient` that takes a `URLRequest`.
- Method `events() -> AsyncThrowingStream<SSEEvent, Error>`:
  - Opens the request via `URLSession.bytes(for:)`.
  - Checks HTTP status: 4xx throws `SSEError.nonRetryable(statusCode)`, 5xx throws `SSEError.retryable(statusCode)`.
  - Reads lines, parses SSE protocol: accumulates `event:`, `data:`, `id:` fields, yields `SSEEvent` on blank line.
  - On stream EOF, throws `SSEError.disconnected`.
  - Malformed lines (no colon, unknown fields) are skipped gracefully.
- SSEClient does NOT reconnect. It parses one connection and terminates.
- Add `os.Logger` output for connection open, events received, and errors.

### Step 2: Add vqueue URL builder to KeepitAPIClient

Add to `KeepitAPIClient`:

```swift
func vqueueURL(sources: [String]) -> URL?
```

Builds `GET /vqueues/multiqueue?sources={comma-separated}` against the configured base URL. Sources:
- `devices-{userId}` -- connector list changes
- `job-{userId}` -- job state changes (covers backup completion)

Also add a helper to build a `URLRequest` with auth headers for the SSE connection (SSEClient needs the same Basic Auth).

### Step 3: Modify AppState for event-driven refresh

Add to `AppState`:
- `private var sseTask: Task<Void, Never>?` -- handle for the SSE event loop.
- `private var debounceTask: Task<Void, Never>?` -- handle for the 2s debounce timer.

`startEventStream()`:
1. **Cancel any existing SSE task first** (`sseTask?.cancel()`) -- critical for re-sign-in and re-auth paths (fix A6).
2. Build the multiqueue `URLRequest` via `api.vqueueRequest(sources:)`.
3. Start a `Task { }` (plain, inherits MainActor -- decision 1A):
   - `while !Task.isCancelled` retry loop (decision 5A -- AppState owns retry).
   - Create `SSEClient`, iterate `events()`.
   - On each event: reset a 2-second debounce timer (decision 10A). When the timer fires, call `refresh()`.
   - On `SSEError.retryable` or `.disconnected`: exponential backoff (1s, 2s, 4s, max 30s), then emit sentinel `SSEEvent(event: "reconnected", data: "")` and `refresh()` (decision 2A).
   - On `SSEError.nonRetryable` (4xx): set `self.error`, break out of retry loop (decision 3A).
4. Store the Task handle in `sseTask`.

Modify `refresh()`:
- Add `guard !isLoading else { return }` at the top (decision 4A).

Modify `signIn()` and `init()` re-auth:
- Call `startEventStream()` instead of (or in addition to) `startPolling()`.
- `startPolling()` remains as fallback timer; interval unchanged (decision 6C).

Modify `signOut()`:
- Cancel `sseTask` and `debounceTask`.

### Step 4: Handle network transitions

- On SSE disconnect (stream error/EOF), `SSEClient` throws. AppState's retry loop catches it and reconnects with backoff.
- On reconnect, AppState triggers a full `refresh()` to catch events missed during the gap.
- The fallback timer covers the case where SSE silently stalls (no EOF, just no data).
- `Task.isCancelled` check in the retry loop ensures clean shutdown on sign-out.

## Testing approach

Manual testing with `os.Logger` output (decision 9A):

1. Sign in, verify SSE connection opens (log the stream URL).
2. Observe SSE events in Console.app.
3. Trigger a backup job in the Keepit dashboard and verify the menubar updates within seconds.
4. Kill network / sleep-wake the Mac and verify reconnection + refresh in logs.
5. Verify fallback timer still fires if SSE is disconnected for >15 minutes.
6. Sign out and sign in again -- verify old SSE task is cancelled and new one starts (A6 fix).

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| SSE connection drops silently | Fallback timer; SSEClient detects EOF |
| Network transitions (sleep/wake, VPN) | Retry loop reconnects with backoff; full refresh on reconnect |
| Rapid burst of SSE events (batch backups) | 2-second debounce coalesces into single refresh |
| Battery drain from persistent connection | URLSession handles TCP keepalive efficiently; one connection vs. many polling requests |
| Auth token expires mid-stream | 4xx on reconnect terminates stream; error surfaced to user |
| Re-sign-in while SSE active (A6) | `startEventStream()` cancels existing `sseTask` before starting new one |
| Concurrent refresh from SSE + fallback timer | `guard !isLoading` prevents double refresh |

## Out of scope

| Item | Rationale |
|------|-----------|
| Targeted single-connector refresh | Deferred -- full refresh on every event is sufficient given low event frequency |
| Per-connector `history-{deviceGuid}` subscriptions | Would require N connections or a system token |
| Making `KeepitAPIClient` an actor | Pre-existing tech debt, separate refactor |
| Adding XCTest target | Manual testing with logging for now |
| Renaming "Refresh interval" setting | Left as-is per decision 6C |
| Push notifications / background app refresh | Foreground menubar app only |
