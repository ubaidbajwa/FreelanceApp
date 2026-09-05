// F-M11 Part 7 (redesign) — voice-note bubble: avatar with mic badge, play/pause,
// waveform with gold playhead dot, and an owned meta row (duration | ticks).
// Owns the meta row so _MessageBubble suppresses its shared row for voice messages.
// Legible on BOTH the navy own-bubble and the light other-bubble — colours chosen
// per `mine`. Width fills 75 % of screen (parent constraint) via Expanded waveform;
// no fixed SizedBox so narrow screens don't clip.
//
// Avatar: incoming → otherUser from chatProvider; own → profileSummaryProvider,
// the same source the app shell drawer uses for the current user's photo/name.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../../../core/utils/relative_time.dart';
import '../../application/chat_notifier.dart';
import '../../application/message_actions.dart';
import '../../application/voice_playback_notifier.dart';
import '../../messaging_strings.dart';
import '../../../shell/application/profile_summary_notifier.dart';

class VoiceBubble extends ConsumerWidget {
  const VoiceBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.otherLastReadAt,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool mine;
  final DateTime? otherLastReadAt; // M4 read-receipt watermark (UTC)
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Own bubble sits on navy → light controls; other bubble on white → navy.
    final fg = mine ? Colors.white : _navy;
    final barBase = mine
        ? Colors.white.withValues(alpha: 0.40)
        : _navy.withValues(alpha: 0.25);

    // Avatar source: incoming = otherUser; own = shell profile summary.
    final otherUser = ref.watch(chatProvider.select((s) => s.otherUser));
    final profile = ref.watch(profileSummaryProvider);
    final senderName = mine ? profile.displayName : (otherUser?.fullName ?? '');
    final senderPhotoUrl = mine ? profile.photoUrl : otherUser?.photoUrl;

    final levels = parseWaveform(message.mediaWaveform);
    final pending = message.status == ChatSendStatus.pending;
    final failed = message.status == ChatSendStatus.failed;
    final url = message.mediaUrl;
    final canPlay =
        message.status == ChatSendStatus.confirmed &&
        (url != null && url.isNotEmpty);

    final playback = ref.watch(voicePlaybackProvider);
    final playing = canPlay && playback.isPlaying(message.id);
    final progress = canPlay ? playback.progressFor(message.id) : 0.0;

    // Elapsed while playing; total otherwise (spec: switch back to total when paused).
    final totalMs = message.mediaDurationMs ?? 0;
    final displayMs = (canPlay && playback.isActive(message.id) && playing)
        ? playback.position.inMilliseconds
        : totalMs;

    // Bind to a promoted non-null local — no `!` on the server-supplied nullable.
    final playUrl = message.mediaUrl;
    final onToggle = (canPlay && playUrl != null)
        ? () => _startOrToggle(ref, playUrl)
        : null;

