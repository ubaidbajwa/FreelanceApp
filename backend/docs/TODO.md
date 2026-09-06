# TODO

## Suggestion Ranking (see ADR 0001)

Revisit signal-driven candidate selection + in-memory weighted scoring when ANY of:

- [ ] `MaxCandidates` cap warning fires regularly in production logs — means real candidates are being dropped
- [ ] p95 latency of `GET /api/network/suggestions` exceeds 300 ms
- [ ] Total registered users exceed ~100 k
- [ ] A/B test shows meaningful CTR lift from an ML-ranked scorer

Migration path: new `ISuggestionScorer` + precomputed scores table + background job + enable `RedisSuggestionCache` via `CacheSeconds > 0`. See ADR 0001 for full details.

## Follow Suggestion Ranking (see ADR 0003)

Revisit three-query signal union + in-memory weighted scoring for `GET /api/network/follow-suggestions` when ANY of:

- [ ] p95 latency of `GET /api/network/follow-suggestions` exceeds 300 ms
- [ ] `Follows` table exceeds ~1 M rows (Query C runs a global GROUP BY on every request)
- [ ] `MaxCandidates` cap warning fires regularly in production logs — real candidates are being dropped

Migration path: cache the top-popular list via `ISuggestionCache` (seam already exists, currently NoOp), or maintain a materialized view of top-N followed users refreshed by a background job. See ADR 0003 for full details.

## Auth / email hardening — deferred (see ADR 0005)

Rate limiting and off-request-thread email shipped in the M-Sec slice. The following are intentionally deferred, each with its trigger:

