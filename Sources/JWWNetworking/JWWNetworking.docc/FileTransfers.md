# File transfers and incremental responses

Use ``HTTPClient`` for foreground uploads and incremental responses. Use
``HTTPTransferSession`` for file tasks that need stable identities and background
session reconnection. Existing `send(template:)` requests still buffer and decode
their responses; the offline request queue does not manage file transfers.

## Foreground operations

`upload(template:fromFile:progress:)` sends an immutable local file, validates the
HTTP response, and decodes the complete response through the template. The file
must contain the entire body, including any multipart envelope. The template and
preparation delegate must not also supply a body or body stream. Keep the source
file until completion. Progress callbacks run on Foundation's delegate queue and
must return promptly. Unknown expected lengths are represented by nil.

`stream(template:receiveResponse:receiveData:)` validates HTTP status, awaits the
response callback, then awaits each ordered data callback. The template's Output
decoder is not used. A caller can reject otherwise-successful headers, such as a
200 response where a byte-range consumer requires 206 and an exact Content-Range.
The implementation uses a dedicated serial streaming session with a copy of the
client's configuration. Redirect and authentication-challenge callbacks are
forwarded to the client's delegate on its original delegate queue; other delegate
events are not forwarded. The client's existing session is not invalidated or
blocked by a slow streaming consumer.

The stream suspends transport while its consumer handles a chunk and waits on its
dedicated delegate queue before delivering another callback. Only one callback Task
exists at a time. The adapter does not accumulate chunks or buffer the body;
Foundation still owns its transport buffers. Keep callbacks responsive and
cooperative with Task cancellation. Move app-specific processing to the correct
actor or serial loading queue. A callback can make another request through the same
HTTPClient without blocking that client's session queue.

Both foreground methods require an in-process session. Cancel their calling Task
to cancel transport. Callback failures stop streaming; arbitrary callback errors
are wrapped in `untypedError`, while JWWNetworkError values retain their cases.
Neither method refreshes credentials or retries after an HTTP or transport error.

## System-owned file tasks

Create one ``HTTPTransferSession`` for each background identifier, using
`URLSessionConfiguration.background(withIdentifier:)`. Pass the same identifier
after relaunch. A default or ephemeral configuration can exercise the same adapter
in process but does not provide background lifecycle guarantees.

Install the fixed ``HTTPTransferSession/Callbacks`` before creating the session:

- `progress`: publish byte counts, not an invented percentage for unknown lengths.
- `claimDownload`: synchronously move or copy Foundation's temporary file to an
  app-selected staging location, or throw. The location expires when this callback
  returns. Do not dispatch its move asynchronously or synchronously block on another
  actor that is itself waiting for delegate delivery.
- `completed`: inspect the HTTP response and either the claimed-download result or
  bounded upload response Data. Persist an upload receipt before publishing content.
  Validate a downloaded file before installing it in the offline store.
- `finishedBackgroundEvents`: Foundation finished delivering its background events.
  Wait for app restoration, file processing, and receipt persistence before invoking
  the UIKit completion handler. The callback itself does not perform that work.

Callbacks are synchronous and serialized on a private Foundation delegate queue.
Any asynchronous work they launch must be tracked by the application. Initialize
account state and a thread-safe staging destination lookup before reconnecting.

Journal intent before calling `startDownload(template:id:)` or
`startUpload(template:fromFile:id:)`. Supply a unique opaque journal ID, without
credentials or server URLs. Submission prepares the request exactly once, assigns
the ID to taskDescription, and resumes it. Cancellation of the submitting Task after
submission returns does not cancel a durable transfer; use `cancel(id:)` instead.
Cancellation during preparation requires cancelling that submitting Task, since
there is no Foundation task to enumerate yet.

Use `tasks()` after relaunch to reconcile the application journal with running and
suspended tasks, including tasks without a recognized caller ID. Restoration does
not reconstruct requests or update their credentials. Missing tasks do not prove
success: reconcile staged files and persisted receipts before deciding what to do.
Retain immutable upload files until the app has resolved the operation.

The default upload response limit is 1 MiB. Override it only for a known contract.
Declared and actual response lengths are checked. An oversized response fails
without replay even if the server already committed the upload. Development APIs
that return entire files as inline data URLs need an explicit larger limit or a
representative storage-backed test service.

Keep the owner alive for its session lifetime. Call `invalidate()` to finish existing
work and release the session, or `invalidate(cancelOutstanding: true)` to explicitly
cancel outstanding tasks. Subsequent submissions are rejected. Do not invalidate
the session merely because the application moved into the background.

## Responsibilities and limits

The library supplies transport, not scheduling, persistence, account management,
destination policy, checksums, offline eviction, media decoding, or AVFoundation
integration. It never automatically replays uploads or adds an idempotency key.
An ambiguous failure or cancellation cannot establish whether the server committed
an upload. Preserve app-owned state and require an explicit retry policy; retrying
may create another remote object. A local cancellation never deletes that object.

Background sessions follow redirects; a redirect-refusal delegate cannot prevent
that. System termination/restoration differs from user force-quit, which cancels
background tasks. Foreground unit tests and synthetic delegate events do not prove
daemon restoration, locked-device access, or UIKit acknowledgement behavior. Verify
those flows in an integrating app on a physical device, separately from package
tests. No explicit download resume-data or resumable-upload protocol is provided.
