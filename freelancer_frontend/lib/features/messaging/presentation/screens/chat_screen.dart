// Real chat screen (F-M2) — REST-only, no real-time (F-M3 add karega). Naye
// messages sirf open/refresh pe aate hain. chat_screen_placeholder.dart ki jagah.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:app_settings/app_settings.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../../../core/utils/number_format.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/active_conversation_provider.dart';
import 'forward_picker_screen.dart';
import 'media_preview_screen.dart';
import 'media_viewer_screen.dart';
import '../widgets/media_bubble_content.dart';
import '../widgets/document_bubble_content.dart';
import '../widgets/document_caption_sheet.dart';
import '../widgets/voice_bubble.dart';
import '../../application/chat_notifier.dart';
import '../../application/voice_recording_notifier.dart';
import '../../application/voice_playback_notifier.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, this.summary});

  final String conversationId;
  // F-M1 nav contract se aati hai (status/isRequest/otherUser). Cold deep-link /
  // future push isay null bhej sakta hai — us par depend nahi karte.
  final ConversationSummary? summary;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _scrollThreshold = 300.0;
  // Autoscroll on fan-out: only if user is within this many pixels of the bottom.
  static const _autoscrollThreshold = 150.0;

  // F-M11: live drag offset of the mic press-and-hold (from origin), plus whether
  // this gesture has already locked. Drives the slide-to-cancel hint + lock fill.
  Offset _holdOffset = Offset.zero;
  bool _holdLocked = false;
  RecordDragOutcome _holdOutcome = RecordDragOutcome.none;

  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();

  // F-M5: tap-to-jump highlight (briefly tints the target bubble gold).
  String? _highlightedMessageId;
  // F-M7: floating reaction bar overlay, anchored above the long-pressed bubble.
  OverlayEntry? _reactionBar;
  String?
  _reactionBarMessageId; // which message the bar is currently anchored to
  // F-M6: composer content saved when entering edit mode, restored on cancel.
  String? _preEditInput;
  // GlobalKey per message so Scrollable.ensureVisible can locate any loaded bubble.
  final Map<String, GlobalKey> _bubbleKeys = {};

  // Captured in initState for use in dispose — ref is unusable there (the
  // widget is already deactivated; Riverpod throws if read in dispose).
  late final ActiveConversationNotifier _activeConv;

  @override
  void initState() {
    super.initState();
    _activeConv = ref.read(activeConversationProvider.notifier);
    WidgetsBinding.instance.addObserver(
      this,
    ); // F-M11: background → stop record/play
    _scroll.addListener(_onScroll);
    // DEFERRED past the first frame — open() synchronously mutates providers
    // (setActive on activeConversationProvider + seeding chatProvider state).
    // Provider mutation during the build phase throws "Tried to modify a
    // provider while the widget tree was building"; the unhandled async error
    // killed the load before its try/finally and left the spinner forever.
    // build() renders isLoading until open() runs one frame later.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(chatProvider.notifier)
          .open(conversationId: widget.conversationId, summary: widget.summary);
    });
  }

  // F-M11: leaving the foreground stops recording (never record in background) and
  // stops any playback. Both notifiers keep what was already captured.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      ref.read(voiceRecordingProvider.notifier).onAppBackgrounded();
      ref.read(voicePlaybackProvider.notifier).stopForBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeReactionBar(); // F-M7: never leak the overlay entry
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    // Clear the active-conversation slot so ConversationsNotifier resumes
    // incrementing unread counts. The mutation is DEFERRED for the same reason
    // as the open() in initState: dispose can run during a navigation
    // transition's build phase, and a synchronous setActive here throws the
    // same "modify while building" error. Uses _activeConv captured in
    // initState — ref itself is unusable in dispose (widget deactivated).
    // clearIfActive re-checks ownership at run time so a newer chat's id is
    // never cleared.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeConv.clearIfActive(widget.conversationId);
    });
    super.dispose();
  }

  // Reverse list: purane messages TOP pe = maxScrollExtent. Wahan pahunchne pe older load.
  void _onScroll() {
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(chatProvider.notifier).loadOlder();
    }
  }

  void _submit() {
    final text = _input.text;
    final editDraft = ref.read(chatProvider).draftEdit;
    if (editDraft != null) {
      _submitEdit(text);
      return;
    }
    if (text.trim().isEmpty) return;
    ref.read(chatProvider.notifier).send(text);
    _input.clear();
    _focus.requestFocus(); // keyboard retain
    // Newest bubble bottom pe (reverse list → offset 0).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  Future<void> _submitEdit(String text) async {
    final err = await ref.read(chatProvider.notifier).applyEdit(text);
    if (err != null) {
      // Error (including 403): keep typed text in _input; show error.
      _snack(err);
    } else {
      // Success or no-op: clear composer, restore pre-edit content (usually empty).
      _input.text = _preEditInput ?? '';
      _preEditInput = null;
      _focus.requestFocus();
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── F-M5: attachments ─────────────────────────────────────────────────────────

  // Composer attachment button → sheet with three options: Gallery, Camera and
  // Document. Document was deliberately absent until the backend accepted files (a
  // dead option is a false affordance) — it works now, so it goes in.
  void _openAttachmentSheet() {
    _focus.unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _navy),
              title: const Text(
                MessagingStrings.attachGallery,
                style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: _navy),
              title: const Text(
                MessagingStrings.attachCamera,
                style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: _navy),
              title: const Text(
                MessagingStrings.attachDocument,
                style: TextStyle(color: _navy, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickDocument();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Gallery: single image OR video (pickMedia). Multi-select noted in docs/TODO.md.
  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickMedia();
      await _onPicked(picked);
    } on PlatformException catch (e) {
      _onPickPermissionError(e, isCamera: false);
    }
  }

  // Camera: capture a photo with the built-in camera (image_picker). The full
  // WhatsApp-style camera — including video capture — is F-M11; this entry point
  // exists so the flow works end to end now (see docs/TODO.md).
  Future<void> _pickFromCamera() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      await _onPicked(picked);
    } on PlatformException catch (e) {
      _onPickPermissionError(e, isCamera: true);
    }
  }

  // Cancelled pick (user backed out) is normal — do nothing, no error state.
  // Otherwise validate size/type client-side BEFORE any upload, then push preview.
  Future<void> _onPicked(XFile? picked) async {
    if (picked == null || !mounted) return; // cancelled — not an error
    final kind = mediaKindForPath(picked.path);
    if (kind == null) {
      _snack(MessagingStrings.mediaUnsupportedType);
      return;
    }
    final length = await picked.length();
    final err = validateMediaFile(path: picked.path, lengthBytes: length);
    if (err != null) {
      _snack(err);
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MediaPreviewScreen(path: picked.path, kind: kind),
      ),
    );
  }

  // Document: pick a file restricted to the allowed extensions (the OS dialog filters
  // out most invalid choices — a convenience, NOT the control), then validate
  // extension + size client-side BEFORE any upload, and show the caption sheet. The
  // server allowlist + magic-byte check remain authoritative; a file can still be
  // 400'd there and that message is surfaced by the send path.
  Future<void> _pickDocument() async {
    PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: DocumentLimits.allowedExtensions.toList(),
      );
    } catch (_) {
      // Includes a denied storage permission on some Android levels.
      if (mounted) _snack(MessagingStrings.genericError);
      return;
    }
    if (picked == null || !mounted) return; // cancelled — not an error
    final path = picked.path;
    if (path == null) {
      _snack(MessagingStrings.genericError);
      return;
    }
    final sizeBytes = await picked.xFile.length();
    if (!mounted) return;
    // Validate the SAME way the server will (extension + size), naming the specific
    // limit — rejecting locally saves a slow upload that would only earn a 400.
    final err = validateDocumentFile(
      fileName: picked.name,
      lengthBytes: sizeBytes,
    );
    if (err != null) {
      _snack(err);
      return;
    }
    if (!mounted) return;
    await showDocumentCaptionSheet(
      context,
      path: path,
      fileName: picked.name,
      sizeBytes: sizeBytes,
    );
  }

  // Denied permission is not a silent dead button — explain what's needed and offer
  // a route to the system settings. image_picker throws with an access-denied code
  // when the user has denied camera/photo access.
  void _onPickPermissionError(PlatformException e, {required bool isCamera}) {
    final denied =
        e.code.contains('access') ||
        e.code.contains('denied') ||
        e.code == 'photo_access_denied' ||
        e.code == 'camera_access_denied';
    if (denied) {
      _showPermissionDialog(isCamera: isCamera);
    } else {
      _snack(MessagingStrings.genericError);
    }
  }

  Future<void> _showPermissionDialog({required bool isCamera}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          isCamera
              ? MessagingStrings.permissionCameraTitle
              : MessagingStrings.permissionPhotosTitle,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        content: Text(
          isCamera
              ? MessagingStrings.permissionCameraBody
              : MessagingStrings.permissionPhotosBody,
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: _navy.withValues(alpha: 0.55),
            ),
            child: const Text(MessagingStrings.permissionDismiss),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.openAppSettings();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            child: const Text(MessagingStrings.permissionOpenSettings),
          ),
        ],
      ),
    );
  }

  // Open the full-screen viewer for a confirmed media message.
  void _openViewer(ChatMessage m) {
    final url = m.mediaUrl;
    if (url == null || url.isEmpty) return;
    final senderName = m.isMine
        ? MessagingStrings.replyYou
        : (ref.read(chatProvider).otherUser?.fullName ??
              widget.summary?.otherUser.fullName ??
              '');
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MediaViewerScreen(
          mediaUrl: url,
          type: m.type,
          senderName: senderName,
          createdAt: m.createdAt,
          mediaDurationMs: m.mediaDurationMs,
        ),
      ),
    );
  }

  // F-M5: toolbar reply tap → draft set → selection cleared → composer focused.
  void _replyToSelected() {
    final notifier = ref.read(chatProvider.notifier);
    if (notifier.replySelected()) _focus.requestFocus();
  }

  // F-M6: toolbar "Edit" tap → enter edit mode; screen populates composer via listener.
  void _startEditSelected() {
    final notifier = ref.read(chatProvider.notifier);
    if (notifier.startEditSelected()) _focus.requestFocus();
  }

  // F-M6: cancel edit — restore pre-edit composer content.
  void _cancelEdit() {
    ref.read(chatProvider.notifier).cancelEdit();
    _input.text = _preEditInput ?? '';
    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
    _preEditInput = null;
  }

  // ── F-M7: reactions ─────────────────────────────────────────────────────────

  // Apply a reaction (optimistic in the notifier) and dismiss the bar. Clearing
  // the selection hides the bar via _syncReactionBar; the toggle then runs and
  // only surfaces a snackbar if the round trip fails (after rolling back).
  Future<void> _react(String messageId, String emoji) async {
    final notifier = ref.read(chatProvider.notifier);
    notifier.clearSelection();
    final err = await notifier.toggleReaction(messageId, emoji);
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  // The "+" on the bar → full curated picker in a bottom sheet. Selecting applies
  // and closes; there is no search box or skin-tone selector this slice (TODO.md).
  Future<void> _openReactionPicker(String messageId) async {
    ref.read(chatProvider.notifier).clearSelection(); // hide the bar first
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _EmojiPickerSheet(),
    );
    if (emoji == null || !mounted) return;
    final err = await ref
        .read(chatProvider.notifier)
        .toggleReaction(messageId, emoji);
    if (!mounted) return;
    if (err != null) _snack(err);
  }

  // Insert / move / remove the reaction bar to match the current selection. Shown
  // only for a single reactable selection (shouldShowReactionBar); a second
  // selection, clear, back, or an applied reaction all remove it.
  void _syncReactionBar() {
    if (!mounted) return;
    final state = ref.read(chatProvider);
    final selected = ref.read(chatProvider.notifier).selectedMessages;
    final show = state.reactionBarVisible && shouldShowReactionBar(selected);
    final id = show ? selected.first.id : null;
    if (id == null) {
      _removeReactionBar();
      return;
    }
    if (_reactionBarMessageId == id && _reactionBar != null) {
      if (mounted) _reactionBar!.markNeedsBuild();
      return;
    }
    _removeReactionBar();
    _reactionBarMessageId = id;
    // Capture the notifier + the caller's current emoji up front. The bar is only
    // open for a single, fixed selection and myReactionEmoji cannot change while it
    // shows (reacting clears the selection), so a snapshot is safe — and it keeps
    // live `ref`/state reads OUT of the OverlayEntry builder, which can outlive
    // this State.
    final notifier = ref.read(chatProvider.notifier);
    final myEmoji = _currentMyEmoji(id);
    final entry = OverlayEntry(
      builder: (_) => _reactionBarOverlay(id, myEmoji, notifier),
    );
    _reactionBar = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _removeReactionBar() {
    _reactionBar?.remove();
    _reactionBar = null;
    _reactionBarMessageId = null;
  }

  // Positions the bar ABOVE the anchored bubble, flipping BELOW when the bubble is
  // too near the top of the viewport, and clamping horizontally so a bar centred
  // over an edge-hugging bubble never runs off-screen.
  Widget _reactionBarOverlay(
    String messageId,
    String? myEmoji,
    ChatNotifier notifier,
  ) {
    // The entry can be rebuilt by the Overlay scheduler; if this State is gone,
    // touching its context/ref would throw — bail to an empty box instead.
    if (!mounted) return const SizedBox.shrink();
    final anchorCtx = _bubbleKeys[messageId]?.currentContext;
    final overlayBox =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    if (anchorCtx == null || overlayBox == null) return const SizedBox.shrink();
    final box = anchorCtx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const SizedBox.shrink();

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bubbleSize = box.size;
    final screen = overlayBox.size;

    const barHeight = 52.0;
    const barWidth = 300.0; // fixed → exact horizontal clamp
    const gap = 8.0;
    // Keep the bar (and the dismiss catcher) clear of the app bar so the selection
    // toolbar — delete / copy / forward / pin — stays tappable while the bar shows.
    final appBarBottom = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final safeTop = appBarBottom + 8.0;

    // Prefer above; flip below when there isn't room above.
    var top = topLeft.dy - barHeight - gap;
    if (top < safeTop) top = topLeft.dy + bubbleSize.height + gap;

    // Centre over the bubble, then clamp so [8, screenWidth-barWidth-8].
    final centreX = topLeft.dx + bubbleSize.width / 2;
    final upper = (screen.width - barWidth - 8.0);
    final left = (centreX - barWidth / 2).clamp(8.0, upper < 8.0 ? 8.0 : upper);

    return Stack(
      children: [
        // Tapping the message area (below the app bar) dismisses the bar. The app
        // bar itself is intentionally left uncovered so its selection toolbar keeps
        // working — covering it would eat the delete/copy taps.
        Positioned(
          top: appBarBottom,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: notifier.clearSelection,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: barWidth,
          child: _ReactionBar(
            myEmoji: myEmoji,
            onSelect: (emoji) => _react(messageId, emoji),
            onMore: () => _openReactionPicker(messageId),
          ),
        ),
      ],
    );
  }

  String? _currentMyEmoji(String messageId) {
    for (final m in ref.read(chatProvider).messages) {
      if (m.id == messageId) return m.myReactionEmoji;
    }
    return null;
  }

  // F-M6: forward — push the conversation picker; on return show snack if sent.
  // clearSelection() fires BEFORE navigation so the bar dismisses on ALL exit paths
  // (send, cancel, swipe-back). IDs are snapshotted first so the push still works.
  void _forwardSelected() async {
    final notifier = ref.read(chatProvider.notifier);
    final ids = notifier.forwardSelectedMessageIds();
    if (ids.isEmpty) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ForwardPickerScreen(
          sourceConversationId: widget.conversationId,
          messageIds: ids,
        ),
      ),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(MessagingStrings.forwardSuccess)),
      );
    }
  }

  // F-M5: tap on quoted block → scroll to original if loaded; snackbar if not.
  // Detection: search state.messages by id (O(n), list is typically ≤ 30 items visible).
  void _jumpToQuoted(String messageId) {
    final messages = ref.read(chatProvider).messages;
    final isLoaded = messages.any((m) => m.id == messageId);
    if (!isLoaded) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(MessagingStrings.replyOriginalNotLoaded),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final key = _bubbleKeys[messageId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    }
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _accept() async {
    final err = await ref.read(chatProvider.notifier).accept();
    if (err != null) _snack(err);
  }

  Future<void> _decline() async {
    final err = await ref.read(chatProvider.notifier).decline();
    if (!mounted) return;
    if (err != null) {
      _snack(err);
    } else {
      context.pop(); // decline success → leave screen
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);

    // textToRestore: 403 sendMessage ke baad refetch ne State A confirm kiya —
    // typed text wapas composer mein aata hai. Screen reads state, restores, clears.
    ref.listen<String?>(chatProvider.select((s) => s.textToRestore), (_, next) {
      if (next != null) {
        _input.text = next;
        _input.selection = TextSelection.fromPosition(
          TextPosition(offset: _input.text.length),
        );
        ref.read(chatProvider.notifier).clearTextRestore();
      }
    });

    // Fan-out autoscroll: scroll to newest only if user is already near the bottom.
    // Reverse list → offset 0 = newest (bottom of screen). If user scrolled up
    // (large offset), don't interrupt them.
    ref.listen<bool>(chatProvider.select((s) => s.scrollToLatest), (
      _,
      shouldScroll,
    ) {
      if (!shouldScroll) return;
      ref.read(chatProvider.notifier).clearScrollSignal();
      if (_scroll.hasClients && _scroll.offset < _autoscrollThreshold) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    // F-M6: entering edit mode — populate composer with the original body.
    ref.listen<EditDraft?>(chatProvider.select((s) => s.draftEdit), (
      prev,
      next,
    ) {
      if (next != null && prev == null) {
        _preEditInput = _input.text;
        _input.text = next.originalBody;
        _input.selection = TextSelection.fromPosition(
          TextPosition(offset: _input.text.length),
        );
        _focus.requestFocus();
      }
    });

    // F-M7: selection + explicit visibility drive the floating reaction bar. Pin
    // cap keeps selection for retry but flips visibility off; normal actions clear
    // selection and visibility together through ChatNotifier.
    ref.listen<(Set<String>, bool)>(
      chatProvider.select((s) => (s.selectedMessageIds, s.reactionBarVisible)),
      (_, next) {
        if (next.$1.isEmpty || !next.$2) {
          _removeReactionBar();
        } else {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _syncReactionBar(),
          );
        }
      },
    );

    // F-M5: a media send failed for a reason the user must see once (e.g. the
    // server's "video too long" 400). The failed bubble already offers retry; this
    // surfaces the specific message, then clears it so it fires only once.
    ref.listen<String?>(chatProvider.select((s) => s.sendError), (_, next) {
      if (next != null) {
        _snack(next);
        ref.read(chatProvider.notifier).clearSendError();
      }
    });

    // F-M11: a finished recording is ready → send it via the shared media path
    // (optimistic bubble, progress, retry-keeps-file). Auto-stop at 300 s lands here
    // too. Consume so it fires once.
    ref.listen<VoiceResult?>(
      voiceRecordingProvider.select((s) => s.completed),
      (_, result) {
        if (result == null) return;
        ref
            .read(chatProvider.notifier)
            .sendVoice(
              path: result.path,
              durationMs: result.durationMs,
              waveform: result.waveform,
            );
        ref.read(voiceRecordingProvider.notifier).consumeCompleted();
      },
    );
    // Mic taken by another app / call → explain, don't crash.
    ref.listen<String?>(voiceRecordingProvider.select((s) => s.error), (
      _,
      err,
    ) {
      if (err == null) return;
      _snack(err);
      ref.read(voiceRecordingProvider.notifier).consumeError();
    });
    // Released under 1 s → accidental-tap hint.
    ref.listen<bool>(voiceRecordingProvider.select((s) => s.tooShort), (
      _,
      tooShort,
    ) {
      if (!tooShort) return;
      _snack(MessagingStrings.voiceHoldHint);
      ref.read(voiceRecordingProvider.notifier).consumeTooShort();
    });

    // Cold open: state.otherUser refetch ke baad milta hai.
    // Hot open: state.otherUser bg-reconciliation ke baad update hota hai;
    // tab tak widget.summary se immediate render hota hai.
    final other = state.otherUser ?? widget.summary?.otherUser;
    final headline = other?.headline; // server-supplied nullable — no `!`

    final selecting = state.isSelecting;

    return PopScope(
      // System back GESTURE while selecting must CANCEL selection, not leave the
      // chat — otherwise a "cancel" gesture jarringly pops the whole route.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(chatProvider.notifier).clearSelection();
      },
      child: Scaffold(
        backgroundColor: _ivory,
        appBar: selecting
            ? _selectionAppBar(state)
            : _normalAppBar(other, headline),
        body: Column(
          children: [
            // F-M6: pin banner — only when pins exist and not in selection mode
            if (state.pinnedMessages.isNotEmpty && !state.isSelecting)
              _PinBanner(
                pinnedMessages: state.pinnedMessages,
                pinnedIndex: state.pinnedIndex,
                onTap: () {
                  // Jump to the currently shown pin, THEN advance the display to
                  // the next one (wrapping). Reuses _jumpToQuoted — including its
                  // not-loaded SnackBar — so there is one jump implementation.
                  final notifier = ref.read(chatProvider.notifier);
                  final st = ref.read(chatProvider);
                  final msgs = st.pinnedMessages;
                  if (msgs.isEmpty) return;
                  final idx = clampPinIndex(st.pinnedIndex, msgs.length);
                  _jumpToQuoted(msgs[idx].id);
                  notifier.cyclePin();
                },
                onUnpin: () async {
                  final err = await ref
                      .read(chatProvider.notifier)
                      .unpinFromBanner();
                  if (err != null) _snack(err);
                },
              ),
            Expanded(child: _messageList(state)),
            _footer(state),
          ],
        ),
      ),
    );
  }

  // Normal header — avatar + name (F-M2). Header tap → profile (abhi koi
  // profile-view route nahi; inert chhoda, dead button add nahi kiya).
  PreferredSizeWidget _normalAppBar(ConversationUser? other, String? headline) {
    return AppBar(
      backgroundColor: _ivory,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: _navy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      foregroundColor: _navy,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        color: _navy,
        onPressed: () => context.pop(),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          UserAvatar(
            fullName: other?.fullName ?? '',
            photoUrl: other?.photoUrl,
            radius: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  other?.fullName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                ),
                if (headline != null && headline.isNotEmpty)
                  Text(
                    headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    style: TextStyle(
                      fontSize: 12,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Selection header — back (cancel) · count · action icons. Which icons show is
  // decided by resolveToolbarActions (single explicit function, not inline ifs).
  PreferredSizeWidget _selectionAppBar(ChatState state) {
    final selected = ref.read(chatProvider.notifier).selectedMessages;
    final actions = resolveToolbarActions(selected);
    final count = state.selectedMessageIds.length;

    return AppBar(
      backgroundColor: _ivory,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: _navy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      foregroundColor: _navy,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        color: _navy,
        tooltip: MessagingStrings.selectionCancel,
        onPressed: () => ref.read(chatProvider.notifier).clearSelection(),
      ),
      titleSpacing: 0,
      title: Text(
        formatCount(count),
        textAlign: TextAlign.start,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _navy,
        ),
      ),
      // Order: reply · edit · copy · forward · delete · pin.
      actions: [
        if (actions.showReply)
          IconButton(
            icon: const Icon(Icons.reply_rounded),
            color: _navy,
            tooltip: MessagingStrings.actionReply,
            onPressed: _replyToSelected,
          ),
        if (actions.showEdit)
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            color: _navy,
            tooltip: MessagingStrings.actionEdit,
            onPressed: _startEditSelected,
          ),
        if (actions.showCopy)
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            color: _navy,
            tooltip: MessagingStrings.actionCopy,
            onPressed: _copySelected,
          ),
        if (actions.showForward)
          IconButton(
            icon: const Icon(Icons.forward_rounded),
            color: _navy,
            tooltip: MessagingStrings.actionForward,
            onPressed: _forwardSelected,
          ),
        if (actions.showDelete)
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: _navy,
            tooltip: MessagingStrings.actionDelete,
            onPressed: _confirmDelete,
          ),
        if (actions.showPin)
          IconButton(
            icon: Icon(
              actions.isUnpin ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            color: _navy,
            tooltip: actions.isUnpin
                ? MessagingStrings.actionUnpin
                : MessagingStrings.actionPin,
            onPressed: _pinSelected,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Selection action handlers ───────────────────────────────────────────────

  Future<void> _copySelected() async {
    final notifier = ref.read(chatProvider.notifier);
    final text = notifier.copySelectedText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(MessagingStrings.copied)));
  }

  // Sequence (spec Parts 2 & 3): unpin is immediate; pin opens the duration
  // dialog FIRST, then attempts. A 409 (cap) opens the replace dialog instead of
  // erroring; Continue retries with the SAME duration and replaceOldest:true.
  Future<void> _pinSelected() async {
    final notifier = ref.read(chatProvider.notifier);
    final selected = notifier.selectedMessages;
    if (selected.length != 1) return;

    // Already pinned → the toolbar button means "unpin"; no dialog.
    if (selected.first.isPinned) {
      final err = await notifier.unpinSelected();
      if (err != null) _snack(err);
      return;
    }

    // Pin: choose a duration before any request. Cancel (null) aborts silently.
    final duration = await _showPinDurationDialog();
    if (duration == null || !mounted) return;

    var outcome = await notifier.pinSelected(duration: duration);
    if (outcome.kind == PinOutcomeKind.capReached) {
      if (!mounted) return;
      final replace = await _showReplaceOldestDialog();
      if (replace != true || !mounted) return;
      // Retry with the duration the user already picked — never re-ask.
      outcome = await notifier.pinSelected(
        duration: duration,
        replaceOldest: true,
      );
    }
    if (outcome.kind == PinOutcomeKind.failed && outcome.message != null) {
      _snack(outcome.message!);
    }
  }

  // Part 2 — duration dialog. 24h preselected; one option is ALWAYS selected, so
  // the Pin button is never disabled for lack of a choice. Returns the chosen
  // PinDuration, or null on Cancel.
  Future<PinDuration?> _showPinDurationDialog() {
    return showDialog<PinDuration>(
      context: context,
      builder: (ctx) {
        var choice = PinDuration.twentyFourHours;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              MessagingStrings.pinDurationTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  MessagingStrings.pinDurationSubtitle,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 13,
                    color: _navy.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 8),
                // RadioGroup ancestor manages the selected value (current API —
                // Radio.groupValue/onChanged are deprecated). One option is always
                // selected (24h default), so Pin is never disabled for lack of one.
                RadioGroup<PinDuration>(
                  groupValue: choice,
                  onChanged: (v) {
                    if (v != null) setLocal(() => choice = v);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _durationOption(
                        PinDuration.twentyFourHours,
                        MessagingStrings.pinDuration24h,
                        (v) => setLocal(() => choice = v),
                      ),
                      _durationOption(
                        PinDuration.sevenDays,
                        MessagingStrings.pinDuration7d,
                        (v) => setLocal(() => choice = v),
                      ),
                      _durationOption(
                        PinDuration.thirtyDays,
                        MessagingStrings.pinDuration30d,
                        (v) => setLocal(() => choice = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  foregroundColor: _navy.withValues(alpha: 0.55),
                ),
                child: const Text(MessagingStrings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, choice),
                style: FilledButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: const Text(MessagingStrings.pinConfirm),
              ),
            ],
          ),
        );
      },
    );
  }

  // Radio row — gold accent only on the selected indicator (never a fill). The
  // selected value is owned by the enclosing RadioGroup; tapping the whole row
  // (InkWell) also selects, for a larger target.
  Widget _durationOption(
    PinDuration value,
    String label,
    ValueChanged<PinDuration> onSelect,
  ) {
    return InkWell(
      onTap: () => onSelect(value),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
        child: Row(
          children: [
            Radio<PinDuration>(
              value: value,
              activeColor: _gold,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              textAlign: TextAlign.start,
              style: const TextStyle(fontSize: 15, color: _navy),
            ),
          ],
        ),
      ),
    );
  }

  // Part 3 — replace-oldest confirm. Returns true on Continue, null/false on Cancel.
  Future<bool?> _showReplaceOldestDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          MessagingStrings.pinReplaceTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        content: Text(
          MessagingStrings.pinReplaceSubtitle,
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.60)),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: _navy.withValues(alpha: 0.55),
            ),
            child: const Text(MessagingStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            child: const Text(MessagingStrings.pinReplaceContinue),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final notifier = ref.read(chatProvider.notifier);
    // Snapshot options BEFORE the dialog — ownership + 48h window decide which
    // buttons appear. Server stays authoritative; this only hides affordances.
    final options = resolveDeleteOptions(notifier.selectedMessages);
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: Colors.white,
        title: Text(
          MessagingStrings.deleteDialogTitle(options.count),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        children: [
          if (options.showDeleteForEveryone)
            _deleteOption(ctx, MessagingStrings.deleteForEveryone, 'everyone'),
          _deleteOption(ctx, MessagingStrings.deleteForMe, 'me'),
          _deleteOption(ctx, MessagingStrings.cancel, null, muted: true),
        ],
      ),
    );
    if (scope == null || !mounted) return;

    final outcome = await notifier.deleteSelected(scope: scope);
    if (!mounted) return;
    if (outcome.succeeded == 0 && outcome.firstError != null) {
      _snack(appErrorMessage(outcome.firstError!));
    } else if (outcome.failed > 0) {
      // Partial success — successes already removed/tombstoned; name the misses.
      _snack(MessagingStrings.deletePartialFailure(outcome.failed));
    }
  }

  Widget _deleteOption(
    BuildContext ctx,
    String label,
    String? value, {
    bool muted = false,
  }) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          label,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontSize: 15,
            color: muted ? _navy.withValues(alpha: 0.55) : _navy,
            fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ── Message list ────────────────────────────────────────────────────────────

  Widget _messageList(ChatState state) {
    if (state.isLoading && state.messages.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
        ),
      );
    }
    if (state.error != null && state.messages.isEmpty) {
      return _fullError(state.error!);
    }
    if (state.messages.isEmpty) {
      return const Center(
        child: Text(
          MessagingStrings.chatEmpty,
          style: TextStyle(color: _navy, fontSize: 14),
        ),
      );
    }

    // list NEWEST-FIRST hai; ListView(reverse: true) isay ULTA kar deta hai taake
    // "sab se neeche = newest" natural initial position (offset 0) ho aur load-older
    // scroll-extent END pe trigger ho. (Ye har codebase mein logon ko confuse karta hai.)
    final rows = <Widget>[];
    final msgs = state.messages;
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      // M3 (Part 4): system notice — centred, muted, no bubble/avatar/timestamp,
      // and fully inert (no _MessageRow selection gestures, no _SwipeToReply).
      // The sentence is built here (server body is empty). "You" vs the other's
      // name is decided from isMine, the same signal bubbles use — no new source.
      if (m.type == MessageType.system) {
        rows.add(
          _SystemNotice(
            text: systemMessageText(
              eventType: m.systemEventType,
              isMine: m.isMine,
              otherName:
                  state.otherUser?.fullName ??
                  widget.summary?.otherUser.fullName ??
                  '',
            ),
          ),
        );
        final isOldestOfDay =
            i == msgs.length - 1 ||
            !_sameLocalDay(msgs[i].createdAt, msgs[i + 1].createdAt);
        if (isOldestOfDay) {
          rows.add(_DaySeparator(timestamp: msgs[i].createdAt));
        }
        continue;
      }
      // F-M5: stable GlobalKey per message — Scrollable.ensureVisible ke liye.
      _bubbleKeys.putIfAbsent(m.id, GlobalKey.new);
      final row = _MessageRow(
        key: _bubbleKeys[m.id],
        message: m,
        selecting: state.isSelecting,
        selected: state.selectedMessageIds.contains(m.id),
        highlighted: _highlightedMessageId == m.id,
        otherUserId: state.otherUserId,
        // M4 — one watermark for the whole conversation; the bubble derives its tick.
        otherLastReadAt: state.otherLastReadAt,
        // clientId sirf optimistic (failed) entries pe hota hai — null par no-op (koi `!` nahi).
        onRetry: () {
          final cid = m.clientId;
          if (cid != null) ref.read(chatProvider.notifier).retry(cid);
        },
        onTap: () {
          if (m.isDeleted) return; // tombstone not selectable
          if (state.isSelecting) {
            ref.read(chatProvider.notifier).toggleSelection(m.id);
          }
        },
        onLongPress: () {
          if (m.isDeleted) return; // tombstone not selectable
          ref.read(chatProvider.notifier).enterSelection(m.id);
        },
        onTapQuote: m.replyTo != null
            ? () => _jumpToQuoted(m.replyTo!.messageId)
            : null,
        // F-M7: tapping an existing chip toggles the caller's reaction with it.
        onReact: (emoji) => _react(m.id, emoji),
        // F-M5: tapping media opens the full-screen viewer (confirmed only).
        onOpenViewer: () => _openViewer(m),
      );
      // F-M5: swipe-to-reply wrapper. Disabled in selection mode and on tombstones.
      rows.add(
        _SwipeToReply(
          enabled: !state.isSelecting && !m.isDeleted,
          onReply: () {
            ref.read(chatProvider.notifier).setDraftReply(m);
            _focus.requestFocus();
          },
          child: row,
        ),
      );
      final isOldestOfDay =
          i == msgs.length - 1 ||
          !_sameLocalDay(msgs[i].createdAt, msgs[i + 1].createdAt);
      if (isOldestOfDay) rows.add(_DaySeparator(timestamp: msgs[i].createdAt));
    }
    // Reverse list mein ye "aakhri" rows sab se UPAR render hote hain (older end).
    if (state.isLoadingOlder) {
      rows.add(const _OlderSpinner());
    } else if (state.loadOlderFailed) {
      rows.add(
        _OlderRetry(onRetry: () => ref.read(chatProvider.notifier).loadOlder()),
      );
    }

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: rows.length,
      itemBuilder: (_, i) => rows[i],
    );
  }

  bool _sameLocalDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  Widget _fullError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: _navy.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _navy.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () => ref
                  .read(chatProvider.notifier)
                  .open(
                    conversationId: widget.conversationId,
                    summary: widget.summary,
                  ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                shape: const StadiumBorder(),
              ),
              child: const Text(MessagingStrings.retry),
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer: composer / accept-decline / waiting / declined / unknown ─────────

  Widget _footer(ChatState state) {
    // 403/404 from getConversation overrides all status-based logic — read-only.
    if (state.accessError != null) {
      return _infoStrip(state.accessError!);
    }
    // Cold-open loading: status unknown until getConversation returns — no footer yet.
    if (state.isLoading && state.status == null) {
      return const SizedBox.shrink();
    }
    // State derive: status + isRequest (Part 1). null status = unknown cold-open.
    final status = state.status;
    if (status == ConversationStatus.accepted) {
      return _composer(state); // State A
    }
    if (status == ConversationStatus.pending) {
      return state.isRequest
          ? _acceptDeclineBar(state) // State C — viewer = recipient
          : _infoStrip(
              MessagingStrings.stateBWaiting,
            ); // State B — viewer = initiator
    }
    if (status == ConversationStatus.declined) {
      return _infoStrip(MessagingStrings.stateDeclined); // State D
    }
    return _infoStrip(
      MessagingStrings.chatUnavailable,
    ); // unknown (null summary)
  }

  Widget _composer(ChatState state) {
    // F-M11: while a voice note is being recorded the composer is covered by the
    // recording UI. The normal Column stays MOUNTED underneath (as a Stack layer)
    // so the mic's press-and-hold GestureDetector keeps receiving the same drag —
    // rebuilding it away mid-gesture would break slide-to-cancel / drag-to-lock.
    final recording = ref.watch(voiceRecordingProvider);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _navy.withValues(alpha: 0.08))),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // F-M6: edit banner — shown when draftEdit is set (distinct from reply preview).
                if (state.draftEdit != null) _editBanner(onCancel: _cancelEdit),
                // F-M5: reply preview banner — shown when draftReply is set.
                if (state.draftEdit == null && state.draftReply != null)
                  _replyPreviewBanner(
                    reply: state.draftReply!,
                    otherUserId: state.otherUserId,
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (context, value, _) {
                      final len = value.text.characters.length;
                      final canSend = value.text.trim().isNotEmpty;
                      final remaining = MessagingStrings.messageCharLimit - len;
                      final showCounter =
                          len >= MessagingStrings.messageCharCounterThreshold;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showCounter)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 8,
                                bottom: 2,
                              ),
                              child: Text(
                                formatCount(remaining),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: remaining <= 0
                                      ? Colors.red.shade700
                                      : _navy.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // F-M5: attachment button — leading side, opens the
                              // Gallery/Camera sheet. Hidden while editing a message
                              // (an edit only changes text; attaching makes no sense).
                              if (state.draftEdit == null)
                                IconButton(
                                  icon: Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: _navy.withValues(alpha: 0.65),
                                  ),
                                  tooltip: MessagingStrings.attachTooltip,
                                  onPressed: _openAttachmentSheet,
                                ),
                              Expanded(
                                child: TextField(
                                  controller: _input,
                                  focusNode: _focus,
                                  minLines: 1,
                                  maxLines: 5,
                                  keyboardType: TextInputType.multiline,
                                  textInputAction: TextInputAction.newline,
                                  textAlignVertical: TextAlignVertical.center,
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(
                                      MessagingStrings.messageCharLimit,
                                    ),
                                  ],
                                  style: const TextStyle(
                                    color: _navy,
                                    fontSize: 15,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: MessagingStrings.composerHint,
                                    hintStyle: TextStyle(
                                      color: _navy.withValues(alpha: 0.40),
                                    ),
                                    filled: true,
                                    fillColor: _ivory,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                        color: _navy.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                        color: _navy.withValues(alpha: 0.12),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                        color: _gold.withValues(alpha: 0.65),
                                        width: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // F-M11: mic (empty field) ⇄ send (any text), animated so
                              // it doesn't flicker per keystroke. Editing always shows
                              // send. Decision is a pure fn (resolveComposerAction).
                              _trailingControl(value.text, state, canSend),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            // Holding (unlocked) recording UI — visual only (IgnorePointer) so the
            // mic GestureDetector beneath keeps the continuous hold-drag.
            if (recording.isActive && !recording.isLocked)
              Positioned.fill(
                child: IgnorePointer(child: _holdingOverlay(recording)),
              ),
            // Locked panel is interactive (delete / pause-resume / send).
            if (recording.isActive && recording.isLocked)
              Positioned.fill(child: _lockedPanel(recording)),
          ],
        ),
      ),
    );
  }

  // ── F-M11: composer mic/send swap + recording UI ────────────────────────────

  // Empty field → mic, any text → send (pure resolveComposerAction). Editing always
  // shows send. AnimatedSwitcher keeps the swap from flickering on every keystroke.
  Widget _trailingControl(String text, ChatState state, bool canSend) {
    final isEdit = state.draftEdit != null;
    final action = isEdit ? ComposerAction.send : resolveComposerAction(text);
    final Widget control;
    if (action == ComposerAction.send) {
      control = Material(
        key: const ValueKey('send'),
        color: canSend ? _navy : _navy.withValues(alpha: 0.25),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: canSend ? _submit : null,
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
          ),
        ),
      );
    } else {
      control = _micButton();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: control,
    );
  }

  // Press-and-hold to record. A quick tap (no hold) hints to hold. The three
  // long-press callbacks form ONE continuous gesture: start → move (cancel/lock) →
  // end (send/cancel/keep-locked).
  Widget _micButton() {
    return Semantics(
      button: true,
      label: MessagingStrings.voiceRecordTooltip,
      child: GestureDetector(
        key: const ValueKey('mic'),
        onTap: () => _snack(MessagingStrings.voiceHoldHint),
        onLongPressStart: _onMicHoldStart,
        onLongPressMoveUpdate: _onMicHoldMove,
        onLongPressEnd: _onMicHoldEnd,
        child: Material(
          color: _navy,
          shape: const CircleBorder(),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.mic_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Future<void> _onMicHoldStart(LongPressStartDetails d) async {
    _holdOffset = Offset.zero;
    _holdLocked = false;
    _holdOutcome = RecordDragOutcome.none;
    HapticFeedback.lightImpact(); // light haptic on start
    final ok = await ref.read(voiceRecordingProvider.notifier).start();
    if (!mounted) return;
    if (!ok) {
      _showMicPermissionDialog(); // denied — explain + offer settings
      return;
    }
    setState(() {});
  }

  void _onMicHoldMove(LongPressMoveUpdateDetails d) {
    if (_holdLocked) return; // already locked — ignore further drag
    if (!ref.read(voiceRecordingProvider).isActive) return; // never started
    _holdOffset = d.offsetFromOrigin;
    final outcome = resolveRecordingDrag(
      dragX: _holdOffset.dx,
      dragY: _holdOffset.dy,
      direction: Directionality.of(context),
    );
    if (outcome == RecordDragOutcome.lock) {
      _holdLocked = true;
      HapticFeedback.mediumImpact();
      ref.read(voiceRecordingProvider.notifier).lock();
    }
    setState(() => _holdOutcome = outcome);
  }

  void _onMicHoldEnd(LongPressEndDetails d) {
    if (_holdLocked) {
      _resetHold(); // locked recording continues hands-free
      return;
    }
    final notifier = ref.read(voiceRecordingProvider.notifier);
    if (ref.read(voiceRecordingProvider).isActive) {
      if (_holdOutcome == RecordDragOutcome.cancel) {
        notifier.cancel(); // crossed cancel → discard + delete file
      } else {
        notifier.finish(); // released → send (or discarded if under 1 s)
      }
    }
    _resetHold();
  }

  void _resetHold() {
    if (!mounted) return;
    setState(() {
      _holdOffset = Offset.zero;
      _holdOutcome = RecordDragOutcome.none;
      _holdLocked = false;
    });
  }

  Future<void> _showMicPermissionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          MessagingStrings.permissionMicTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _navy,
          ),
        ),
        content: Text(
          MessagingStrings.permissionMicBody,
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: _navy.withValues(alpha: 0.55),
            ),
            child: const Text(MessagingStrings.permissionDismiss),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppSettings.openAppSettings();
            },
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            child: const Text(MessagingStrings.permissionOpenSettings),
          ),
        ],
      ),
    );
  }

  // Unlocked (finger-down) recording UI: timer (leading) · slide-to-cancel hint
  // (following the finger, fading toward the cancel threshold) · a lock affordance
  // filling as the finger rises. Directions are start/end so RTL mirrors correctly.
  Widget _holdingOverlay(VoiceRecordingState rec) {
    final ltr = Directionality.of(context) == TextDirection.ltr;
    const cancelT = RecordDragThresholds.cancel;
    const lockT = RecordDragThresholds.lock;
    final startward = ((ltr ? -_holdOffset.dx : _holdOffset.dx)).clamp(
      0.0,
      cancelT,
    );
    final cancelProgress = (startward / cancelT).clamp(0.0, 1.0);
    final upward = (-_holdOffset.dy).clamp(0.0, lockT);
    final lockProgress = (upward / lockT).clamp(0.0, 1.0);

    return Container(
      color: Colors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 12, 8),
      child: Row(
        children: [
          _RecordingDot(paused: false),
          const SizedBox(width: 10),
          Text(
            formatMediaDuration(rec.elapsedMs),
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _navy,
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: Offset(ltr ? -startward : startward, 0),
              child: Opacity(
                opacity: (1 - cancelProgress).clamp(0.0, 1.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 18,
                      color: _navy.withValues(alpha: 0.45),
                    ),
                    Text(
                      MessagingStrings.voiceSlideToCancel,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 13,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _LockAffordance(progress: lockProgress),
        ],
      ),
    );
  }

  // Locked (hands-free) panel: delete · pause/resume (label+icon reflect state) ·
  // send. The timer stops while paused (elapsedMs is frozen by the notifier).
  Widget _lockedPanel(VoiceRecordingState rec) {
    final notifier = ref.read(voiceRecordingProvider.notifier);
    return Container(
      color: Colors.white,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: Colors.red.shade400,
            ),
            tooltip: MessagingStrings.voiceDelete,
            onPressed: () => notifier.cancel(),
          ),
          _RecordingDot(paused: rec.isPaused),
          const SizedBox(width: 8),
          Text(
            formatMediaDuration(rec.elapsedMs),
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _navy,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () =>
                rec.isPaused ? notifier.resume() : notifier.pause(),
            style: TextButton.styleFrom(foregroundColor: _navy),
            icon: Icon(
              rec.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 20,
            ),
            label: Text(
              rec.isPaused
                  ? MessagingStrings.voiceResume
                  : MessagingStrings.voicePause,
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _navy,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => notifier.finish(),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // F-M5: strip above the text field showing the quoted message.
  // Gold accent bar on leading side, sender name, snippet or type indicator.
  Widget _replyPreviewBanner({
    required MessageReply reply,
    required String? otherUserId,
  }) {
    final isReplyMine = otherUserId != null && reply.senderId != otherUserId;
    final displayName = isReplyMine
        ? MessagingStrings.replyYou
        : reply.senderName;
    final mutedColor = _navy.withValues(alpha: 0.55);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _navy.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          // Gold accent bar
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: _gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
                const SizedBox(height: 1),
                _replySnippetWidget(reply: reply, color: mutedColor),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: mutedColor),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () => ref.read(chatProvider.notifier).clearDraftReply(),
          ),
        ],
      ),
    );
  }

  // F-M6: editing banner — navy accent bar (vs gold for reply) so the two modes
  // are visually distinct and cannot be confused.
  Widget _editBanner({required VoidCallback onCancel}) {
    final mutedColor = _navy.withValues(alpha: 0.55);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 6),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: _navy.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              MessagingStrings.editBannerLabel,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.75),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: mutedColor),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: MessagingStrings.cancel,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  // Shared snippet renderer used by both the composer preview and _QuotedBlock.
  static Widget _replySnippetWidget({
    required MessageReply reply,
    required Color color,
  }) {
    if (reply.isDeleted) {
      return Text(
        MessagingStrings.replyDeletedQuote,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: color,
        ),
      );
    }
    return switch (reply.type) {
      MessageType.image => _replyTypeRow(
        Icons.image_rounded,
        MessagingStrings.replyPhoto,
        color,
      ),
      MessageType.video => _replyTypeRow(
        Icons.videocam_rounded,
        MessagingStrings.replyVideo,
        color,
      ),
      // F-M8 — a document quote shows its filename (the server sends no label);
      // middle-ellipsised so the extension survives and the row never overflows.
      MessageType.file => _replyTypeRow(
        Icons.description_rounded,
        (reply.fileName?.isNotEmpty ?? false)
            ? middleEllipsize(reply.fileName!, maxChars: 24)
            : MessagingStrings.replyFile,
        color,
      ),
      MessageType.voice => _replyTypeRow(
        Icons.mic_rounded,
        MessagingStrings.replyVoice,
        color,
      ),
      _ => Text(
        reply.bodySnippet,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: TextStyle(fontSize: 12, color: color),
      ),
    };
  }

  static Widget _replyTypeRow(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          textAlign: TextAlign.start,
          style: TextStyle(fontSize: 12, color: color),
        ),
      ],
    );
  }

  // State C — Accept (navy fill) / Decline (muted), F-M1 request_tile treatment.
  Widget _acceptDeclineBar(ChatState state) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _navy.withValues(alpha: 0.08))),
        ),
        child: state.actionBusy
            ? const SizedBox(
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _gold,
                    ),
                  ),
                ),
              )
            : Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: _decline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: BorderSide(
                            color: _navy.withValues(alpha: 0.30),
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          MessagingStrings.decline,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: _accept,
                        style: FilledButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          MessagingStrings.accept,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // State B / D / unknown — read-only informational strip (koi composer nahi).
  Widget _infoStrip(String text) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _navy.withValues(alpha: 0.08))),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: _navy.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 13,
                  color: _navy.withValues(alpha: 0.60),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Message bubble ──────────────────────────────────────────────────────────
