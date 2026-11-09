# File transfers and incremental responses

Status: JWWNetworking implemented locally; validation completed with existing watchOS test failures.
Application integration, background lifecycle acceptance, and backend work remain pending.
Updated: 2026-11-09.

## Outcome and accepted decisions

Add reusable transport to JWWNetworking for Clickwheel audio and togetherMade
images/videos while preserving ordinary API requests and durable JSON delivery.

Justin approved these scope decisions:

- Background file uploads are included in the initial scope, alongside downloads.
- The foreground file-upload API also remains in the initial scope.
- togetherMade retains downloaded media offline and plays video after the complete
  file downloads. Progressive video playback is not required.
- Keep togetherMade's existing 50 MiB attachment limit (50 * 1024 * 1024 bytes).
- Start with explicit user retry for ambiguous upload failures. Warn that retry
  can upload another copy; do not retry automatically or claim deduplication.
- JWWNetworking implementation is authorized. Both apps and the togetherMade
  backend remain unchanged; hosted uploads are not enabled by this work.

Offline retention permits an explicit app-managed file store; it does not mean
enabling general HTTP caching or retaining another account's files after logout.

## Evidence and baseline

The preceding source audit inspected toolkit main at `9867b4f`, togetherMade
backend main at `a8a5e294`, and fetched mobile-ios main at `0815999`. The iOS
working branch was left intact. Refresh these revisions before implementation.

- `Sources/JWWNetworking/HTTPClient.swift`: `send` builds a request, executes
  `URLSession.data(for:)`, validates status, then decodes the complete response.
- `NetworkRequestBuilder.swift`: static/generated URLs, user agent, request
  headers, and bearer authentication. Explicit request headers take precedence.
  The builder alone does not invoke `HTTPClientDelegate` preparation.
- `OfflineRequestQueue.swift`: application-owned durable request replay, not
  background URLSession file transfer. Its replay rules must remain separate.
- Clickwheel, under `/Users/justinwilliams/src/justin/jellyfin-audio`:
  `Main Application/App - iOS/Model/BackgroundAudioTransfers.swift`,
  `OriginalAudioLoader.swift`, `AudioDownloads.swift`, and
  `Packages/ClickwheelNetworking/Sources/ClickwheelNetworking/MusicServerTransport.swift`.
  Downloads use stable session/task identities and synchronously move temporary
  files. Playback validates 206 and Content-Range before delivering chunks.
- togetherMade backend, under `/Users/justinwilliams/src/togethermade/togetherMade`:
  `api/src/controllers/uploads/uploads.controller.ts` accepts authenticated
  multipart `file` uploads and returns `{ url }`. Attachments allow 50 MiB;
  channel/monitor images allow 10 MiB. `user.controller.ts` allows 5 MiB avatars.
  Each accepted attachment upload generates a fresh object name.
- `api/src/services/uploader/uploader.service.ts` buffers uploads and reads.
  Hosted disabled uploads return 503; local disabled uploads return a potentially
  large inline data URL. There is no signed-upload or multipart-storage protocol
  in the audited path.
- `api/src/controllers/threads/threads.controller.ts` and
  `api/src/services/threads/thread.service.ts` authorize retained-file reads
  through content visibility. Responses use private/no-store; non-image files
  are octet-stream attachments. This is sufficient to transport a complete video
  file, not proof that its codec is playable.
- `/Users/justinwilliams/src/togethermade/mobile-ios` has no media upload pipeline
  or attachment fields in its audited publication models. Native authentication
  uses explicit refresh and avoids automatic replay.
- `infra/runtime/main/services.tf` disables hosted uploads pending approved and
  verified private delivery. This is checked-in configuration, not live proof.

## Public API design

The library contracts below are implemented in the working tree. Existing
initializers, templates, send behavior, decoding, and errors remain compatible.
Do not introduce dependencies, a universal transfer protocol, or a new database.

### Shared preparation and validation

Extract private helpers from HTTPClient so each new submission uses the same
builder/authentication/header precedence and then invokes the preparation delegate
exactly once. Preserve the ordinary-send and durable-replay distinctions. Do not
silently add refresh-on-401. Validate non-HTTP responses and non-2xx statuses using
existing JWWNetworkError cases; preserve underlying transport cancellation errors.
File operations can use the existing untyped error wrapper for local I/O failure.

Transport submission after preparation must check cancellation before creating or
resuming the task. Restoration reconnects existing tasks; it must not rebuild,
reauthenticate, or replay their original requests. A new user retry is a new task.

