# ADR 0004 — Messaging (M1): Cursor Pagination, REST-Writes + SignalR Fan-out, In-Memory Backplane

**Date:** 2026-07-26  
**Status:** Accepted

---

## Decision

The M1 messaging module is built from five deliberate choices:

1. **Cursor pagination for messages, offset pagination for the conversation list.**
2. **REST for all writes; SignalR for server-to-client fan-out only.**
3. **In-memory SignalR backplane** (single API instance).
4. **A single `LastReadAt` watermark per participant** instead of per-message read receipts.
5. **A `ConversationStatus` enum** (`Pending`/`Accepted`/`Declined`) even though the Follow feature deliberately avoided a status enum.

Each is detailed below with its own revisit trigger and migration path.

---

## 1. Cursor pagination for messages, offset for the conversation list

**Decision:** Messages are paged with a keyset cursor (`MessagePageDto { Items, NextCursor, HasMore }`, `?before=<CreatedAt>&limit=`), newest-first, backed by `IX_Messages_ConversationId_CreatedAt`. The conversation list and requests list keep the existing `PagedResult<T>` offset envelope (`?page=&pageSize=`).

**Why:** A message thread is a **live-appending list** — new messages arrive at the head constantly. Offset pagination (`Skip/Take`) over a list that grows underneath the reader duplicates rows (an insert shifts everything down, so page 2 re-shows a row from page 1) or skips them. A keyset cursor anchored on `CreatedAt` is immune: "give me messages older than this timestamp" returns a stable slice no matter how many new messages arrive. The conversation *list* changes far more slowly and is read top-down, so offset is fine and keeps parity with People/Connections/Suggestions. This is the **first cursor-paginated endpoint in the codebase**; `MessagePageDto` is intentionally NOT `PagedResult<T>`.

**Revisit trigger:** A second live-appending list endpoint appears (e.g. a notifications feed) — extract the cursor envelope into a reusable `CursorPage<T>` in `Common/Models` rather than re-deriving it.

**Migration path:** Additive — introduce `CursorPage<T>`, make `MessagePageDto` an alias or thin subtype; no wire change if field names are preserved.

---

## 2. REST for writes, SignalR for fan-out only

**Decision:** Every write (start conversation, send message, accept, decline, mark-read) is a REST endpoint on `ConversationsController`. `ChatHub` has **no client-to-server methods** — it is a one-way push channel. After a write commits, `ChatService` calls the `IChatNotifier` seam to fan out the event.

**Why:** Routing writes through REST reuses the existing FluentValidation auto-validation and the `GlobalExceptionHandler` (RFC 7807 ProblemDetails) with zero duplication. If the hub accepted writes, all of that validation/error machinery would have to be re-implemented inside hub methods. Persist-then-notify also gives a clean durability story: the message is committed before any push, and a notifier failure only logs a warning (a client refetch recovers the missed event) — the request never fails because real-time delivery hiccupped.

**Revisit trigger:** Write latency through REST becomes a user complaint, OR a feature needs genuine client-to-server real-time calls (typing indicators, presence, read-receipt streaming).

**Migration path:** Add narrowly-scoped hub methods for the ephemeral signals only (e.g. `Typing(conversationId)`), keeping durable writes on REST. The `IChatNotifier` seam is unaffected.

---

## 3. In-memory SignalR backplane

**Decision:** `AddSignalR()` with the default in-process backplane. Users are targeted by id (`Clients.Users(ids)` via a `ChatUserIdProvider : IUserIdProvider` that returns the `sub` claim), so a message reaches every device a user is signed in on — without any hand-rolled connectionId dictionary (which breaks on multi-device and is lost on restart).

**Why:** At one API instance, connections all live in one process, so no cross-node message bus is needed. Introducing Redis backplane infrastructure now would be complexity with no payoff.

**Revisit trigger:** More than one API instance is deployed (horizontal scale / load balancing). With the in-memory backplane, a user connected to instance A never receives an event fanned out from instance B.

**Migration path:** Add the `Microsoft.AspNetCore.SignalR.StackExchangeRedis` package and point it at the **existing Upstash Redis connection** (`builder.Services.AddSignalR().AddStackExchangeRedis(<Upstash connString>)`). **No application code changes** — the hub, notifier, provider, and `IChatNotifier` seam are all backplane-agnostic.

---

## 4. `LastReadAt` watermark over per-message read receipts

**Decision:** Each `ConversationParticipant` carries a single nullable `LastReadAt` timestamp. Unread count is `messages WHERE CreatedAt > LastReadAt AND SenderId != me` (one indexed query); `MarkReadAsync` sets `LastReadAt = UtcNow`.

