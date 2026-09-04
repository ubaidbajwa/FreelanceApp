// F-M5 Part 5 — the image/video content inside a message bubble.
//
// Reserving space BEFORE load: the box is sized from the server's mediaWidth/Height
// via resolveMediaBox, so the bubble occupies its final area before the thumbnail
// arrives and the list never reflows. A pending (optimistic) bubble shows the LOCAL
// file with a progress overlay; a confirmed bubble shows the cached THUMBNAIL (never
// the full mediaUrl — that is only for the viewer) and opens the viewer on tap.
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../application/chat_notifier.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

class MediaBubbleContent extends StatefulWidget {
  const MediaBubbleContent({
    super.key,
    required this.message,
    this.onOpenViewer,
  });

  final ChatMessage message;
  // Non-null only for a confirmed message with a full mediaUrl — tap opens the viewer.
  final VoidCallback? onOpenViewer;

  @override
  State<MediaBubbleContent> createState() => _MediaBubbleContentState();
}

class _MediaBubbleContentState extends State<MediaBubbleContent> {
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  // Bumped to force CachedNetworkImage to re-fetch after a load failure (tap retry).
  int _reloadToken = 0;

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final screen = MediaQuery.sizeOf(context);
    final box = resolveMediaBox(
      mediaWidth: m.mediaWidth,
      mediaHeight: m.mediaHeight,
      maxWidth: screen.width * 0.62,
      maxHeight: screen.height * 0.42,
    );
    final pending = m.status == ChatSendStatus.pending;
    final isVideo = m.type == MessageType.video;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: box.width,
        height: box.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _thumbnail(m, box),
            // Video affordances: centre play glyph + duration badge (m:ss).
            if (isVideo && !pending) _videoOverlay(m),
            // Pending upload: dark scrim + real progress ring over the local file.
            if (pending) _progressOverlay(m.uploadProgress),
            // Tap to open the full-screen viewer (confirmed messages only).
            if (widget.onOpenViewer != null)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: widget.onOpenViewer),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(ChatMessage m, MediaBox box) {
    // Optimistic bubble → local file (loads instantly, no network). A VIDEO file
    // can't be decoded by Image.file, and extracting a frame needs another
    // dependency, so a pending video shows a neutral dark tile until the server
    // thumbnail arrives; the progress overlay sits on top either way.
    final local = m.mediaLocalPath;
    if (local != null) {
      if (m.type == MessageType.video) {
        return Container(color: _navy.withValues(alpha: 0.85));
      }
      return Image.file(File(local), fit: BoxFit.cover);
    }
    final url = m.mediaThumbnailUrl;
    if (url == null || url.isEmpty) return _placeholder();
    return CachedNetworkImage(
      key: ValueKey(_reloadToken),
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _errorRetry(),
    );
  }

  Widget _placeholder() {
    return Container(
      color: _navy.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      ),
    );
  }

  // Tapping re-fetches by bumping the CachedNetworkImage key. Sits above the
  // viewer-open InkWell (which is disabled on failure anyway — no full url yet).
  Widget _errorRetry() {
    return GestureDetector(
      onTap: () => setState(() => _reloadToken++),
      child: Container(
        color: _navy.withValues(alpha: 0.06),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                size: 28, color: _navy.withValues(alpha: 0.4)),
            const SizedBox(height: 6),
            Text(
              MessagingStrings.mediaTapToRetry,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: _navy.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoOverlay(ChatMessage m) {
    return IgnorePointer(
      child: Stack(
        children: [
          const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x59000000), // black @ 35%
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.play_arrow_rounded,
                    size: 32, color: Colors.white),
              ),
            ),
          ),
          PositionedDirectional(
            start: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded,
                      size: 12, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    formatMediaDuration(m.mediaDurationMs),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressOverlay(double? progress) {
    return IgnorePointer(
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.center,
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.white,
            // Real determinate progress from dio; null before the first callback.
            value: (progress ?? 0) <= 0 ? null : progress,
          ),
        ),
      ),
    );
  }
}