### Foreground HTTPClient additions

1. `upload(template:fromFile:progress:) async throws(JWWNetworkError) -> T.Output`.
   Send the supplied file with Foundation's file-upload operation, validate the
   response, and use existing decoding. Report sent/expected byte counts, allowing
   an unknown total. Cancel the request when its calling task is cancelled.
   Reject an existing Data body or body stream after preparation rather than
   silently replacing it. The caller retains an immutable source file through
   completion. The response remains buffered, as with send; document this limit.
2. `stream(template:receiveResponse:receiveData:) async throws(JWWNetworkError)`.
   Deliver HTTP headers before ordered Data chunks; allow the response handler to
   reject a response before body delivery. Await serialized Sendable callbacks.
   EOF completes the method. Cancellation or callback failure stops transport.
   Never replay a partial response. Template Output decoding is bypassed.

Use a dedicated serial Foundation data-delegate session for each stream, copying
the client's configuration and forwarding redirects and authentication challenges
to its delegate on its delegate queue. Other delegate events are not forwarded.
The adapter awaits one async callback at a time on its own OperationQueue, suspends
transport during body consumption, and keeps no body buffer or callback backlog.
It never blocks the original session queue or an actor executor. Small chunks are
delivered promptly; AVFoundation remains on the app's loading queue.

Implementation evidence: fixed-size AsyncBytes batching would delay partial
chunks. A per-task asynchronous delegate with a bounded queue overflowed on the
8 MiB loopback case despite task suspension. The dedicated serial queue passes
that case, small-chunk-before-EOF, slow-consumer nested requests, cancellation,
and redirect refusal tests without a custom channel or scheduler. Foundation
still owns its native transport buffers; these tests are not a peak-memory benchmark.

A separate foreground download convenience is deferred: both concrete durable
download consumers can use the session adapter below.

### Background HTTPTransferSession

Use one focused session owner with distinct upload/download operations. Sharing
this plumbing is justified by the two applications, not hypothetical transports.
Keep it a thin adapter over Foundation tasks and delegate callbacks. Foundation
owns transfer scheduling and execution; the adapter must not introduce a custom
scheduler, retry engine, persistence layer, or extensible event framework.

Proposed surface:

- Initialize with a caller-supplied background URLSessionConfiguration, HTTPClient
  for preparation, fixed callbacks, and upload-response byte limit.
- `startDownload(template:id:)` and `startUpload(template:fromFile:id:)` prepare,
  create a task, set an opaque caller identity, and resume it. Return the task
  snapshot only after submission. The caller must journal its intent first.
- `tasks()` returns Sendable snapshots: session/task identity, caller ID, kind,
  state, sent/received counts, and optional expected counts. Avoid exposing mutable
  URLSessionTask objects as the primary API.
- `cancel(id:)` cancels matching submitted tasks. No pause/resume-data API yet.
- Fixed callbacks receive progress, download file handoff, upload response completion,
  terminal failure, and background-events-finished notification.
  Use one callback bundle; no subscriber registry, event bus, pluggable transport
  protocol, or generic event pipeline.

Use a Sendable byte-progress value with direction and optional total. Task
description contains only an opaque identity, never tokens or account details.
One session identifier has one live owner. Install callbacks before
reconnecting the system session so restored events cannot race an absent handler.

The delegate bridge serializes mutable task state and terminal delivery. Avoid
unstructured task creation for every progress event. A task produces at most one
terminal result per live delivery sequence; this is not a cross-process exactly-once
guarantee. Callers reconcile their journals and completed files/results on launch.

Download completion validates HTTP status, then synchronously invokes a throwing
file-claim callback before Foundation deletes its temporary file. The caller chooses
and moves to its staging destination. Never actor-hop with an unclaimed temporary
URL. A later asynchronous callback performs integrity checking and installation.
If no owner can claim a file, fail explicitly; do not report success or choose an
arbitrary permanent destination. The app must provide a thread-safe destination
lookup before reconnecting, rather than synchronously blocking on its main actor.

Upload completion collects response data with a configured finite bound and returns
HTTPURLResponse plus Data; the application decodes and durably records its receipt.
Choose a documented small default (1 MiB) with caller override for known contracts.
Exceeding the bound cancels body collection and reports failure without retry: the
server may already have committed the upload. Local inline-data responses need a
deliberate larger test configuration or an enabled test storage backend.