// Own → AlignmentDirectional.centerEnd (RTL mein khud-ba-khud left aa jata hai,
// jo Arabic/Urdu ka sahi convention hai). Other → centerStart.

// Wraps a bubble with selection affordances: long-press enters selection, tap
// toggles while selecting, and the ENTIRE ROW tints when selected (spec: the
// whole row highlights, not just the bubble — and a tint, never a gold fill).
// F-M5: also shows a brief gold tint when `highlighted` (tap-to-jump landing).
class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.message,
    required this.selecting,
    required this.selected,
    required this.onRetry,
    required this.onTap,
    required this.onLongPress,
    this.highlighted = false,
    this.otherUserId,
    this.onTapQuote,
    this.otherLastReadAt,
    this.onReact,
    this.onOpenViewer,
  });

  final ChatMessage message;
  final bool selecting;
  final bool selected;
  final VoidCallback onRetry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool highlighted;
  final String? otherUserId;
  final VoidCallback? onTapQuote;
  final DateTime? otherLastReadAt; // M4 read-receipt watermark (UTC)
  final ValueChanged<String>? onReact; // F-M7 chip tap → toggle that emoji
  final VoidCallback? onOpenViewer; // F-M5 media tap → full-screen viewer

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    Color? bg;
    if (highlighted) {
      bg = _gold.withValues(alpha: 0.14);
    } else if (selected) {
      bg = _navy.withValues(alpha: 0.08);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: bg,
        child: _MessageBubble(
          message: message,
          onRetry: onRetry,
          otherUserId: otherUserId,
          onTapQuote: onTapQuote,
          otherLastReadAt: otherLastReadAt,
          onReact: onReact,
          onOpenViewer: onOpenViewer,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.onRetry,
    this.otherUserId,
    this.onTapQuote,
    this.otherLastReadAt,
    this.onReact,
    this.onOpenViewer,
  });

  final ChatMessage message;
  final VoidCallback onRetry;
  final String? otherUserId;
  final VoidCallback? onTapQuote;
  final DateTime? otherLastReadAt; // M4 read-receipt watermark (UTC)
  final ValueChanged<String>? onReact; // F-M7 chip tap → toggle that emoji
  final VoidCallback? onOpenViewer; // F-M5 media tap → full-screen viewer

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;

    // Tombstone (delete-for-everyone): muted italic placeholder rendered IN PLACE.
    // No meta, no retry, no pin — and not selectable (the row guards taps).
    if (message.isDeleted) {
      return Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: mine ? _navy.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _navy.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 14, color: _navy.withValues(alpha: 0.35)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  MessagingStrings.messageDeleted,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: _navy.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final pending = message.status == ChatSendStatus.pending;
    final failed = message.status == ChatSendStatus.failed;

    // F-M5: image/video render a thumbnail + optional caption (body). F-M11: voice
    // renders the voice bubble. Text renders its body; any OTHER non-text type
    // (file/unknown) → neutral placeholder.
    final isText = message.type == MessageType.text;
    final isMedia =
        message.type == MessageType.image || message.type == MessageType.video;
    final isVoice = message.type == MessageType.voice;
    final isFile = message.type == MessageType.file; // F-M8 document
    final hasCaption = message.body.isNotEmpty;
    final bodyText = isText
        ? message.body
        : MessagingStrings.unsupportedMessage;
    // Tap-to-view only once confirmed and the full asset URL exists.
    final canView =
        message.status == ChatSendStatus.confirmed &&
        (message.mediaUrl?.isNotEmpty ?? false);

    final bubbleColor = mine ? _navy : Colors.white;
    final textColor = mine ? Colors.white : _navy;

    final bubble = Opacity(
      opacity: pending ? 0.5 : 1.0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
          border: mine
              ? null
              : Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // F-M5: quoted block — rendered above body when this is a reply.
            if (message.replyTo != null)
              _QuotedBlock(
                reply: message.replyTo!,
                mine: mine,
                isReplyMine:
                    otherUserId != null &&
                    message.replyTo!.senderId != otherUserId,
                onTap: onTapQuote,
              ),
            // F-M6: "Forwarded" label — low visual weight, inside bubble.
            if (message.isForwarded)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.forward_rounded,
                      size: 11,
                      color: textColor.withValues(alpha: 0.45),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      MessagingStrings.forwardedLabel,
                      textAlign: TextAlign.start,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: textColor.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            // F-M5: media thumbnail (image/video). Coexists ABOVE the caption and
            // BELOW the quoted/forwarded blocks, so a forwarded reply with a caption
            // and reactions still lays out correctly.
            if (isMedia)
              MediaBubbleContent(
                message: message,
                onOpenViewer: canView ? onOpenViewer : null,
              ),
            if (isMedia && hasCaption)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Text(
                  message.body,
                  textAlign: TextAlign.start,
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
            // F-M8: document — distinct icon/name/size layout with a download-open
            // affordance. Caption (if any) renders below, like media.
            if (isFile)
              DocumentBubbleContent(
                // Keyed by id so the per-message download state never leaks onto
                // another message when the list recycles element state.
                key: ValueKey('doc-${message.id}'),
                message: message,
                mine: mine,
              ),
            if (isFile && hasCaption)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6),
                child: Text(
                  message.body,
                  textAlign: TextAlign.start,
                  style: TextStyle(fontSize: 15, color: textColor),
                ),
              ),
            // F-M11: voice note — avatar+badge | play/pause | waveform | meta row.
            // VoiceBubble owns the meta row (duration + ticks), so the shared meta
            // row below is suppressed for voice messages.
            if (isVoice)
              VoiceBubble(
                message: message,
                mine: mine,
                otherLastReadAt: otherLastReadAt,
                onRetry: onRetry,
              ),
            // Text body (or the neutral placeholder for an unknown non-text type) —
            // never media, voice or a document (each renders its own content above).
            if (!isMedia && !isVoice && !isFile)
              Text(
                bodyText,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: 15,
                  color: textColor,
                  fontStyle: isText ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            // Voice bubble owns its meta row — skip shared one to avoid duplication.
            if (!isVoice) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pin indicator — muted, low visual weight, sits before the time.
                  if (message.isPinned) ...[
                    Icon(
                      Icons.push_pin,
                      size: 11,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                  ],
                  _meta(
                    mine: mine,
                    pending: pending,
                    failed: failed,
                    textColor: textColor,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    // F-M7 — reaction chips attach under the bubble, aligned to the bubble's own
    // side (CrossAxisAlignment.start/end respect Directionality, so they mirror
    // under RTL). They live OUTSIDE the bubble box, so the metadata row (timestamp,
    // edited marker, ticks) inside the bubble is untouched.
    final hasReactions = message.reactions.isNotEmpty;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          bubble,
          if (hasReactions)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: mine ? 0 : 14,
                end: mine ? 14 : 0,
                bottom: 4,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.75,
                ),
                child: _ReactionChips(
                  reactions: message.reactions,
                  onTap: onReact,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Timestamp (muted) / pending clock / failed retry.
  Widget _meta({
    required bool mine,
    required bool pending,
    required bool failed,
    required Color textColor,
  }) {
    if (failed) {
      return InkWell(
        onTap: onRetry,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh, size: 13, color: Colors.red.shade400),
            const SizedBox(width: 4),
            Text(
              MessagingStrings.sendFailedRetry,
              style: TextStyle(fontSize: 11, color: Colors.red.shade400),
            ),
          ],
        ),
      );
    }
    if (pending) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 12,
            color: textColor.withValues(alpha: 0.6),
          ),
        ],
      );
    }
    // Confirmed bubble metadata row: optional "edited" marker · timestamp · read
    // tick. The tick joins this row (F-M6 edited marker already lives here) without
    // pushing it to wrap — an icon is far narrower than the timestamp it follows.
    final tick = _tickIcon(
      resolveTickState(message, otherLastReadAt),
      textColor: textColor,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // F-M6: "edited" marker sits before the timestamp (muted italic).
        if (message.editedAt != null) ...[
          Text(
            MessagingStrings.editedMarker,
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: textColor.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          formatBubbleTime(message.createdAt),
          style: TextStyle(
            fontSize: 10,
            color: textColor.withValues(alpha: 0.6),
          ),
        ),
        if (tick != null) ...[const SizedBox(width: 4), tick],
      ],
    );
  }

  // M4 read receipts — three states, on the caller's OWN messages only
  // (resolveTickState returns none for everything else, so this never renders on
  // the other person's bubbles, system notices, tombstones, or pending/failed
  // sends). Own bubbles sit on NAVY, so both states are tuned for a dark base:
  //   sent → single ✓ in muted white (textColor is white on own bubbles), the
  //          same weight as the timestamp; a plain grey ✓ would vanish on navy.
  //   read → double ✓✓ in gold (#C0A062), the CLAUDE.md accent — high contrast on
  //          navy and clearly distinct from the muted sent state.
  // A tick is an icon, not a button, so gold as its colour respects "gold is never
  // a button fill". Returns null for TickState.none (nothing rendered).
  Widget? _tickIcon(TickState state, {required Color textColor}) {
    switch (state) {
      case TickState.none:
        return null;
      case TickState.sent:
        return Icon(
          Icons.check,
          size: 13,
          color: textColor.withValues(alpha: 0.6),
        );
      case TickState.read:
        return const Icon(Icons.done_all, size: 13, color: _gold);
    }
  }
}