**Why:** Per-message read rows cost one row per (message × recipient) — 1000 messages × 2 users = 2000 rows purely to track "seen". A watermark answers "how many unread" and "up to where have I read" from a single column, with the unread count served by the existing `IX_Messages_ConversationId_CreatedAt` index.

**Revisit trigger:** Group chat requires **per-member, per-message** receipts (e.g. "seen by 3 of 5", avatars under the exact message each member last saw). A single watermark cannot express which specific members saw which specific message.

**Migration path:** Additive — introduce a `MessageRead { MessageId, UserId, ReadAt }` table for the richer receipt UI, keep `LastReadAt` as the cheap unread-count fast path, and populate both.

**Known constraint — the list projection assumes exactly 1:1.** `ConversationRepository.ProjectSummary` resolves "the other participant" with a single-counterpart join (`INNER JOIN (SELECT … FROM "ConversationParticipants" WHERE "UserId" <> @me) ON "ConversationId"`). Two consequences to record next to this 1:1 decision:
- **3+ participants would duplicate list rows.** The join yields N−1 rows per conversation, so a group thread would appear once per other member. The `ConversationParticipant` *table* is group-ready, but this *query* is not — group chat needs an aggregated participant projection (or a conversation-level title/avatar) first. Tracked in `docs/TODO.md`.
- **The join is `INNER`, so a conversation missing a counterpart participant row (a data anomaly) silently disappears from lists** rather than surfacing as a malformed row. This is the correct default for well-formed 1:1 data, but noted here so a "vanished conversation" is diagnosed as a missing-participant-row anomaly, not a mystery.

---

## 5. `ConversationStatus` enum — even though Follow avoided a status enum

**Decision:** Conversations carry a `ConversationStatus { Pending = 0, Accepted = 1, Declined = 2 }` enum column.