The library signals that Foundation finished background events. The application
invokes UIKit's completion handler only after its restoration, receipt persistence,
file processing, and outstanding callbacks finish. UIKit and application lifecycle
objects remain outside JWWNetworking. Never acknowledge merely because bytes ended.

Preserve configuration for cellular access and scheduling. Background sessions
follow redirects regardless of the redirect delegate; document this limitation
and never advertise strict redirect refusal. Foreground consumers retain their
configured redirect behavior. Do not introduce global URLSession delegate changes.

## Ownership and failure semantics

JWWNetworking owns transport preparation, HTTP checks, byte delivery, progress,
cancellation, session reconnection, and safe temporary-file handoff.

Applications own queue scheduling, accounts, durable intent/result journals,
source-file lifetime, destinations, integrity/media validation, offline retention,
cleanup, UI, and the meaning of a retry. No transfer is submitted to
OfflineRequestQueue, and no Idempotency-Key is invented by this feature.

Synchronous file handoff, durable app-owned upload receipts, account isolation,
and explicit ambiguous-outcome handling are required correctness safeguards.
Keep them even when simplifying the adapter; do not move their application policy
into a library persistence or workflow abstraction.

togetherMade's starter upload state machine is:

`prepared -> submitted -> uploaded(receipt) -> attached to published content`.

A transport failure after submission, cancellation after submission, missing result
on restoration, or unusable/oversized successful response can become `outcome
unknown`. Keep the source and draft. Do not publish without a valid persisted URL.
Offer explicit retry as another upload, explaining that an extra stored copy may
result. Never claim cancel deleted a remote object. A definite HTTP rejection is
reported separately; it still does not trigger automatic retry.

Persist the upload URL before starting publication. Retry publication using its
existing submission identity and already-uploaded URL rather than uploading again.
A process death after remote commit but before local receipt persistence remains
ambiguous; the starter deliberately does not solve that with a receipt database in
JWWNetworking. Server upload identities, reconciliation, and orphan cleanup are
separate future backend work.

## Implementation sequence and acceptance

Checked items below describe local implementation and passing checks, not merged
or deployed work. Each track is independently reviewable; library completion does
not close app, backend, or physical-device acceptance.

### L1 — Toolkit preparation compatibility

- [x] Add regression coverage before extracting private preparation/status helpers.
- [x] Preserve explicit headers, authentication errors, delegate order/errors,
  ordinary-send decoding, transport errors, and durable replay guards.
- [x] Verify no automatic retry/refresh and no changes to public existing APIs.

### L2 — Toolkit foreground upload and streaming

- [x] Implement the two HTTPClient methods and progress value with public docs.
- [x] Test file-body conflicts, empty/missing files, HTTP errors, decoding, progress,
  cancellation before dispatch and during transfer, and source-file expectations.
- [x] Test headers before chunks, response rejection, ordered incremental delivery,
  slow consumers, midstream errors, callback failure, and cancellation.
- [x] Use a controlled local HTTP server for chunk timing, redirects, actual upload
  bytes, and an 8 MiB response consumed without accumulating chunks in the consumer. Existing MockNetwork explicitly does not
  simulate streaming or redirects; extend only narrowly or use private test fixtures.

### L3 — Toolkit background downloads and uploads

- [x] Implement the thin session owner, serialized delegate bridge, snapshots, and
  fixed callbacks using Foundation tasks. Review that no custom scheduler, retry
  engine, persistence layer, or extensible event framework has been introduced.
- [x] Test identity assignment before resume, restored snapshot mapping, unknown
  lengths, cancellation/completion races, bounded upload responses, non-2xx errors,
  synchronous file claiming, failed file moves, and terminal notifications. Snapshot
  tests exercise the in-process reconciliation API, not actual daemon restoration.
- [x] Document source/result lifetime, app acknowledgement duties, lack of automatic
  replay, redirect limitations, and force-quit versus system-termination behavior.
- [x] Retain existing deployment targets. Verify SDK availability for each target;
  narrowly gate background APIs where needed rather than raising package minimums.
- [x] Run swift build, swift test, SwiftLint, and DocC generation/symbol validation.
- [x] Run the repository's all-platform test matrix using installed compatible
  simulator destinations. macOS/iOS/tvOS/visionOS pass; watchOS has existing mock-network
  failures reproduced on unchanged main. See evidence below; the matrix is not all green.

### C1 — Clickwheel integration (separate application change)

