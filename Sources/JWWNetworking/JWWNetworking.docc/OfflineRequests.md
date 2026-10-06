# Recovering requests after connectivity failures

Persist replay-safe operations, retry on a bounded schedule, and acknowledge recovered results.

## Create an account-scoped queue

Use a dedicated Application Support directory and one queue owner per store URL. The parent directory
must exist. Exclude that directory from backups and choose file protection appropriate for the app's
payloads before opening the store. The queue's SwiftData container is local, with CloudKit disabled,
and separate from the app's domain database.

```swift
let configuration = try OfflineQueueConfiguration(
    storeURL: queueDirectory.appendingPathComponent("requests.store"),
    accountID: account.id
)
let queue = try OfflineRequestQueue(client: client, configuration: configuration)
try await queue.start()
```

Retain the queue for the account's session. Call `start()` on launch to recover pending requests.
Call `stop()` before replacing the queue. It waits for startup recovery, cancels the active retry,
and waits for the worker to settle; it does not delete queued work. Also cancel and await caller-owned initial submissions before
replacing credentials. Use `cancelAll()` when signing out to stop the worker and cancel pending work.
Never change an authentication provider to another account while that account's queue is running.

The worker runs while the app can execute. Persistence survives relaunch; it does not provide
background execution while the operating system suspends or terminates the app. Multiple processes
or queue instances sharing a store are unsupported.

## Submit a replay-safe operation

```swift
let policy = try RetryPolicy(
    maximumRetries: 5,
    schedule: .exponential(initialDelay: 5, multiplier: 2, maximumDelay: 60),
    jitterFraction: 0.2,
    maximumAge: 86_400
)
let submission = try await queue.send(
    template: request,
    policy: policy,
    operation: "update-preferences",
    replaySafety: .idempotencyKey(operationKey)
)
switch submission {
case .completed(let response):
    apply(response)
case .queued(let id):
    showPendingRequest(id)
}
```

An eligible connectivity failure saves a snapshot and its retry policy. `.queued` means the save
succeeded; a storage error means durable acceptance was not confirmed. Persistence begins only after
the initial failure, so termination before that save can lose the operation.

Five retries allow at most six library-managed attempts. URLSession may perform its own lower-level
transport work. Offline waiting alone does not consume a retry. Each started retry reserves its
attempt in the store before network execution. An interrupted attempt retains that reservation,
even if termination occurred before transmission.

A lost response does not prove that the server rejected an operation. Choose `.idempotent` only when
repeating the operation is safe. Use `.idempotencyKey` only with a server that recognizes the
`Idempotency-Key` header. The key is attached before the first attempt and reused for every retry;
delegates cannot remove or replace it. This is not an exactly-once delivery guarantee.

The operation identifier selects app-specific handling after relaunch; it is not a serialized Swift
type. Immediate responses use the template's decoder. Recovered responses retain raw data and status
for the app to decode. A decoding failure never causes another send.

## Configure retry timing

| Schedule | Behavior |
| --- | --- |
| `.none` | One ordinary request; no persistence or automatic retry |
| `.fixed(10)` | Ten seconds before every retry |
| `.exponential(initialDelay: 5, multiplier: 2, maximumDelay: 60)` | 5, 10, 20, 40, 60, 60 seconds before jitter |
| `.intervals([5, 30, 120])` | 5, 30, 120, 120 seconds before jitter |

Zero maximum retries also disables persistence. Retry-specific settings are ignored for `.none`.
Intervals must be finite and positive. `jitterFraction: 0.2` varies a ten-second interval from eight
to twelve seconds; exponential schedules still respect their maximum delay. Zero disables jitter.
Jitter has a floor of one second, or the configured interval when shorter than one second, so full
jitter never schedules an immediate retry. At the exponential cap, positive jitter is clipped to
preserve the maximum delay.

The queue saves the chosen next-attempt date, so relaunch does not reset the schedule or retry budget.
The reserved recovery date for an interrupted attempt is retained if it is still in the future.

The worker retries offline, connection-lost, timeout, host-connection, and DNS errors. Cancellation,
certificate failures, authentication failures, and all non-success HTTP statuses are terminal.
This includes 429 and 5xx; HTTP throttling and `Retry-After` are not part of this policy.