- [ ] **Distributed rate limiter** — trigger: a second API instance is deployed. The built-in limiter counts **per process**, so N instances allow N× every limit (an attacker just spreads attempts across nodes). Migration: back the limiter with the existing Redis (a distributed fixed-window/token store) so the ceiling is global. The `RateLimitSettings` values and policy names are unaffected — only the partition store changes. See ADR 0005 §1.
- [ ] **Database outbox for transactional email** — trigger: a lost email becomes a **correctness** problem rather than an inconvenience (payment receipts, legal notices, invoices). Today auth email uses a bounded in-process `Channel<T>` (`DropOldest`), so a process crash drops in-flight OTP/reset mail — acceptable because the user simply requests another. Migration: persist the email intent in a DB `EmailOutbox` table inside the same transaction as the triggering write, and have a relay worker send + mark sent. The `IEmailQueue` seam is where it swaps in. See ADR 0005 §2.
- [ ] **Hash the password-reset / verification OTP at rest** — trigger: OTP flows carry higher-value actions, or a security review mandates it. `EmailOtp.Code` is currently stored **plaintext** and compared directly. For a 6-digit, 10-minute, 3-attempt, single-use code with per-account + per-IP rate limits this is low-risk, but a DB read still exposes live codes. Fix: store a hash (e.g. SHA-256 — a 6-digit space doesn't need a slow KDF), email the plaintext, and compare hashes on verify. Structural: touches `OtpService`, the `AuthService` verify paths, and the OTP test suite — its own slice, not bundled into rate limiting. See ADR 0005 §2.

## Messaging — deferred features (see ADR 0004)

M1 ships 1:1 text messaging (REST writes + SignalR fan-out). The following are intentionally out of scope for M1, each with the trigger for picking it up:

- [ ] **Multi-instance SignalR backplane** — trigger: a second API instance is deployed. Migration: add `Microsoft.AspNetCore.SignalR.StackExchangeRedis`, point it at the existing Upstash Redis connection. No application code change. See ADR 0004 §3.
- [ ] **Per-message read receipts** — trigger: group chat needs per-member, per-message "seen" state. Migration: add a `MessageRead { MessageId, UserId, ReadAt }` table alongside the existing `LastReadAt` watermark. See ADR 0004 §4.
- [ ] **Video calling** — needs WebRTC or a provider (Agora / Twilio); a separate module, not an extension of messaging. Trigger: product commits to in-app calls.
- [ ] **EN ⇄ UR auto-translation** — needs a translation provider integration plus a per-message cost model (who pays, caching translated bodies, on-demand vs. eager). Trigger: cross-language usage is validated as a real need.
- [ ] **Voice messages** — needs audio recording (client), audio blob storage (Cloudinary or S3), and waveform rendering UI. The `MessageType.Voice` enum value already exists so this is additive. Trigger: voice is prioritized.

- [ ] **Cloudinary asset cleanup for media messages (M-M4) — orphans accumulate after delete-for-everyone.** Delete-for-everyone tombstones a media message and blanks `MediaUrl`/`MediaThumbnailUrl` in the projection, but deliberately does **NOT** delete the underlying Cloudinary asset. Reason: a **forward reuses the same `MediaPublicId`** (a forward is a reference, not a copy), so deleting the asset when one copy is deleted-for-everyone would break every other copy that still points at it. Consequence: assets whose every referencing message is a tombstone are never reclaimed and accumulate storage cost. Required work before ANY asset can be safely removed: **reference counting on `MediaPublicId`** — an asset may be destroyed only when no live (non-tombstone) message references that public id. Migration when triggered: a background reconciliation job (or a counted-delete on the last reference) that `COUNT`s live references per `MediaPublicId` and calls `IMediaStorageService.DeleteAsync` only at zero. **Trigger:** Cloudinary storage cost / quota becomes material, OR a storage-usage alert fires. Until then, the safe default is to keep every asset.
- [ ] **Group chat** — the join-table participant model (`ConversationParticipant`) is additive-ready, **but `ConversationRepository.ProjectSummary` is NOT.** The conversation-list query resolves "the other participant" with a single-counterpart join (`INNER JOIN (SELECT … FROM "ConversationParticipants" WHERE "UserId" <> @me) ON "ConversationId"`). With exactly two participants that yields one row per conversation; with **3+ participants it yields N−1 rows per conversation**, so the same thread would appear multiple times in the list — once per other member. Required work before group chat: introduce a conversation-level title/avatar concept, or replace the single-counterpart join with an **aggregated** participant projection (e.g. member count + a few sample avatars), so each conversation is exactly one list row regardless of member count. Trigger: group conversations are prioritized. Pairs with per-message read receipts above. See ADR 0004 §4.
- [ ] **`MessageRequestPolicy`** — a messaging equivalent of the existing `ConnectionInvitePolicy` (who may send you a message request). NOTE: `ConnectionInvitePolicy` deliberately governs **connection invites only** and is **not** applied to message requests in M1 — message requests are open to anyone in M1, gated only by the pending 1-message rule. Trigger: message-request spam becomes a problem. Migration: additive nullable enum column on `Profile`, enforced in `ChatService.StartOrGetConversationAsync`, mirroring the `ConnectionInvitePolicy` enforcement in `ConnectionService`.

## Messaging — read receipts (M-RR shipped: watermark exposure + notify; follow-ups deferred)

M-RR exposed the existing `ConversationParticipant.LastReadAt` watermark to the other party
(`ConversationSummaryDto.otherLastReadAt`, caller-relative) and added a `ConversationRead` SignalR
event fired from `MarkReadAsync` to the other participant only. The client renders **two** tick
states from this. The following are intentionally deferred:

- [ ] **`ReadReceiptsEnabled` profile setting (privacy) — not built. Covers BOTH read AND played
  receipts.** Read receipts (`LastReadAt` / `otherLastReadAt`) and voice "played" receipts (M-M7's
  `MessagePlay` / `playedByOther`) are the **same class of privacy signal** — both tell the other
  party what you did with their message — so a single toggle must govern both. They are
  privacy-sensitive; WhatsApp and LinkedIn both let users turn them off, and Skillora already has a
  `ConnectionInvitePolicy` precedent for per-user privacy settings. **The rule must be symmetric:**
  when a user disables receipts they stop *sending* read **and played** state AND stop *seeing*
  others' read **and played** state. A one-way switch that hides your own activity while you still
  see everyone else's is exactly the version users object to — do not ship that. Migration when
  triggered: additive nullable/boolean column on `Profile` (default enabled), enforced in
  `ChatService.MarkReadAsync` (suppress the `ConversationRead` notify + skip persisting/advancing
  when the reader has receipts off), in `ChatService.MarkPlayedAsync` (suppress the `MessagePlayed`
  notify + skip inserting the `MessagePlay` row when the player has receipts off), and in
  `ConversationRepository.ProjectSummary` / `ProjectMessage` (project `otherLastReadAt` and
  `playedByOther` as false/null when *either* party has receipts off, to keep the symmetry). Trigger:
  users ask for a read-receipt toggle.

- [ ] **Only two tick states are achievable today (✓ sent, ✓✓ read) — by design, do not assume
  three.** The grey "delivered" middle state (✓✓ grey) needs a per-device *acknowledgement*
  mechanism that does not exist: the current `LastReadAt` watermark only knows "read", never
  "arrived on device". Delivery receipts require each recipient device to ACK receipt of a message
  (a new `MessageDelivery`/device-ack concept), which is a separate slice — not an extension of the
  read watermark. Trigger: product commits to a three-state tick UI. Pairs with **per-message read
  receipts** below (both are blocked on richer per-recipient state than a single watermark).

## Messaging — message-cursor precision (verified, NOT currently a bug)

`GetMessagesAsync` orders by `(CreatedAt DESC, Id DESC)` but the keyset cursor is `CreatedAt` **only** and the comparison is strict (`CreatedAt < before`). Two messages sharing an identical `CreatedAt` that straddle a page boundary would drop one row (a gap). Verified the full precision chain to decide whether this is reachable:

- **DB column:** `Messages.CreatedAt` is `timestamp with time zone` with **no precision specifier** → Postgres stores **microseconds** (6 fractional digits), not `timestamp(3)`.
- **JSON out (System.Text.Json, default — no custom `JsonOptions` in `Program.cs`):** emits full round-trip precision, up to 7 fractional digits, trailing zeros trimmed. Real example: `"createdAt":"2026-08-04T12:34:56.1234567Z"`.
- **Query-string model binding of `DateTime? before`:** preserves microseconds exactly — bound a 6-digit value back through the `DateTime` `TypeConverter`, **0 ticks lost**.
- **Postgres round-trip:** stored/returned at microsecond precision (the .NET 100ns/7th digit is truncated to 6 by the column; that is finer than millisecond, so irrelevant here). Derived from the confirmed column type + documented Npgsql/Postgres behavior; the live Neon DB was **not** queried (avoid touching production data).

**Verdict: no millisecond truncation anywhere in the chain.** The tightest precision is Postgres microsecond; JSON and model binding are finer and lossless. Two *human-typed* messages colliding within the same microsecond is not realistically reachable, so the composite-cursor change is **not** taken this pass.

- [ ] **Composite cursor (`before` + `beforeId`) — conditional, low priority.** Trigger ANY of: (a) `Messages.CreatedAt` is ever redefined to `timestamp(3)`/millisecond, (b) messages start being machine-generated / bulk-inserted (system messages, imports, seeded fixtures) where same-microsecond collisions become plausible, or (c) a real "skipped message at page boundary" report appears. Options when triggered: **(1)** composite keyset cursor `(CreatedAt, Id)` — cursor carries both `before` and `beforeId`, WHERE becomes `(CreatedAt < before) OR (CreatedAt = before AND Id < beforeId)`; or **(2)** a monotonic `Seq bigint` sequence column ordered/cursored on alone. NOTE: either **changes the public cursor contract** (`MessagePageDto.NextCursor` shape) and the Flutter client, so it must be a deliberate versioned slice, not a silent change.

## Messaging — documents (M-M8): deferred hardening (see ADR 0004 §10)

M-M8 ships document sharing (`MessageType.File`, Cloudinary `raw`) through the existing media endpoint, with an extension/MIME/magic-byte allowlist, filename sanitisation and a 25 MB limit. The following are intentionally deferred, each with its trigger:

- [ ] **Signed / expiring download URLs — a real gap.** A Cloudinary `raw` URL is **publicly reachable by anyone holding the link**, with no expiry — which matters far more for a contract than for a chat photo. The URL is stored on the message and (for a live message) returned on the wire, so a leaked link is a leaked document. **Trigger:** before any public launch, OR once documents are exchanged with parties outside a user's connections. **Migration path:** switch document delivery to **signed, expiring Cloudinary URLs** — store only the `MediaPublicId` and mint a short-TTL signed URL per request (an authenticated `GET .../messages/{id}/download` that 302s to the signed URL), so possession of an old link no longer grants access. `IMediaStorageService` is the seam; the message write path is unaffected.

- [ ] **Virus / malware scanning on upload — not built.** Validation confirms a document's *type* (allowlist + family magic bytes), never that its contents are safe; the server never parses or executes the file (ADR 0004 §10d), which bounds the risk, but a malicious-but-well-formed PDF/Office macro doc still reaches the recipient's device. **Trigger:** worth adding before any public launch, or once documents are exchanged with parties outside a user's connections. **Candidate approach:** a **scanning service invoked on upload** (e.g. ClamAV via an `IMalwareScanner` seam, or a Cloudinary/third-party scan add-on) that runs after the allowlist passes and before the message is persisted — reject on a positive, so an infected file never becomes a live message. Not built this slice.

- [ ] **Document asset cleanup — same orphan deferral as M-M4 media (pre-existing, not new).** Delete-for-everyone tombstones a document and blanks `MediaUrl`/`MediaFileName` in the projection but deliberately does **not** delete the Cloudinary asset, because a forward reuses the same `MediaPublicId` (a reference, not a copy). Documents inherit the existing **reference-counting on `MediaPublicId`** requirement (see the M-M4 "Cloudinary asset cleanup" item above) before any asset can be safely removed. Same trigger and migration path; the `Document → ResourceType.Raw` delete mapping is already correct for when it is built.

## Deployment blockers

- [ ] **HTTPS/WSS required in production — blocker, not a nice-to-have.** SignalR passes the JWT as a `?access_token=` **query-string** parameter (the browser WebSocket API cannot set an `Authorization` header). Query strings are written to server access logs and any intermediate proxy/CDN logs, so over plain HTTP the token is logged in cleartext at every hop. The current dev setup is plain HTTP on `localhost:5186`. Production must terminate TLS and serve the hub over `wss://` so the token only ever travels inside the encrypted channel. Also scope: set access-token log redaction / short token TTL as defense-in-depth.