- [ ] Replace BackgroundAudioTransfers transport plumbing with HTTPTransferSession,
  retaining the existing background session identifier and task descriptions so
  in-flight downloads can reconnect across the app update.
- [ ] Preserve AudioDownloads journal/account reconciliation, staging destinations,
  SHA-256 and byte-count checks, playability checks, installation, and Live Activity
  processing before background acknowledgement.
- [ ] Move OriginalAudioLoader network transport to stream, preserving exact Range
  construction, 206/Content-Range checks, serial AVFoundation delivery, and per-load
  cancellation. Audio playback remains incremental; togetherMade's video decision
  does not change Clickwheel playback.
- [ ] Resolve Clickwheel's strict-redirect expectation before migration: its current
  background delegate cannot enforce refusal. Do not silently promise that it can.

### T1 — togetherMade iOS application (separate track)

- [ ] Add attachment input/output models, media selection, and deterministic metadata.
  Keep 50 MiB attachments and existing endpoint-specific image limits.
- [ ] Export picked assets to account-owned storage; construct multipart bodies on
  disk with field name file, safe filename, MIME type, and matching boundary header.
  JWWNetworking sends the completed body file without media-specific knowledge.
- [ ] Add a durable app journal linking opaque task IDs to drafts, source/multipart
  files, account, upload receipt, and outcome state. Restore before attaching events.
- [ ] Wire background upload progress/cancellation and explicit retry UI. Preserve
  explicit refresh, cookie-free requests, and no replay after a 401 or uncertain send.
- [ ] Persist the returned URL before submitting attachment metadata with a post or
  reply. Do not automatically publish a draft merely because an upload completed.
- [ ] Download authorized content to account-owned staging; validate completion and
  media playability, then atomically install into the offline store. Use returned
  metadata/length where available; do not invent a checksum the server does not supply.
- [ ] Play videos only from complete local files. Keep image presentation, media
  decoding, AVFoundation, offline indexing, and storage UI outside the library.
- [ ] Retain installed files across launches; default to purging account files on
  sign-out/account deletion, never exposing them to another account. Provide explicit
  removal. Confirm quota/eviction and permission-revocation rules before shipping;
  offline content cannot immediately learn that remote access was revoked.
- [ ] Resolve protected relative URLs against the API origin; never attach bearer
  credentials indiscriminately to external URLs. Preserve private delivery semantics.
- [ ] Add model, multipart, journal, unknown-outcome, and account-switch tests; run
  Shared Code and app tests on iOS Simulator using the repository's documented scheme.

### T2 — togetherMade backend and deployment (separate track)

- [ ] Confirm/document authenticated upload and retained-file download contracts,
  supported image/video formats, filename/type metadata, and offline retention policy.
  Treat generic video MIME acceptance as storage support, not codec validation.
- [ ] Verify complete video downloads are usable with published attachment metadata.
  Keep the authorized file route; no signed public URL bypass or range endpoint is
  required by download-before-play. Retain no-store for ordinary HTTP caching and
  explicitly document app-managed offline copies and their authorization limits.
- [ ] Test 50 MiB boundary rejection/acceptance, multipart field requirements, bearer
  auth, HTTP failures, attachment publication, unauthorized reads, removed content,
  and image/video readback with disposable storage fixtures.
- [ ] Keep disabled-upload tests and the local inline-data distinction. Enabling
  hosted uploads requires a separate approved deployment with private read delivery
  verified; this plan changes no environment flags, credentials, bucket policies,
  or infrastructure.
- [ ] Record duplicate/orphan-object behavior as an accepted starter limitation.
  Upload IDs, idempotency, reconciliation endpoints, and cleanup jobs are deferred.
- [ ] Run relevant API HTTP/persistence integration tests in the mandated disposable
  container workflow; regenerate clients only if the HTTP contract changes.

### A1 — Runtime acceptance, separately tracked

- [ ] Local server: verify real file uploads/downloads, chunk timing, headers,
  cancellation, redirects, and bounded client memory. Unit mocks prove none of the
  system background lifecycle guarantees.
- [ ] Simulator: exercise app wiring, task restoration reconciliation, offline video
  playback, draft publication separation, cleanup, and delayed acknowledgement.
- [ ] Physical iPhone, without debugger dependence: background/suspend, OS process
  termination and relaunch, locked-device file access, network loss/recovery,
  expired credentials, cancellation races, and background upload response delivery.
- [ ] Upgrade with in-flight Clickwheel downloads; confirm old tasks reconnect.
- [ ] Terminate togetherMade around remote upload completion/local receipt save;
  confirm unknown-outcome UI and no automatic resubmission.
