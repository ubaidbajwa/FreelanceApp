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

## Notes

- **Backplane and read-model are the two most likely first revisits** — the backplane the moment a second instance is deployed, the read-model if per-message receipts are demanded by group chat.
- Deferred messaging features and their triggers are tracked in `docs/TODO.md`.