Expiration bounds pending lifetime. Replay checks the deadline again after authentication and delegate
preparation, immediately before transmission. A single worker processes eligible operations without allowing a
future-dated operation to block another ready request. It does not promise dependency ordering.
On relaunch or after suspension, overdue work is reevaluated against the current wall clock.

## Handle completions and cleanup

```swift
for completion in try await queue.unacknowledgedCompletions() {
    try await handleCompletion(completion)
    try await queue.acknowledge(completion.id)
}
```

On success, exhaustion, expiration, permanent failure, or explicit cancellation, the queue saves a
terminal receipt and clears the stored request snapshot and policy. It deletes the receipt after
acknowledgment or retention expiration (seven days by default). Sweeps run while the queue executes,
on recovery, and when querying receipts. Expired receipts are not guaranteed to be delivered.

Make completion handling idempotent: termination before acknowledgment can deliver the same receipt
again. Reading does not acknowledge. Repeated acknowledgment is harmless. Cancellation does not undo
server work; a late response cannot overwrite a cancellation receipt.

Use `events()` for live notifications of saved completion IDs and worker storage failures. The stream
buffers the latest 100 events and is not a durable delivery channel. Query persisted receipts after
subscribing and when returning to the app. Recovery and expiration sweeps may produce receipts without
a live completion notification. Cancelling an observer does not cancel requests.

A worker storage failure stops automatic scheduling and emits `.storageFailure`. Preserve the error
for diagnostics and call `start()` to attempt recovery when storage is available again. Never delete
the store to recover from an ordinary storage error. Failure to save a completion can leave an unknown
server outcome; replay safety remains necessary when recovery retries it.

## Bound retained data and protect credentials

Configuration bounds record count, encoded request size, response-body size, and retained payload
bytes per account. Capacity includes that account's pending records and terminal receipts;
other accounts do not consume its budget. Each record reserves at least 4 KiB
of the byte budget so a failure receipt can replace a pending operation even at capacity. These are
logical payload limits, not limits on database file size, SQLite history, or peak URLSession memory.
An oversized successful replay response becomes a terminal `responseTooLarge` receipt; it is not resent.
Immediate successes are decoded and returned without applying storage limits.

The initial online attempt preserves ordinary request headers and cookie handling. Snapshot header
and payload checks apply only after an eligible connectivity failure, before durable acceptance.
An online success can therefore complete even when the request could not be persisted.

Only approved headers enter the snapshot. Authorization, proxy authorization, and cookie headers are
always rejected. Add custom header names only after verifying that their values are safe to persist.
URLs and bodies can also contain sensitive data; this library does not encrypt or redact them.
Queued requests disable automatic request cookie handling. Use an account-scoped session and provider.

When a provider is configured, authenticated templates fetch its current bearer token before attempts
without explicit Authorization. A delegate may supply Authorization when no provider is configured;
authenticated replay requires that header after preparation. Request-specific authorization takes
precedence on the initial attempt and is never persisted. Delegate preparation runs again on each
attempt and must be reproducible from the persisted request; delegates must not change
the operation's replay semantics or depend on transient state that disappears on relaunch. Streamed
request bodies are unsupported. Generate signed headers or URLs during preparation, not in persisted
request fields.

## Preserve queued work through schema changes

The store starts with `OfflineQueueSchemaV1` and an explicit `SchemaMigrationPlan`. Released schemas
must remain frozen. Add another version and migration stage only when an actual schema change is
needed, using lightweight migration where possible and custom migration when necessary.

Request snapshots carry a separate encoding version. Retry policies and terminal receipt encodings
are also part of the stored contract: retain their decoding compatibility or migrate them explicitly.
Changing a Swift enum's Codable representation is not automatically handled by a database migration.

Migration tests must reopen an on-disk store from every supported prior version and verify request
identity, bodies, account scopes, policies, attempt counts, deadlines, and terminal receipts. V1 has
no migration transition yet. Unsupported or invalid pending records become terminal `invalidRecord`
receipts without blocking other pending work. Their snapshots and policies are cleared like other terminal operations.
Failed store opens and failed saves produce errors; they never trigger an automatic database reset.

## Transport error compatibility

`HTTPClient.send(template:)` reports URLSession failures as `JWWNetworkError.networkError` rather than
`untypedError`. Callers matching `untypedError` for transport failures must update their handling.
This enables the existing cancellation, network-issue, and retry classification helpers.