- [ ] Test user force-quit separately and describe expected cancellation; do not
  present it as evidence against ordinary OS-termination restoration.
- [ ] Approved hosted acceptance: private image/video upload/readback and offline
  replay, account isolation, and object access checks. Local success is not deployed
  proof. Track failures and unrun checks explicitly.

## Remaining decisions and exclusions

Accepted: background uploads, offline retention, complete-file video playback,
50 MiB attachments, and explicit user retry for ambiguous uploads.

Before app release, settle offline storage quota/eviction and access-revocation
expectations, allowed playable formats/export policy, and Clickwheel's background
redirect requirement. These do not justify changing existing behavior silently.

Excluded: automatic upload retries, offline-queue replay of uploads, resumable
upload protocols, explicit download resume data, progressive togetherMade video,
transcoding/HLS, server upload deduplication, signed-upload APIs, and a generic media
framework. App migration, infrastructure activation, commits, and publication are
outside the current toolkit implementation request.

## Local implementation evidence — 2026-11-09

Working-tree implementation (uncommitted): shared HTTPClient preparation/status
helpers; foreground file uploads; incremental streaming; HTTPTransferSession and
its fixed callback bridge; byte progress and task snapshots; public DocC guidance;
loopback HTTP and preparation regression tests. No app or backend files changed.

Passed:

- `swift build` and `swift test` (macOS), including 20 transfer tests in two suites
  and the existing ordinary-request/offline-queue regression suites.
- `swiftlint lint --config .swiftlint.yml`: no new violations; ten existing warnings
  in ScopedMockURLProtocol and FormatStyleExtensionsTests remain outside scope.
- `swift package --allow-writing-to-directory /tmp/jww-transfers-docc
  generate-documentation --target JWWNetworking --output-path /tmp/jww-transfers-docc`:
  archive generated without DocC warnings.
- iPhone 17 simulator, iOS 27.2: full package xcodebuild test suite passed after
  Justin fixed the SwiftLint plugin trust issue.
- Full package Xcode tests on macOS, Apple TV 4K (3rd generation) / tvOS 27.0,
  and Apple Vision Pro / visionOS 27.0.
- All 20 new transfer tests on Apple Watch Series 11 / watchOS 27.0. The full
  watchOS suite failed in existing HTTPClientTests and DeprecatedNetworkCompatibilityTests;
  a separate unchanged HEAD (`9867b4f`) archive reproduced mock-network failures.
  Mocked requests reached real networking (DNS/connect errors and unused mock outcomes).
  These existing test failures remain unresolved; do not claim a passing watchOS suite.
- SwiftPM SDK compilation of JWWNetworking for iOS 18.4, tvOS 18.4, and watchOS 11.4
  simulator targets. These are compilation checks, not runtime acceptance.

The exact VS Code matrix command first failed because its named iPhone 17 Pro was
absent. Compatible temporary tvOS/watchOS/visionOS devices were used instead.
A combined remaining-destinations invocation crashed inside Xcode
`IDEXCBuildServiceBuildOperation.performBuild()`; each destination was then tested
separately. SwiftPM's native visionOS cross-build constructed a
malformed target version (`xros2.415.4`); the passing Xcode visionOS suite supersedes
that failed cross-build attempt. Validation logs are in `/tmp/jww-transfer-*.log`
and `/tmp/jww-transfers-*.log`. The three temporary validation simulators were
removed afterward; existing simulators were retained.

Physical-device background restoration, locked-device file access, app-owned result
persistence/acknowledgement, upgrade migration, and hosted integration remain in A1.
The unit-level background-event notification test proves callback forwarding only.
No commit, publication, application migration, or hosted mutation has occurred.

### PR review follow-up — 2026-11-09

The upload delegate-policy finding did not reproduce. Two real loopback regression
checks exercise session-level redirect refusal and task-level Basic authentication
cancellation while the upload uses its progress-only task delegate. Both pass
without production changes: Foundation falls back to the session delegate for
these unimplemented task-delegate methods. Explicit forwarding is unnecessary.

The transfer suites now contain 22 tests. Follow-up validation passed: full
`swift test`, SwiftLint (the same ten existing warnings), and the iOS 27.2
HTTPTransferTests Xcode suite. The earlier platform results apply to unchanged
production code; other simulator suites were not repeated for this test-only
follow-up. Background physical-device acceptance remains pending.
