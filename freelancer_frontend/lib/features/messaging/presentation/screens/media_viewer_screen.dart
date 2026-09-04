// F-M5 Part 6 — full-screen media viewer.
//   Images: full mediaUrl in an InteractiveViewer (pinch-zoom + pan), swipe-down to
//           dismiss, on a black backdrop.
//   Videos: video_player with play/pause, a scrub bar, and elapsed/total time.
// A header shows the sender name + timestamp; back dismisses. The video controller
// is paused and disposed on exit (a leaked controller keeps audio playing).
//
// Swiping BETWEEN a conversation's media is out of scope (see docs/TODO.md).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/relative_time.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.mediaUrl,
    required this.type,
    required this.senderName,
    required this.createdAt,
    this.mediaDurationMs,
  });

  final String mediaUrl;
  final MessageType type; // image or video
  final String senderName;
  final DateTime createdAt; // UTC — rendered .toLocal() via helper
  final int? mediaDurationMs;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  static const _gold = Color(0xFFC0A062);

  VideoPlayerController? _controller;
  bool _videoReady = false;
  bool _videoError = false;

  bool get _isVideo => widget.type == MessageType.video;

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.mediaUrl));
    _controller = c;
    try {
      await c.initialize();
      if (!mounted) return;
      setState(() => _videoReady = true);
      c.play();
      c.addListener(_tick);
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoError = true);
    }
  }

  // Rebuild for the scrub bar / elapsed time / play-pause icon as playback advances.
  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Pause THEN dispose — never leak the controller (audio would keep playing).
    _controller?.removeListener(_tick);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        elevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(
              formatBubbleTime(widget.createdAt),
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
      body: Center(child: _isVideo ? _videoBody() : _imageBody()),
    );
  }

  // Image: pinch-zoom + pan, and a vertical drag that pops when dragged down far
  // enough (swipe-to-dismiss) — only meaningful while not zoomed.
  Widget _imageBody() {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).pop();
      },
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: CachedNetworkImage(
          imageUrl: widget.mediaUrl,
          fit: BoxFit.contain,
          placeholder: (_, _) => const _ViewerSpinner(),
          errorWidget: (_, _, _) => const _ViewerError(),
        ),
      ),
    );
  }

  Widget _videoBody() {
    if (_videoError) return const _ViewerError();
    final c = _controller;
    if (!_videoReady || c == null) return const _ViewerSpinner();

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
        // Tap anywhere to toggle play/pause.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(
                () => c.value.isPlaying ? c.pause() : c.play()),
            child: AnimatedOpacity(
              opacity: c.value.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: const Center(
                child: Icon(Icons.play_arrow_rounded,
                    size: 72, color: Colors.white),
              ),
            ),
          ),
        ),
        // Scrub bar + elapsed / total time along the bottom.
        Positioned(
          left: 16,
          right: 16,
          bottom: 32,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: _gold,
                  bufferedColor: Colors.white.withValues(alpha: 0.3),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatMediaDuration(c.value.position.inMilliseconds),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    formatMediaDuration(c.value.duration.inMilliseconds),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewerSpinner extends StatelessWidget {
  const _ViewerSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: Color(0xFFC0A062)),
      );
}

class _ViewerError extends StatelessWidget {
  const _ViewerError();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined,
            size: 44, color: Colors.white.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(
          MessagingStrings.mediaLoadFailed,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}
