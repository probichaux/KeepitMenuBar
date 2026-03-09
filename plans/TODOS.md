# TODOS

## 1. Targeted single-connector refresh

**What:** Add `AppState.refreshConnector(guid:)` that refreshes health, snapshot, and anomaly status for a single connector instead of the full list.

**Why:** With SSE, every event currently triggers a full `refresh()` (1 + 3*N API calls). If a customer has many connectors and frequent backup jobs, this is wasteful. A targeted refresh would make 3 API calls instead of 1 + 3*N.

**Context:** The `job-{userId}` vqueue event payload is XML: `<job><job-guid/><account-guid/><device-guid/><device-type/><update/></job>`. The `device-guid` maps to `Connector.id` (lowercased GUID). The `update` field is `newjob`, `state`, or `progress` -- only `state` changes (completion/failure) warrant a refresh. Implementation needs: parse event XML with `XMLSimpleParser.firstElementText`, find the connector in the array by GUID, fetch its health/snapshot/anomaly, update in-place. Note: `Connector.id` is `String` not `Int` -- the original plan had a type error here.

**Depends on / blocked by:** MOD01 (SSE integration) must land first.

## 2. Make KeepitAPIClient an actor

**What:** Convert `KeepitAPIClient` from a class with `@unchecked Sendable` to a proper Swift actor.

**Why:** The client has mutable state (`baseURL`, `authHeader`, `userId`) with no synchronization. Currently safe because all access goes through `@MainActor` AppState, but this is fragile -- any future non-MainActor caller would introduce a data race. SSE adds a second access path (building the vqueue URLRequest) that happens to also be MainActor-safe, but the pattern is getting riskier.

**Context:** `KeepitAPIClient` is in `Sources/KeepitAPIClient.swift`. Converting to an actor means all call sites need `await`. Current call sites are all in `AppState` (already async) and in `TaskGroup` closures (already async), so the migration is straightforward. The `configure()` method would become an actor-isolated mutation. The `session` property (URLSession) is already Sendable.

**Depends on / blocked by:** Nothing -- can be done independently. Lower priority than MOD01.