// ── Day separator (centered pill) ───────────────────────────────────────────

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.timestamp});
  final DateTime timestamp;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    final label = formatDateSeparator(
      timestamp,
      todayLabel: MessagingStrings.chatToday,
      yesterdayLabel: MessagingStrings.chatYesterday,
    );
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: _navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _navy.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}

// ── System notice (M3, Part 4) ───────────────────────────────────────────────
// Centred, muted, small. Not a bubble: no avatar, no background, no timestamp.
// Inert by construction — it is never wrapped in _MessageRow or _SwipeToReply.
class _SystemNotice extends StatelessWidget {
  const _SystemNotice({required this.text});
  final String text;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 7),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: _navy.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}

class _OlderSpinner extends StatelessWidget {
  const _OlderSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFC0A062),
          ),
        ),
      ),
    );
  }
}

class _OlderRetry extends StatelessWidget {
  const _OlderRetry({required this.onRetry});
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: OutlinedButton(
          onPressed: onRetry,
          style: OutlinedButton.styleFrom(
            foregroundColor: _navy,
            side: BorderSide(color: _navy.withValues(alpha: 0.35)),
            shape: const StadiumBorder(),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text(
            MessagingStrings.retry,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

// ── Quoted block (F-M5) ──────────────────────────────────────────────────────
// Rendered above the message body when the message is a reply.
// Works in both bubble styles (navy-fill / white) — colors adjusted per `mine`.

class _QuotedBlock extends StatelessWidget {
  const _QuotedBlock({
    required this.reply,
    required this.mine,
    required this.isReplyMine,
    this.onTap,
  });

  final MessageReply reply;
  final bool mine; // outer bubble style (navy fill vs white)
  final bool isReplyMine; // whether the QUOTED sender is the current user
  final VoidCallback? onTap;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final senderName = isReplyMine
        ? MessagingStrings.replyYou
        : reply.senderName;

    // Colors chosen to be legible on both backgrounds:
    // navy bubble (mine=true): white-tinted text; light block bg on dark base
    // white bubble (mine=false): navy-tinted text; very light tint on white base
    final blockBg = mine
        ? Colors.white.withValues(alpha: 0.12)
        : _navy.withValues(alpha: 0.06);
    final snippetColor = mine
        ? Colors.white.withValues(alpha: 0.65)
        : _navy.withValues(alpha: 0.55);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 7),
          color: blockBg,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Accent bar on leading side — Row respects Directionality so
                // this bar is on the right in RTL without any branching.
                Container(width: 3, color: _gold),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _ChatScreenState._replySnippetWidget(
                          reply: reply,
                          color: snippetColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Swipe-to-reply (F-M5) ────────────────────────────────────────────────────
// Wraps any message row with a startToEnd horizontal drag gesture.
// One direction for ALL bubbles regardless of sender (isMine is NOT branched).
// startToEnd resolves to right-drag in LTR and left-drag in RTL automatically —
// both match the bubbles' own mirror behaviour, giving RTL users a consistent feel.
//
// Implementation: custom GestureDetector + Transform.translate (NOT Dismissible).
// Dismissible removes the item on a completed drag; confirmDismiss:false is a
// workaround but still briefly removes the item from the build subtree. The custom
// gesture gives exact control over spring-back and never touches the list item.

class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _threshold = 60.0;
  static const _maxDrag = 72.0;
  static const _navy = Color(0xFF0A1633);

  late final AnimationController _ctrl;
  double _drag = 0.0;
  double _dragAtRelease = 0.0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onSpringTick);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onSpringTick() {
    if (!mounted) return;
    setState(() {
      _drag = (_dragAtRelease * (1.0 - Curves.easeOut.transform(_ctrl.value)))
          .clamp(0.0, _maxDrag);
      if (_ctrl.isCompleted) _triggered = false;
    });
  }

  // Convert raw dx to "startToEnd" direction, regardless of which side isMine.
  // LTR: positive dx = startToEnd (allow). RTL: negative dx = startToEnd (invert).
  double _effectiveDelta(double dx) {
    return Directionality.of(context) == TextDirection.ltr ? dx : -dx;
  }

  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    _triggered = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final eff = _effectiveDelta(d.delta.dx);
    if (eff < 0 && _drag <= 0) return; // reject end-to-start drag from rest
    setState(() => _drag = (_drag + eff).clamp(0.0, _maxDrag));
    if (_drag >= _threshold && !_triggered) {
      _triggered = true;
      HapticFeedback.selectionClick();
      widget.onReply();
    }
  }

  void _onDragEnd(DragEndDetails _) => _springBack();
  void _onDragCancel() => _springBack();

  void _springBack() {
    _dragAtRelease = _drag;
    if (_dragAtRelease == 0) {
      _triggered = false;
      return;
    }
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final td = Directionality.of(context);
    // Display offset: positive (end direction) in LTR, negative (end direction) in RTL.
    final displayOffset = td == TextDirection.ltr ? _drag : -_drag;

    return GestureDetector(
      onHorizontalDragStart: widget.enabled ? _onDragStart : null,
      onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
      onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
      onHorizontalDragCancel: widget.enabled ? _onDragCancel : null,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Reply icon fades in on the leading side as the bubble slides away.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: Opacity(
                opacity: (_drag / _threshold).clamp(0.0, 1.0),
                child: Icon(
                  Icons.reply_rounded,
                  color: _navy.withValues(alpha: 0.45),
                  size: 22,
                ),
              ),
            ),
          ),
          // Bubble slides in the startToEnd direction.
          Transform.translate(
            offset: Offset(displayOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// ── Pin banner (F-M6) ────────────────────────────────────────────────────────
// Slim banner below the app bar. Tap → cycle + jump. Unpin icon → remove pin.
// Only shown when pinnedMessages is non-empty and not in selection mode.

class _PinBanner extends StatelessWidget {
  const _PinBanner({
    required this.pinnedMessages,
    required this.pinnedIndex,
    required this.onTap,
    required this.onUnpin,
  });

  final List<ChatMessage> pinnedMessages;
  final int pinnedIndex;
  final VoidCallback onTap;
  final VoidCallback onUnpin;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  String _snippet(ChatMessage m) {
    if (m.isDeleted) return MessagingStrings.messageDeleted;
    return switch (m.type) {
      MessageType.image => MessagingStrings.replyPhoto,
      MessageType.video => MessagingStrings.replyVideo,
      // F-M8 — prefer the document's filename over the generic label.
      MessageType.file => (m.mediaFileName?.isNotEmpty ?? false)
          ? m.mediaFileName!
          : MessagingStrings.replyFile,
      MessageType.voice => MessagingStrings.replyVoice,
      _ => m.body,
    };
  }

  @override
  Widget build(BuildContext context) {
    final total = pinnedMessages.length;
    final safeIdx = clampPinIndex(pinnedIndex, total);
    final current = pinnedMessages[safeIdx];
    final seg = resolvePinSegments(total, safeIdx);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: _navy.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              // Segment bars on the leading side — one per active pin (≤4), the
              // current one gold, the rest muted. Replaces the old "N of M" text.
              _PinSegmentBars(count: seg.count, activeIndex: seg.activeIndex),
              const SizedBox(width: 10),
              Icon(Icons.push_pin, size: 13, color: _gold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _snippet(current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 13,
                    color: _navy.withValues(alpha: 0.70),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.push_pin_outlined,
                  size: 16,
                  color: _navy.withValues(alpha: 0.40),
                ),
                tooltip: MessagingStrings.pinBannerUnpinTooltip,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
                onPressed: onUnpin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Segment bars for the pin banner (WhatsApp-style). A row of thin vertical
// segments; the active one is gold, the rest muted navy. Tap advancing is
// driven entirely by the banner's onTap — there is NO timer cycling pins.
class _PinSegmentBars extends StatelessWidget {
  const _PinSegmentBars({required this.count, required this.activeIndex});

  final int count;
  final int activeIndex;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(end: i == count - 1 ? 0 : 3),
            child: Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: i == activeIndex ? _gold : _navy.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Reaction chips (F-M7, Part 3) ─────────────────────────────────────────────
// A wrapping row of chips under the bubble. WRAP (not cap) was chosen: reactions
// on a 1:1 thread are few, and wrapping keeps every distinct emoji visible without
// a hidden "+N" the user can't act on. Counts go through formatCount so Arabic /
// Urdu render their own digits; a count of 1 shows the emoji alone.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({required this.reactions, this.onTap});

  final List<MessageReaction> reactions;
  final ValueChanged<String>? onTap;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final r in reactions) _chip(r)],
    );
  }

  Widget _chip(MessageReaction r) {
    // reactedByMe → distinguished by the GOLD BORDER only (accent, never a fill),
    // per CLAUDE.md. Others: hairline navy border on white.
    final mine = r.reactedByMe;
    return Semantics(
      button: true,
      selected: mine,
      label: MessagingStrings.reactWith(r.emoji),
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap!(r.emoji),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 8,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mine
                  ? _gold.withValues(alpha: 0.85)
                  : _navy.withValues(alpha: 0.12),
              width: mine ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.emoji, style: const TextStyle(fontSize: 13)),
              if (r.count > 1) ...[
                const SizedBox(width: 3),
                Text(
                  formatCount(r.count),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Floating reaction bar (F-M7, Part 1) ──────────────────────────────────────
// Six quick emoji + a "+" to open the full picker. The caller's current reaction
// is highlighted; tapping it again removes it (the same toggle the backend does).
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.myEmoji,
    required this.onSelect,
    required this.onMore,
  });

  final String? myEmoji;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 6,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in kQuickReactionEmojis) _emojiButton(e),
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsetsDirectional.symmetric(horizontal: 2),
                color: _navy.withValues(alpha: 0.10),
              ),
              IconButton(
                icon: Icon(
                  Icons.add_rounded,
                  color: _navy.withValues(alpha: 0.65),
                ),
                tooltip: MessagingStrings.reactionMoreTooltip,
                onPressed: onMore,
                iconSize: 20,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiButton(String emoji) {
    final selected = emoji == myEmoji;
    return Semantics(
      button: true,
      label: MessagingStrings.reactWith(emoji),
      child: InkResponse(
        onTap: () => onSelect(emoji),
        radius: 22,
        child: Container(
          padding: const EdgeInsets.all(6),
          // Caller's current reaction → gold RING (accent), not a gold fill.
          decoration: selected
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold, width: 1.6),
                )
              : null,
          child: Text(emoji, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}

// ── Full emoji picker sheet (F-M7, Part 2 — curated grid, Option B) ────────────
// ~130 curated emoji in six categories, no dependency. Selecting one pops the
// chosen emoji back to the caller, which applies the reaction and closes. No
// search box and no skin-tone selector this slice (noted in docs/TODO.md).
class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // Parallel to kEmojiPickerGroups (same order).
  static const _labels = [
    MessagingStrings.reactionCatSmileys,
    MessagingStrings.reactionCatGestures,
    MessagingStrings.reactionCatHearts,
    MessagingStrings.reactionCatAnimals,
    MessagingStrings.reactionCatFood,
    MessagingStrings.reactionCatActivities,
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
                child: Text(
                  MessagingStrings.reactionPickerTitle,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                itemCount: kEmojiPickerGroups.length,
                itemBuilder: (context, i) =>
                    _category(context, _labels[i], kEmojiPickerGroups[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _category(BuildContext context, String label, List<String> emojis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            top: 10,
            bottom: 6,
            start: 4,
          ),
          child: Text(
            label,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _gold,
            ),
          ),
        ),
        Wrap(
          children: [
            for (final e in emojis)
              InkResponse(
                onTap: () => Navigator.of(context).pop(e),
                radius: 24,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── F-M11 recording UI bits ───────────────────────────────────────────────────

// A small red dot marking an active recording; hollow while paused.
class _RecordingDot extends StatelessWidget {
  const _RecordingDot({required this.paused});
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: paused ? Colors.transparent : Colors.red.shade400,
        border: paused
            ? Border.all(color: Colors.red.shade400, width: 2)
            : null,
      ),
    );
  }
}

// The lock affordance shown on the trailing side while holding. A capsule track
// with a lock icon; a navy fill rises from the bottom as the finger rises (gold is
// reserved as an accent, never a fill). At full fill the recording locks.
class _LockAffordance extends StatelessWidget {
  const _LockAffordance({required this.progress});
  final double progress; // 0..1

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 40,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _navy.withValues(alpha: 0.15)),
            ),
          ),
          FractionallySizedBox(
            heightFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          Positioned(
            top: 6,
            child: Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: progress >= 1.0 ? _gold : _navy.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
