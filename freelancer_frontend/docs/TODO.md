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
## F-M7 — Reaction picker: search box

The full emoji picker (curated grid, Option B) has NO search box this slice. With
~130 emoji across six categories a search field is a reasonable follow-up. Add a
TextField above the grid that filters the flattened emoji list; keep it under the
navy/gold theme and route any label through messaging_strings.dart.

## F-M7 — Reaction skin-tone selector

No skin-tone selector this slice. The backend column is varchar(16) and already
accepts multi-codepoint sequences (skin-tone modifiers, ZWJ), so this is purely a
UI gap: a long-press on a gesture/person emoji could open a Fitzpatrick modifier
row and send the composed sequence. No backend change is needed.

## F-M7 — "Who reacted" list

The reaction DTO is aggregate-only (emoji + count + reactedByMe); there is no
per-user breakdown. Showing a "who reacted" sheet needs a new backend endpoint,
so it is out of scope here.

## F-M5 — Multi-select from the gallery

`_pickFromGallery` uses `ImagePicker().pickMedia()` — a SINGLE image or video per
pick. Sending several at once (WhatsApp-style multi-select with a shared caption)
is a follow-up: switch to `pickMultipleMedia()`, show a horizontal strip of
thumbnails on the preview screen, and fire `sendMedia` once per file (or a batched
endpoint if the backend adds one). Keep the per-file client-side validation.

## F-M5 — Camera video capture

The Camera attachment option captures a PHOTO (`pickImage(source: camera)`). The
full WhatsApp-style camera — hold-to-record video, tap for photo, flip camera — is
F-M11 and will replace this entry point. Until then, a recorded video can still be
sent by picking it from the gallery.

## F-M5 — Crop & markup before sending

The preview screen sends the picked image/video as-is. Cropping, rotating, and
drawing/markup (arrows, text, blur) before sending are a later slice. They would
slot into MediaPreviewScreen between the preview and the caption bar, editing a
working copy of the file so the original is never mutated.

## F-M5 — Swiping between media in the viewer

MediaViewerScreen shows ONE asset. Swiping left/right through all the media in a
conversation (a media gallery) is out of scope. It needs the viewer to take the
ordered list of media messages + a starting index and drive a PageView, plus a
per-page video-controller lifecycle so only the visible video holds a controller.

## F-M11 — Voice note follow-ups

Out of scope for this slice (deliberately):
- Playback speed (1x/1.5x/2x) — just_audio supports setSpeed; add a small speed
  toggle in the bubble that persists per-conversation.
- "Played" receipts — the mic badge in VoiceBubble is wired for a future colour swap
  (muted → gold) but the backend has no played flag yet. Needs a MessagePlay table on
  the server with the same shape as MessageDeletion and MessageReaction (messageId,
  userId, playedAt). Client reads it via the existing realtime/REST layer. Do NOT use
  LastReadAt as a proxy — LastReadAt tracks when a conversation was opened, not whether
  a specific audio file was played; they diverge whenever a message is read on another
  device or via a notification preview.
- Waveform scrubbing (drag the playhead dot) — out of scope. Implement via
  GestureDetector.onHorizontalDragUpdate reusing the _onWaveformTap fraction mapping.
  No CustomPainter change needed; the dot position already follows `progress`.
- Transcription — a server/ML feature, no client hook exists.
- Camera video capture / documents remain in their own slices (F-M12, later).

## F-M8 — Signed / expiring media URLs (security)

Cloudinary **raw** delivery URLs (documents) are publicly reachable by anyone holding
the link — there is no auth on the asset itself; the URL *is* the capability. The
backend recorded this trade-off. The migration path is signed or time-expiring URLs
(Cloudinary signed URLs, or serving through an authenticated backend redirect).

This matters more for a **contract/NDA shared in a hiring thread** than for a chat
photo, so documents raise the priority. Scope when addressed:
- Backend issues signed/expiring URLs (or a short-lived redirect endpoint) for
  `mediaUrl` on File/media messages.
- The client already downloads via a plain Dio in `DocumentDownloader` (no app token
  sent to Cloudinary); it would simply consume whatever URL the server returns, so no
  client change is expected beyond honouring an expiry (re-fetch the message/URL if a
  download 403s on an expired link).

## F-M8 — Document sharing follow-ups (out of scope this slice)

- Multi-file selection — `FilePicker.pickFile` picks one; `pickFiles` (plural) plus a
  per-file optimistic bubble would add multi-attach.
- In-app document viewing / previews — deliberately NOT done. Untrusted files are
  handed to the OS (open_filex) so its sandboxing applies (backend ADR). Do not add an
  in-app renderer.
- Zip / archive support — the server rejects `.zip` and executables by design.
- A "downloaded / open" persistent indicator across app restarts — the cache is keyed
  by message id in the temp dir, which the OS may clear; a persistent "downloaded"
  badge would need its own bookkeeping.