**Why the inconsistency with Follow is intentional:** The Follow feature deliberately has no status enum because a follow is a single binary, low-commitment gesture (you follow or you don't) — a status column there would model states that don't exist. Messaging genuinely has **three distinct states**: a pending request, an accepted thread, and a declined request. Critically, **`Declined` must persist** — it is what blocks a rejected initiator from re-sending (repeat-spam prevention). A soft/implicit "no relationship" state (as Follow uses) cannot enforce that, because there'd be nothing recording that the recipient said no. Three real states + a state that must be durable to enforce a rule = an enum is the correct model here.

**Revisit trigger:** A fourth state is needed (e.g. `Blocked`, `Archived`). Enum values are additive; the existing rows are unaffected.

**Migration path:** Additive enum member + additive migration (nullable/defaulted column changes only), following the same pattern as `AvailabilityStatus`/`ConnectionInvitePolicy`.

**List membership is interpreted caller-relative, not by raw status.** The same `Pending` conversation belongs in different lists depending on who is asking, because "request" is the *recipient's* framing, not an intrinsic property of the row:

- **The caller's own outgoing pending thread appears in their conversations list** (`GetAcceptedPageAsync`), not in a separate "sent" tab and not hidden. From the sender's side they simply opened a conversation and messaged into it — modelling their own message as something needing their own approval would be wrong. Predicate: `LastMessageAt != null && (Status == Accepted || (Status == Pending && InitiatorId == caller))`. `IsRequest` is computed caller-relative (`Status == Pending && InitiatorId != caller`), so it is correctly **false** for these self-initiated rows and **true** only in the recipient's `GetPendingRequestsPageAsync` view of the identical row.
- **Declined threads are excluded from both lists for both parties.** The initiator learns their request was rejected from the *absence* of a reply, not from a lingering declined row in their list; the recipient obviously doesn't want it either. This also composes with the `Declined`-persistence rule above: the row must survive (to block re-sends) but must not be *listed*.
- **Message-less threads (`LastMessageAt == null`) are excluded from both lists** but remain individually fetchable via `GET /api/conversations/{id}` — a freshly created get-or-create thread must resolve for a cold deep link / push-notification tap before any message exists. The single-get endpoint therefore deliberately omits the `LastMessageAt != null` filter that the list queries apply.

---

## 6. Message actions (M1.2): two delete semantics, a capped pin list, server-enforced time windows

**Decision:** The WhatsApp-style message actions (reactions, reply, edit, pin, delete, forward) were added as one additive migration (`AddMessageActions`). Three sub-decisions are load-bearing:

### 6a. "Delete for me" vs "delete for everyone" are different mechanisms, not one flag with a scope

- **Delete for everyone** sets the existing `Message.DeletedAt`. The row survives as a **shared tombstone**: both participants see "This message was deleted". The message-page projection now *includes* tombstoned rows but blanks the body **in SQL** (`CASE WHEN "DeletedAt" IS NULL THEN "Body" ELSE '' END`) and sets `isDeleted = true` — the original text never leaves the database. Own messages only, within a 48h window, idempotent, and it fires a `MessageDeleted` realtime event.
- **Delete for me** inserts a `MessageDeletion { MessageId, UserId }` row. That row's *existence* excludes the message from **that user's** page only (`WHERE NOT EXISTS (… MessageDeletions …)`); the other participant's view is untouched. Any visible message (own or not), no time window, idempotent, and it fires **no realtime event** — a delete-for-me is private to that user, and pushing it would leak their private deletion to the other party.

Modelling both as one "delete with a scope flag on the message" would be wrong: delete-for-me is inherently *per-user* and cannot live on the shared row. The two are a shared-column tombstone vs a per-user join row precisely because their visibility scopes differ.

### 6b. Pin list: cap 4, timed durations, query-time expiry, replace-oldest, system messages

#### Cap raised 3 → 4

Any participant may pin any message (pinning is conversation-scoped, not ownership-scoped). The cap is **`MaxPinnedPerConversation = 4`** (raised from 3 to match WhatsApp parity). Beyond the cap the endpoint returns `409`; a caller may pass `ReplaceOldest = true` to atomically free a slot instead. An uncapped pin list is a second unbounded message list — the cap keeps `GET /pinned` bounded (and it reuses the same message projection, so it inherits the no-N+1 shape).

#### Three pin durations — stored as a UTC expiry timestamp, not an enum

The caller picks a duration at pin time:

| `PinDuration` enum | Window constant | Stored as |
|---|---|---|
| `TwentyFourHours = 0` | `ChatService.PinWindow24Hours` | `UtcNow + 24 h` |
| `SevenDays = 1` | `ChatService.PinWindow7Days` | `UtcNow + 7 d` |
| `ThirtyDays = 2` | `ChatService.PinWindow30Days` | `UtcNow + 30 d` |

The computed absolute UTC deadline is stored in `Message.PinExpiresAt` (nullable). The enum value itself is **not** persisted — storing the deadline rather than the choice is simpler to query, requires no second lookup, and is unambiguous if the window constants ever change.

#### Query-time expiry — no background sweeper

Expired pins are excluded at read time with `(PinExpiresAt IS NULL OR PinExpiresAt > now())` in three places: `CountPinnedAsync`, `GetPinnedAsync`, and the `ProjectMessage` `IsPinned` expression. **No background job** sweeps or nulls out expired rows.

Why no sweeper: a sweeper is a second write path that must be coordinated, may race with concurrent pin/unpin writes, complicates local development, and adds operational failure modes. The query-time filter achieves identical observable behaviour — an expired pin is invisible to clients — with zero extra infrastructure. The row stays in the DB with `PinnedAt` intact, so a future "pin history" feature can read it.

#### `PinExpiresAt = NULL` — legacy rows never expire

Rows pinned before this migration have `PinExpiresAt = NULL`. The filter treats `NULL` as **never-expiring** (the `IS NULL` branch of the OR). Interpreting `NULL` as "immediately expired" would be a destructive semantic change dressed up as an additive migration — any pre-migration pin that the conversation's participants still want stays visible. They can unpin it manually.

#### Re-pin updates duration only — no cap consumption, no system message

If the target message is already actively pinned (`PinnedAt IS NOT NULL` and not expired), `PinAsync` updates `PinExpiresAt` in place and returns early. It does **not** decrement and re-increment the active count (so it never trips the cap) and does **not** emit a system message (there is nothing to announce — the pin itself is unchanged from the participants' perspective).

#### Replace-oldest is a single atomic `SaveChangesAsync`

When the cap is full and `ReplaceOldest = true`, all four mutations are staged and flushed together:

1. Unpin oldest → `PinnedAt = null`, `PinnedByUserId = null`, `PinExpiresAt = null`
2. Pin the new message
3. Insert a `SystemEventType.MessageUnpinned` system row
4. Insert a `SystemEventType.MessagePinned` system row

EF Core wraps a `SaveChanges` call in one DB transaction, so a partial failure cannot leave the conversation with a phantom unpin or a phantom pin. Two `MessagePinChanged` realtime events and two `MessageReceived` (for the system rows) are dispatched after the commit.

#### System messages — empty body, client renders the text

Pin and unpin each produce a `MessageType.System = 4` row. Key design choices:

**`Body` is always `""`** — the display string ("Ubaid pinned a message", "You pinned a message") is composed by the Flutter client from `SenderId + SystemEventType + SystemTargetMessageId`. Storing a rendered English string on the server would break two things:

- **Viewer-relative phrasing.** "You pinned" vs "Ubaid pinned" depends on *who is reading*, not who wrote the row. The server has no reader context at write time.
- **Localization.** The backend has no locale; the client does. Moving the string to the client means it renders correctly in every language without any server change.

**`SenderId` = the actor** (the user who pinned/unpinned), not a sentinel "system" id. The client needs a real user id to resolve a display name and branch on "You" vs "someone else".

**`SystemTargetMessageId`** points to the affected message so the client can render a body snippet or a deep-link to it.

**Five operations refused on system rows** — reply, forward, edit, pin, react all return `400`. System rows are conversation history, not addressable content. Delete-for-me is allowed (private, no realtime event). Delete-for-everyone is `403` — a system row is not the actor's own content.

**Excluded from `UnreadCount`** and from `LastMessagePreview` — the conversation list preview falls back to the last non-system message, so a pin/unpin event never leaves the preview blank or shows a confusing empty string.

**Excluded from rule-(c) allowance** — `CountMessagesBySenderAsync` filters `Type != System`. Pinning in a pending conversation does not consume the initiator's single-message allowance.

**Updates `LastMessageAt`** — a pin/unpin is a real conversation event; the thread should surface to the top of both participants' lists.

### 6c. The edit and delete-for-everyone windows are server-enforced, and why

- **Edit window:** `ChatService.EditWindow = 15 minutes` (WhatsApp's limit). Past it, editing an own message is a `403`.
- **Delete-for-everyone window:** `ChatService.DeleteForEveryoneWindow = 48 hours` (WhatsApp's approximate limit). Past it, delete-for-everyone is a `403`; delete-for-me remains available (it has no window).

Both are `DateTime.UtcNow - message.CreatedAt` checks **in `ChatService`**, not in the client. A client-enforced window is not a rule — it's a suggestion a modified app, a replayed request, or a skewed device clock trivially bypasses. The constant lives server-side next to the code that enforces it so the two can never drift.

**Query-shape note (no N+1 for the enriched page):** `replyTo` is resolved by a correlated subquery *inside* the single message-page `SELECT` (same technique as the conversation list's other-participant join), with the quoted-body snippet truncated **in SQL** (`substring(…, 1, 80)`). `reactions` are **not** joined into that `SELECT` (a per-row collection would Cartesian-explode the page) — they are one aggregate `GROUP BY (MessageId, Emoji)` keyed by the page's ids and attached in memory. The page therefore costs a constant **two** queries regardless of page size. See `MessageQueryShapeTests` (a `ToQueryString()` guard) and `ConversationRepository.AttachReactionsAsync`.

**Revisit trigger:** Attachments/voice/images ship (the `MessageType` enum already reserves them) — reactions/reply/pin/forward all already carry `Type`, so those actions extend to non-text messages without schema change; only the body-snippet/preview rendering needs a per-type branch.

---

## 7. Media messages (M-M4): image/video, one-request upload, reuse of the single write path

**Decision:** Images and videos are real message types (`MessageType.Image = 1`, `MessageType.Video = 5`), sent through **one** multipart endpoint (`POST /api/conversations/{id}/messages/media`) that uploads to Cloudinary **and** creates the message in the same request. Eight nullable `Media*` columns were added to `Message` in one additive migration (`AddMediaMessages`). Load-bearing sub-decisions:

### 7a. `Video = 5`, not 4 — 4 is `System`

`System = 4` was assigned in M1.2. Reusing 4 for `Video` would silently re-type every existing pin/unpin row. `Video` therefore takes the next free value, **5**. `Image = 1` was already reserved in M1.

### 7b. One request (upload-then-create together), not a separate upload endpoint

A separate "upload first, send later" endpoint orphans a Cloudinary file whenever a user picks an image and then backs out — the same lesson the deferred profile-photo flow already learned ("commit on submit"). A single request means **a file exists only if a message exists**.

### 7c. Media flows through `SendCoreAsync` — it cannot skip rule (c)

Media send reuses the exact text write path (`SendCoreAsync`), so it inherits the participant gate, the declined check, the pending 1-message rule (c), persist-then-notify, and the request-received push. To keep "no orphan on a rejected send", the Cloudinary upload is **deferred**: `SendMediaMessageAsync` passes a `mediaFactory` that `SendCoreAsync` invokes **only after** those gates pass. An unauthorized send therefore never uploads. A **forward** passes a factory that returns the *source* message's media, so a forwarded media message **reuses the same `MediaUrl` + `MediaPublicId`** — a reference, not a re-upload.

### 7d. Validate before upload; duration is the one check that can't be

Type, size, and **magic bytes** are validated locally before any Cloudinary call — the declared MIME is verified against the file's leading signature (a renamed `.jpg` can't pass). Limits (10 MB image / 50 MB video / 120 s) live as named constants in `ChatService` beside `EditWindow`/`PinWindow*`. **Duration is the exception:** with no ffmpeg (explicitly out of scope), duration is only known from Cloudinary's upload result. So an over-length video is rejected **after** upload, and the just-uploaded (still unreferenced) asset is deleted — no orphan, no over-length video stored. This is the only case where a rejected file reaches Cloudinary.

### 7e. Thumbnails are Cloudinary URL transformations — no server-side processing

No ffmpeg, no generated files. The client shows a small thumbnail in the bubble and the full asset only when opened:
- **Image thumbnail:** `c_fill,w_400,q_auto` injected after `/image/upload/`.
- **Video poster:** `so_0,w_400,c_fill` injected after `/video/upload/`, extension swapped to `.jpg`.

### 7f. Preview label is localised on the client via `lastMessageType`

An uncaptioned photo has an empty `Body`, so the conversation-list preview would be blank. Rather than store `"📷 Photo"` server-side (untranslatable — Skillora targets every country, the same mistake M1.2 avoided for system messages), `ConversationSummaryDto` gains `lastMessageType` (resolved by one more correlated subquery in the **same** list statement — no extra round-trip) and the client renders its own localised "Photo"/"Video".

### 7g. A tombstone blanks the media URLs, exactly like the body

Delete-for-everyone blanks `MediaUrl`/`MediaThumbnailUrl` **in SQL** in the message projection (`CASE WHEN "DeletedAt" IS NULL THEN "MediaUrl"`), same as `Body`. A Cloudinary URL is publicly reachable, so a deleted photo whose URL still leaked would be a real privacy failure. `MediaPublicId` is **never** projected — it is a server-only deletion handle.

### 7h. Assets are never deleted in this slice — reference counting is required first

Because a forward shares `MediaPublicId`, deleting the asset on one copy's delete-for-everyone would break the others. No asset deletion ships here; orphan cleanup needs reference counting on `MediaPublicId`. Tracked in `docs/TODO.md` with the storage-cost trigger.

### 7i. Uploads pass through the API — acceptable now, with a known revisit

The upload streams **through the API**, tying up a request thread for the duration of a (up to 50 MB) video — consistent with the existing KYC and profile-photo paths, and acceptable at this scale. **Revisit trigger:** sustained upload volume, or larger size limits. **Migration path:** signed **direct-to-Cloudinary** uploads — the client uploads straight to Cloudinary and the API only issues an upload signature, then creates the message from the returned public id. `IMediaStorageService` is the seam that changes; the message write path is unaffected.

**Query-shape note:** the media columns are additional **scalar** columns in the single message-page `SELECT` (with the tombstone-blank `CASE` for the two URLs); `lastMessageType` is one more correlated subquery in the single list `SELECT`. Neither adds a statement — `GetMessagesAsync` stays **two** statements (page projection + reactions aggregate). Guarded by `MessageQueryShapeTests`.

**Out of scope (unchanged):** file message type, client-side crop/markup, signed direct uploads, asset deletion / reference counting.

## 8. Voice notes (M-M6): audio reuses the media path; the waveform is computed by the client

**Decision:** A voice note is `MessageType.Voice` (the value reserved since M1). It reuses the **entire** M-M4 media path — the same `POST .../messages/media` endpoint, the same `SendCoreAsync` write path, the same deferred-upload/rule-(c) discipline, the same validate-before-upload and delete-on-over-duration behaviour. Audio is not a parallel upload path; it is one more `MediaKind`. Only **one** new column was added (`MediaWaveform`, one additive migration `AddVoiceWaveform`). Load-bearing sub-decisions:

### 8a. The waveform is computed by the CLIENT, not the server

A voice bubble draws a waveform rather than a blank bar, so it needs amplitude data. Extracting it server-side means **decoding the audio — ffmpeg** — which was ruled out in M-M4 for exactly the reason it is ruled out here: no server-side media processing. But the mobile recorder **already exposes amplitude while recording**, so the client has the data for free and simply sends it. The server only **validates and stores** it: comma-separated integers, each `0–100`, **at most 64 samples** (enough resolution for a bubble a few cm wide, and it bounds the `varchar(512)` column so a client can't push thousands of points). A malformed value is a **400** — the shape is validated in `ChatService` beside the file checks, so the whole media write path is validated in one place. `null` is valid (the client falls back to a flat bar). This mirrors 7f (`lastMessageType`): the server stores structured data, the client renders the human-facing form.

### 8b. Audio has no distinct Cloudinary resource type — it is stored as "video"

Cloudinary has no `audio` resource type; audio lives under **`resource_type=video`**. `UploadAudioAsync` therefore uses `VideoUploadParams` (which sets that), and `DeleteAsync` maps `MediaKind.Audio → ResourceType.Video` so an over-length voice note's just-uploaded asset is deleted correctly. The app still models `Audio` as its own `MediaKind` so a `Voice` message is never confused with a `Video`. No thumbnail and no width/height are stored for voice (`MediaThumbnailUrl`/`MediaWidth`/`MediaHeight` stay `null`); duration follows the 7d rule — known only after upload, so an over-300 s note is rejected post-upload and its asset deleted.

### 8c. m4a and mp4 share the `ftyp` signature — the declared MIME decides the kind, not the bytes

An `.m4a` (audio) and an `.mp4` (video) both begin with the `ftyp` box at offset 4, so their magic-byte checks look alike. The **kind is decided by the declared MIME** (checked against `AllowedAudioTypes` vs `AllowedVideoTypes`), and the signature only **confirms the container is plausible** — it is never used to infer audio-vs-video. So a video declared `video/mp4` goes to the video path and an m4a declared `audio/mp4` to the audio path; neither can be misrouted by the shared signature. A cross-type payload whose container differs (e.g. an OGG declared `video/mp4`, or an mp4 declared `audio/ogg`) is still caught, because its signature won't match the declared type's branch.

### 8d. The waveform is a tombstone-blanked column, like the URLs

Delete-for-everyone blanks `MediaWaveform` in the same in-SQL `CASE` treatment as `MediaUrl`/`MediaThumbnailUrl` — a waveform left on a deleted voice note is a small leak, but it is still a leak. It is its **own** `CASE ... ELSE NULL END` output column, so `GetMessagesAsync` stays **two** statements (verified by a `ToQueryString()` dump: three separate media `CASE` columns, one page `SELECT`, plus the reactions aggregate). Edit is refused for `Voice` (the M-M4 media edit-guard now covers `Image`/`Video`/`Voice`); a forward reuses the same `MediaUrl` + `MediaPublicId` **and** `MediaWaveform`, no re-upload; `lastMessageType` returns `Voice` and the client renders its own localised label; a reply to a voice note carries `replyTo.type = Voice` with an empty snippet (no caption), same client-localised rule as media previews and system messages.

**Out of scope (M-M6):** transcription, playback-speed metadata, and file/document sharing (a later slice). *(Voice "played" receipts shipped in M-M7 — see §9.)*

---

## 9. Voice "played" receipts (M-M7): a dedicated `MessagePlay` table, not derived from `LastReadAt`

**Decision:** Whether a voice note has been played is tracked by its own per-user join table, `MessagePlay { MessageId, UserId, PlayedAt }` (composite PK, one additive migration `AddMessagePlays`), **not** derived from the conversation read watermark. A `POST /api/conversations/{id}/messages/{messageId}/played` endpoint inserts one row; `MessageDto` gains two caller-relative booleans — `playedByMe` (the caller played it) and `playedByOther` (the other participant did).

**Why `LastReadAt` is not a valid proxy (§4 read-vs-played distinction):** the `LastReadAt` watermark records that the **conversation was read up to a timestamp** — a viewport/scroll fact. It says nothing about whether a *specific* voice note was ever played. Someone can open a chat, read the text, and never tap play; deriving "played" from the read watermark would show a **false played receipt**. For a voice note that receipt is a claim the other person actually *listened* — a stronger signal than "seen", and one users take seriously — so it needs its own record. This is the same reasoning as §4 (a watermark can't express per-item state) applied one level finer: read is per-conversation, played is per-(message, user).

**Load-bearing sub-decisions:**

- **Composite PK ⇒ idempotency for free.** One row per (message, user), so marking a note played twice is a natural no-op (the row already exists) rather than a guarded upsert. `ChatService.MarkPlayedAsync` checks `HasMessagePlayAsync` first: if a row exists it returns immediately and **fires no event** — a repeat call from the client must not push a duplicate `MessagePlayed`. The event is dispatched only on the branch where a new row was actually inserted. Mirrors `MessageDeletion`'s config exactly (FK→Message Cascade, FK→User Restrict, `IX_MessagePlays_MessageId`).

- **Endpoint rules.** Participant only (else 403); unknown message 404; non-`Voice` type 400 (marking a text message played is meaningless — reject surfaces a client bug); the **sender** marking their own note 400 (a sender must not be able to manufacture their own played receipt); a tombstoned message 400; idempotent second call is a no-op.

- **Two flags without a third statement.** `playedByMe` / `playedByOther` are two correlated `EXISTS` subqueries **inside** the existing message-page `SELECT` — the same technique as `isPinned` and the delete-for-me exclusion. `playedByMe` seeks the composite PK; `playedByOther` seeks `IX_MessagePlays_MessageId` then filters `UserId <> caller`. They are **not** attached as a separate aggregate (that would be a third statement) and **not** projected as a `MessagePlay` collection (that would Cartesian-explode the page). `GetMessagesAsync` therefore stays **two** statements (page projection + reactions aggregate), verified by a `ToQueryString()` guard in `MessageQueryShapeTests` (asserts `MessagePlays` appears only via `EXISTS`, never a JOIN, and no window function). Both flags are blanked for a tombstone (`DeletedAt IS NULL AND EXISTS(...)`), consistent with `Body`, the media URLs, and `MediaWaveform`.

- **Realtime fires to the sender only.** `MessagePlayed { conversationId, messageId }` is a new `IChatNotifier` method (Application never references SignalR), sent to the **sender** — they are the one whose bubble's mic badge changes; the player already knows they pressed play. Persist-first, then notify; a notifier failure logs a warning and does not fail the request (a client refetch recovers the flag).

**Out of scope (M-M7):** played receipts for images/video (only voice), a "played at" timestamp in any UI, the `ReadReceiptsEnabled` privacy toggle (deferred in `docs/TODO.md`, now covering read **and** played symmetrically), and any Flutter change.

**Revisit trigger:** played receipts are wanted for other media types, or a "played at" time is surfaced in the UI — both are additive (the row already stores `PlayedAt`; the type gate widens).

---

## 10. Documents (M-M8): the reserved `File = 2`, an allowlist, and honest validation limits

**Decision:** Document sharing (PDF, Office, text/csv) reuses the **entire** M-M4 media path — the same `POST .../messages/media` endpoint (with an added `fileName` field), the same `SendCoreAsync` write path, the same deferred-upload/rule-(c) discipline, the same media rate-limit policy (S1's 20/hour per user). A document is `MessageType.File` — the value **reserved since M1** — and one more `MediaKind` (`Document → Cloudinary resource_type=raw`). One additive column was added (`MediaFileName`, migration `AddMessageFileName`). Load-bearing sub-decisions:

### 10a. An allowlist, never a blocklist; `.zip` is deliberately excluded

Nine extensions are allowed: `.pdf .docx .xlsx .pptx .doc .xls .ppt .txt .csv`, each pinned to the ONE declared MIME consistent with it. Anything not listed is rejected. A blocklist of "dangerous" extensions is **not** the primary control: a blocklist is the set of things we happened to think of, and the attacker's job is to find one we didn't — an allowlist inverts that burden. `.zip` is excluded on purpose: a zip is a container that can hold anything, so allowing it makes the whole allowlist meaningless — constraining the contents would mean unzipping, which we refuse (that is exactly how zip bombs work). Recorded here so nobody re-adds it thinking it an oversight.

### 10b. Three validation layers, none sufficient alone — and the magic-byte family limit

Extension (Layer 1) and declared MIME (Layer 2) are both client-supplied and forgeable; the MIME must be consistent with the extension (a `.pdf` declared `text/plain` is rejected regardless of its bytes). Layer 3 is magic bytes, and it is implemented **honestly**: `.docx/.xlsx/.pptx` are all zip archives (`PK\x03\x04`, plus the empty `PK\x05\x06` and spanned `PK\x07\x08` variants, accepted as zip-family), so the signature can confirm "this is the zip family" but **never** "this is specifically a Word document". `.doc/.xls/.ppt` are all OLE2 compound files (`D0 CF 11 E0 A1 B1 1A E1`) and likewise indistinguishable from one another. So the rule is **family-level agreement**: the signature must place the file in the family the extension implies. We deliberately do **not** unzip to inspect `[Content_Types].xml` — decompressing attacker-supplied archives is the zip-bomb attack, and the extra precision isn't worth exposing a decompressor to hostile input. `%PDF-` (`25 50 44 46 2D`) is the one signature that proves a specific type.

### 10c. txt/csv have no signature — a bounded heuristic, and its weakness

Plain text has nothing to match, so `.txt/.csv` use a bounded **heuristic, not a guarantee**: read at most the first **8 KB** (never the whole file), reject a null byte (the clearest binary marker), reject if >30 % of bytes are non-printable control characters, and reject anything that does not decode as UTF-8 (ASCII is a subset). A crafted file **can** pass this — it is acceptable only because a `.txt/.csv` is never executed, only stored and served. This is stated in a code comment on `IsPlausibleText` as well.

### 10d. Type detection is a filter, not a proof — the real defences are downstream

A file is a byte sequence; its "type" is a convention, not a property of the bytes, and a polyglot can be a valid PDF *and* a valid archive at once. Detection is therefore a filter, never a proof. The real defences are downstream: **the server never executes or parses the file** — it stores and serves bytes; documents are stored as **Cloudinary `raw`**, so no image/document transformation pipeline ever touches attacker-supplied bytes; and the client must never auto-open a download with elevated trust — it hands off to the OS, which applies its own sandboxing.

### 10e. Validation is entirely local — a document never reaches Cloudinary and is then deleted

Every document check (extension, MIME, size, magic bytes, text heuristic) is local, so a rejected document never reaches Cloudinary — unlike video/voice duration, which is only knowable *after* upload (7d), a document has no post-upload check, so there is **no upload-then-delete** path for documents. The deferred-upload factory still runs the participant/declined/rule-(c) gates before the upload, so an unauthorized send never uploads either.

### 10f. Size limit 25 MB

A named constant beside the image (10 MB), video (50 MB) and audio (10 MB) limits. Uploads pass **through** the API (§7i), so each upload holds a request thread for its duration — a larger cap multiplies that across concurrent users. On a mobile link 25 MB is already a slow upload; a higher cap makes failure likelier, not the feature more capable. It also bounds abuse alongside the per-user media rate limit. The **declared content length** is checked *before* the file is read, so a 500 MB upload is rejected early rather than buffered first (buffering it to discover it is too large is itself the attack).

### 10g. The filename is untrusted input — sanitised, with the validated extension forced

Documents need their original name (`contract_final_v3.pdf` *is* the content to the user), stored in the new `MediaFileName` (max 255). It is sanitised before storage: strip every path component (so `../../etc/passwd.pdf` becomes `passwd.pdf`); strip null bytes and control characters; strip bidirectional-override / directional-format characters (U+202A–202E, U+2066–2069, U+200E/200F) — a genuine spoof, since an RTL override makes `report<U+202E>fdp.exe` render to the eye as `reportexe.pdf`; Skillora has real RTL users, so we **strip the control characters while preserving legitimate Arabic/Urdu letters**, not reject non-Latin names. Truncate to 255 preserving the extension; if empty after sanitising, fall back to a generated stem. The stored extension is **always** the validated type, never whatever the user typed.

### 10h. Cloudinary `raw` mapping — and delete parity

`Document → RawUploadParams` (`resource_type=raw`) on upload; `DeleteAsync` maps `MediaKind.Document → ResourceType.Raw` so a delete passes the **same** resource type the asset was uploaded under (Cloudinary silently no-ops a delete on a resource-type mismatch, leaving an orphan with no error). This is the same map extended, not a parallel one (M6 added `Audio → Video`). No thumbnail, dimensions, duration or waveform are stored for a document (`MediaThumbnailUrl`/`MediaWidth`/`MediaHeight`/`MediaDurationMs`/`MediaWaveform` stay `null`) — Cloudinary *can* render a PDF's first page, but only by uploading it as an `image` resource, which would put attacker-supplied files through the image pipeline; not worth it, so the client renders an icon from the extension.

### 10i. Interaction with existing features

A tombstone blanks both `MediaUrl` **and** `MediaFileName` in the projection (its own in-SQL `CASE` column, like the URLs/waveform) — a filename (`salary_negotiation_final.pdf`) leaks meaning even when the file is gone; `replyTo.fileName` carries the quoted document's name (one more scalar on the existing replyTo LEFT JOIN — no extra statement; `GetMessagesAsync` stays **two** statements, verified by the `ToQueryString()` dump); a forward reuses the same `MediaUrl`/`MediaPublicId`/`MediaFileName`, no re-upload; edit is refused for `File` (the media edit-guard now covers `Image/Video/Voice/File`); a caption is allowed (held in `Body`, empty valid); played receipts remain voice-only (a document is rejected there); `lastMessageType` returns `File` and the client renders its own localised label (no server-side "Document" string).

**Out of scope (M-M8):** zip/archive support (10a); virus scanning; signed/expiring download URLs; document previews or in-app rendering; any Flutter change. Virus scanning and signed delivery are tracked in `docs/TODO.md`, each with its trigger.

**Revisit trigger:** signed/expiring download URLs before any public launch (a Cloudinary `raw` URL is publicly reachable by anyone holding the link — far more sensitive for a contract than a chat photo); virus scanning before documents are exchanged with parties outside a user's connections.

---

## Notes

- **Backplane and read-model are the two most likely first revisits** — the backplane the moment a second instance is deployed, the read-model if per-message receipts are demanded by group chat.
- Deferred messaging features and their triggers are tracked in `docs/TODO.md`.