    // Mic badge (F-M11 M7): a COLOUR SWAP, never a re-layout. Incoming note reflects
    // playedByMe ("I have listened"); own note reflects playedByOther ("they have
    // listened to mine") — the asymmetry lives in resolvePlayedBadge. Unplayed → the
    // muted treatment; played → gold. Never blue: gold is the app accent (CLAUDE.md),
    // already used for read ticks and the waveform playhead.
    final unplayedBadgeColor = mine
        ? Colors.white.withValues(alpha: 0.50)
        : _navy.withValues(alpha: 0.40);
    final micBadgeIconColor =
        resolvePlayedBadge(message) == PlayedBadgeState.played
        ? _gold
        : unplayedBadgeColor;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: avatar+badge | play/pause | waveform+dot
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _avatar(
              senderName: senderName,
              photoUrl: senderPhotoUrl,
              micBadgeIconColor: micBadgeIconColor,
            ),
            const SizedBox(width: 8),
            _leadingControl(
              context,
              pending: pending,
              playing: playing,
              fg: fg,
              onToggle: onToggle,
            ),
            const SizedBox(width: 8),
            // Expanded fills the remaining bubble width; LayoutBuilder gives the
            // exact pixel width for tap-to-seek fraction and dot positioning.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: canPlay
                        ? (d) => _onWaveformTap(
                            ref,
                            d.localPosition.dx,
                            constraints.maxWidth,
                          )
                        : null,
                    child: SizedBox(
                      height: 34,
                      child: CustomPaint(
                        painter: _WaveformPainter(
                          levels: levels,
                          progress: progress,
                          baseColor: barBase,
                          playedColor: _gold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        // Row 2: duration (leading) | Spacer | pin? + timestamp + ticks (trailing).
        // mainAxisSize.max lets Spacer distribute the full bubble width.
        Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              formatMediaDuration(displayMs),
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.75)),
            ),
            const Spacer(),
            if (message.isPinned) ...[
              Icon(Icons.push_pin, size: 11, color: fg.withValues(alpha: 0.60)),
              const SizedBox(width: 4),
            ],
            _voiceMeta(fg: fg, pending: pending, failed: failed),
          ],
        ),
      ],
    );
  }

  // Circular avatar with a small mic badge pinned to its trailing-bottom corner.
  // The 36×36 SizedBox gives the badge 4 px of overlap room beyond the 32 px avatar.
  Widget _avatar({
    required String senderName,
    required String? photoUrl,
    required Color micBadgeIconColor,
  }) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        children: [
          UserAvatar(fullName: senderName, photoUrl: photoUrl, radius: 16),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // White badge face keeps the mic icon legible on both bubble colours.
                color: Colors.white,
                border: Border.all(
                  color: _navy.withValues(alpha: 0.10),
                  width: 0.5,
                ),
              ),
              child: Center(
                // Animate the colour so a played event doesn't pop harshly. begin
                // is null → no motion on first paint (the resolved colour shows
                // immediately); it lerps only when micBadgeIconColor CHANGES, i.e.
                // when MessagePlayed flips the badge to gold mid-screen.
                child: TweenAnimationBuilder<Color?>(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  tween: ColorTween(end: micBadgeIconColor),
                  builder: (context, color, _) =>
                      Icon(Icons.mic, size: 9, color: color ?? micBadgeIconColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leadingControl(
    BuildContext context, {
    required bool pending,
    required bool playing,
    required Color fg,
    required VoidCallback? onToggle,
  }) {
    if (pending) {
      final p = message.uploadProgress;
      return SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: fg.withValues(alpha: 0.7),
          value: (p ?? 0) <= 0 ? null : p,
        ),
      );
    }
    final label = playing
        ? MessagingStrings.voicePlaybackPause
        : MessagingStrings.voicePlay;
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        radius: 24,
        onTap: onToggle,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: mine
                ? Colors.white.withValues(alpha: 0.18)
                : _navy.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 22,
            color: onToggle != null ? fg : fg.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }

  // Mirrors _MessageBubble._meta logic, scoped to voice-bubble colours.
  Widget _voiceMeta({
    required Color fg,
    required bool pending,
    required bool failed,
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
      return Icon(Icons.schedule, size: 12, color: fg.withValues(alpha: 0.60));
    }
    final tickState = resolveTickState(message, otherLastReadAt);
    Widget? tickWidget;
    switch (tickState) {
      case TickState.none:
        break;
      case TickState.sent:
        tickWidget = Icon(
          Icons.check,
          size: 13,
          color: fg.withValues(alpha: 0.60),
        );
      case TickState.read:
        tickWidget = const Icon(Icons.done_all, size: 13, color: _gold);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatBubbleTime(message.createdAt),
          style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.60)),
        ),
        if (tickWidget != null) ...[const SizedBox(width: 4), tickWidget],
      ],
    );
  }

  // Toggle playback, and on a genuine START (not resume-after-pause) fire the played
  // receipt. "Fresh start" = this note is not the one currently loaded in the shared
  // player; a paused note is still active, so resuming it must NOT re-mark. The
  // notifier applies shouldMarkPlayed (own/non-voice/tombstone/already-played skip),
  // so calling it unconditionally on a fresh start is safe.
  void _startOrToggle(WidgetRef ref, String url) {
    final freshStart = !ref.read(voicePlaybackProvider).isActive(message.id);
    ref.read(voicePlaybackProvider.notifier).toggle(message.id, url);
    if (freshStart) ref.read(chatProvider.notifier).markPlayed(message.id);
  }

  // Tap-to-seek: fraction maps dx → 0..1. Starts playback if note isn't loaded yet.
  void _onWaveformTap(WidgetRef ref, double dx, double width) {
    if (width <= 0) return;
    final tapUrl = message.mediaUrl;
    if (tapUrl == null || tapUrl.isEmpty) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final notifier = ref.read(voicePlaybackProvider.notifier);
    final playback = ref.read(voicePlaybackProvider);
    if (playback.isActive(message.id)) {
      notifier.seekFraction(message.id, fraction);
    } else {
      // Fresh start from a waveform tap → also fire the played receipt.
      notifier.toggle(message.id, tapUrl);
      ref.read(chatProvider.notifier).markPlayed(message.id);
    }
  }
}

// Rounded bars scaled from 0–100 levels; played portion is gold, unplayed is muted.
// A gold circular playhead dot rides on top of bars at the current progress position.
// At rest (progress = 0) the dot sits at the leading edge. Empty levels → flat bar.
// TODO(voice-scrub): draggable dot for scrubbing is out of scope for this slice.
// Implement via GestureDetector.onHorizontalDragUpdate reusing the _onWaveformTap
// fraction mapping — no CustomPainter change needed.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.baseColor,
    required this.playedColor,
  });

  final List<int> levels;
  final double progress; // 0..1 playback fill
  final Color baseColor;
  final Color playedColor; // always _gold per design system

  static const _dotRadius = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    if (levels.isEmpty) {
      final paint = Paint()
        ..color = baseColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3;
      canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);
      if (progress > 0) {
        canvas.drawLine(
          Offset(0, midY),
          Offset(size.width * progress, midY),
          paint..color = playedColor,
        );
      }
      _drawDot(canvas, size, midY);
      return;
    }

    const barGap = 2.0;
    final n = levels.length;
    final barWidth = ((size.width - barGap * (n - 1)) / n).clamp(1.5, 6.0);
    final playedX = size.width * progress;

    for (var i = 0; i < n; i++) {
      final x = i * (barWidth + barGap);
      final h = (levels[i] / 100.0) * size.height;
      final barH = h.clamp(3.0, size.height);
      final top = midY - barH / 2;
      final centerX = x + barWidth / 2;
      final paint = Paint()
        ..color = centerX <= playedX ? playedColor : baseColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(centerX, top), Offset(centerX, top + barH), paint);
    }
    // Dot drawn last so it sits on top of the bars.
    _drawDot(canvas, size, midY);
  }

  void _drawDot(Canvas canvas, Size size, double midY) {
    final dotX = (size.width * progress).clamp(
      _dotRadius,
      size.width - _dotRadius,
    );
    canvas.drawCircle(
      Offset(dotX, midY),
      _dotRadius,
      Paint()..color = playedColor,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.levels != levels ||
      old.baseColor != baseColor ||
      old.playedColor != playedColor;
}
