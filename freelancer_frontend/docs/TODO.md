# Follow-up items (out of scope for current slice)

## F-M6 — Multi-target forwarding

Currently ForwardPickerScreen forwards to exactly one conversation per gesture
(single-target). The spec notes multi-target forwarding as a follow-up.

What is needed:
- Replace the single-tap _forward(target) call with a multi-select mode (checkboxes).
- The send button fires forwardMessages once per selected target (or a batched
  endpoint if the backend adds one).
- The count indicator in the app bar should update to show N targets selected.
- Pagination: getConversations(pageSize: 50) is a reasonable initial load but a
  large contact list warrants a load-more footer or an infinite-scroll list.

## F-M6 — Forwarded-message label in the target conversation

When the recipient opens the target conversation they see the message with an
isForwarded == true flag. The "Forwarded" label rendering (already implemented in
_MessageBubble) handles this transparently. The label renders in both bubble styles.

## M3 — Jump-to-target from a system message

A System message (pin/unpin notice) carries `systemTargetMessageId`, which points
at the pinned/unpinned message. Making the centred notice tappable to jump to that
message (reusing `_jumpToQuoted`, including its not-loaded SnackBar) would be a nice
touch, but it is deliberately out of scope for this slice. The id is parsed and
carried on `Message`/`ChatMessage` so the wiring is a small follow-up: give
`_SystemNotice` an `onTap` and pass `_jumpToQuoted(systemTargetMessageId)`.

## M3 — Pin remaining-time in the UI

Pins now expire. `Message.pinExpiresAt` (nullable UTC; null = never, legacy rows)
is parsed and carried through `ChatMessage` and the `MessagePinChanged` event, but
nothing renders it yet. A future slice could show a subtle "expires in …" hint in
the pin banner or the bubble's pin indicator. Remember `.toLocal()` on render and
that null must read as "no expiry", not "expired".