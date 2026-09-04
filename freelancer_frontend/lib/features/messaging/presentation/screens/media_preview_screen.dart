// F-M5 Part 3 — preview + caption screen, pushed AFTER picking and BEFORE anything
// is sent. Sending straight from the picker gives no chance to add a caption or
// change one's mind.
//   • Full-bleed image, or the video's first frame with a play control.
//   • Optional caption field + send button (empty caption is fine).
//   • Back cancels the whole thing and uploads nothing.
//   • A reply in progress is carried through and its quoted preview shown here.
// The actual optimistic-send happens in ChatNotifier.sendMedia; this screen only
// gathers the caption then pops. Size/type were already validated before this push
// (see ChatScreen._pickAndPreview); video DURATION is validated by the server.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../application/chat_notifier.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

class MediaPreviewScreen extends ConsumerStatefulWidget {
  const MediaPreviewScreen({
    super.key,
    required this.path,
    required this.kind,
  });

  final String path;
  final PickedMediaKind kind;

  @override
  ConsumerState<MediaPreviewScreen> createState() => _MediaPreviewScreenState();
}

class _MediaPreviewScreenState extends ConsumerState<MediaPreviewScreen> {
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _caption = TextEditingController();
  bool _sending = false; // double-tap guard — one upload per pick
  VideoPlayerController? _video;
  bool _videoReady = false;

  bool get _isVideo => widget.kind == PickedMediaKind.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(File(widget.path));
    _video = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _videoReady = true);
    } catch (_) {
      // First-frame preview failing is non-fatal — the still is skipped, send works.
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.pause();
    _video?.dispose();
    super.dispose();
  }

  void _send() {
    if (_sending) return; // guard: a second tap must not spawn a second upload
    setState(() => _sending = true);
    // Fire the optimistic media send on the chat notifier, then leave — the bubble
    // (with progress) is already in the list behind this screen.
    ref.read(chatProvider.notifier).sendMedia(
          path: widget.path,
          kind: widget.kind,
          caption: _caption.text,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Carry the in-progress reply through; show its quoted preview here too.
    final reply = ref.watch(chatProvider.select((s) => s.draftReply));
    final otherUserId = ref.watch(chatProvider.select((s) => s.otherUserId));

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          // Back cancels everything — nothing is uploaded.
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _preview())),
          if (reply != null)
            _QuotedPreview(reply: reply, otherUserId: otherUserId),
          _captionBar(),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_isVideo) {
      final c = _video;
      if (!_videoReady || c == null) {
        return const CircularProgressIndicator(strokeWidth: 2, color: _gold);
      }
      return Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio:
                c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          // Play control over the first frame; tap toggles inline playback.
          GestureDetector(
            onTap: () =>
                setState(() => c.value.isPlaying ? c.pause() : c.play()),
            child: AnimatedOpacity(
              opacity: c.value.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow_rounded,
                    size: 48, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Image.file(File(widget.path), fit: BoxFit.contain),
    );
  }

  Widget _captionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
        color: Colors.black,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _caption,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                enabled: !_sending,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: MessagingStrings.mediaCaptionHint,
                  hintStyle:
                      TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send — navy fill circle (gold never a button fill), per CLAUDE.md.
            Material(
              color: _sending ? _navy.withValues(alpha: 0.4) : _navy,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Compact quoted-reply strip shown above the caption bar (dark theme variant).
class _QuotedPreview extends StatelessWidget {
  const _QuotedPreview({required this.reply, required this.otherUserId});

  final MessageReply reply;
  final String? otherUserId;

  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final isReplyMine =
        otherUserId != null && reply.senderId != otherUserId;
    final name = isReplyMine ? MessagingStrings.replyYou : reply.senderName;
    final snippet = reply.isDeleted
        ? MessagingStrings.replyDeletedQuote
        : switch (reply.type) {
            MessageType.image => MessagingStrings.replyPhoto,
            MessageType.video => MessagingStrings.replyVideo,
            MessageType.file => MessagingStrings.replyFile,
            MessageType.voice => MessagingStrings.replyVoice,
            _ => reply.bodySnippet,
          };

    return Container(
      width: double.infinity,
      color: Colors.white.withValues(alpha: 0.06),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: _gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
