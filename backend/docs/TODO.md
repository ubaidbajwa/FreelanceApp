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

## Messaging — deferred features (see ADR 0004)

M1 ships 1:1 text messaging (REST writes + SignalR fan-out). The following are intentionally out of scope for M1, each with the trigger for picking it up:

- [ ] **Multi-instance SignalR backplane** — trigger: a second API instance is deployed. Migration: add `Microsoft.AspNetCore.SignalR.StackExchangeRedis`, point it at the existing Upstash Redis connection. No application code change. See ADR 0004 §3.
- [ ] **Per-message read receipts** — trigger: group chat needs per-member, per-message "seen" state. Migration: add a `MessageRead { MessageId, UserId, ReadAt }` table alongside the existing `LastReadAt` watermark. See ADR 0004 §4.
- [ ] **Video calling** — needs WebRTC or a provider (Agora / Twilio); a separate module, not an extension of messaging. Trigger: product commits to in-app calls.
- [ ] **EN ⇄ UR auto-translation** — needs a translation provider integration plus a per-message cost model (who pays, caching translated bodies, on-demand vs. eager). Trigger: cross-language usage is validated as a real need.
- [ ] **Voice messages** — needs audio recording (client), audio blob storage (Cloudinary or S3), and waveform rendering UI. The `MessageType.Voice` enum value already exists so this is additive. Trigger: voice is prioritized.
- [ ] **Group chat** — the join-table participant model (`ConversationParticipant`) is additive-ready, **but `ConversationRepository.ProjectSummary` is NOT.** The conversation-list query resolves "the other participant" with a single-counterpart join (`INNER JOIN (SELECT … FROM "ConversationParticipants" WHERE "UserId" <> @me) ON "ConversationId"`). With exactly two participants that yields one row per conversation; with **3+ participants it yields N−1 rows per conversation**, so the same thread would appear multiple times in the list — once per other member. Required work before group chat: introduce a conversation-level title/avatar concept, or replace the single-counterpart join with an **aggregated** participant projection (e.g. member count + a few sample avatars), so each conversation is exactly one list row regardless of member count. Trigger: group conversations are prioritized. Pairs with per-message read receipts above. See ADR 0004 §4.
- [ ] **`MessageRequestPolicy`** — a messaging equivalent of the existing `ConnectionInvitePolicy` (who may send you a message request). NOTE: `ConnectionInvitePolicy` deliberately governs **connection invites only** and is **not** applied to message requests in M1 — message requests are open to anyone in M1, gated only by the pending 1-message rule. Trigger: message-request spam becomes a problem. Migration: additive nullable enum column on `Profile`, enforced in `ChatService.StartOrGetConversationAsync`, mirroring the `ConnectionInvitePolicy` enforcement in `ConnectionService`.

## Messaging — message-cursor precision (verified, NOT currently a bug)

`GetMessagesAsync` orders by `(CreatedAt DESC, Id DESC)` but the keyset cursor is `CreatedAt` **only** and the comparison is strict (`CreatedAt < before`). Two messages sharing an identical `CreatedAt` that straddle a page boundary would drop one row (a gap). Verified the full precision chain to decide whether this is reachable:

- **DB column:** `Messages.CreatedAt` is `timestamp with time zone` with **no precision specifier** → Postgres stores **microseconds** (6 fractional digits), not `timestamp(3)`.
- **JSON out (System.Text.Json, default — no custom `JsonOptions` in `Program.cs`):** emits full round-trip precision, up to 7 fractional digits, trailing zeros trimmed. Real example: `"createdAt":"2026-08-04T12:34:56.1234567Z"`.
- **Query-string model binding of `DateTime? before`:** preserves microseconds exactly — bound a 6-digit value back through the `DateTime` `TypeConverter`, **0 ticks lost**.
- **Postgres round-trip:** stored/returned at microsecond precision (the .NET 100ns/7th digit is truncated to 6 by the column; that is finer than millisecond, so irrelevant here). Derived from the confirmed column type + documented Npgsql/Postgres behavior; the live Neon DB was **not** queried (avoid touching production data).

**Verdict: no millisecond truncation anywhere in the chain.** The tightest precision is Postgres microsecond; JSON and model binding are finer and lossless. Two *human-typed* messages colliding within the same microsecond is not realistically reachable, so the composite-cursor change is **not** taken this pass.

- [ ] **Composite cursor (`before` + `beforeId`) — conditional, low priority.** Trigger ANY of: (a) `Messages.CreatedAt` is ever redefined to `timestamp(3)`/millisecond, (b) messages start being machine-generated / bulk-inserted (system messages, imports, seeded fixtures) where same-microsecond collisions become plausible, or (c) a real "skipped message at page boundary" report appears. Options when triggered: **(1)** composite keyset cursor `(CreatedAt, Id)` — cursor carries both `before` and `beforeId`, WHERE becomes `(CreatedAt < before) OR (CreatedAt = before AND Id < beforeId)`; or **(2)** a monotonic `Seq bigint` sequence column ordered/cursored on alone. NOTE: either **changes the public cursor contract** (`MessagePageDto.NextCursor` shape) and the Flutter client, so it must be a deliberate versioned slice, not a silent change.

## Deployment blockers

- [ ] **HTTPS/WSS required in production — blocker, not a nice-to-have.** SignalR passes the JWT as a `?access_token=` **query-string** parameter (the browser WebSocket API cannot set an `Authorization` header). Query strings are written to server access logs and any intermediate proxy/CDN logs, so over plain HTTP the token is logged in cleartext at every hop. The current dev setup is plain HTTP on `localhost:5186`. Production must terminate TLS and serve the hub over `wss://` so the token only ever travels inside the encrypted channel. Also scope: set access-token log redaction / short token TTL as defense-in-depth.
