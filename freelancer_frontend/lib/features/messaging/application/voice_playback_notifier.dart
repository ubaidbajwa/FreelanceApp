// F-M11 — voice PLAYBACK (Riverpod Notifier, no StateProvider).
//
// A SINGLE just_audio player lives here, not per-bubble. That is what makes
// "starting one stops any other" trivial: switching the URL on one shared player
// inherently stops whatever was playing. Per-bubble controllers would force bubbles
// to know about each other. The player is disposed when the chat provider is
// disposed (leaving the chat), and stopped when the app is backgrounded.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

class VoicePlaybackState {
  // The message id currently loaded into the shared player (null = nothing loaded).
  final String? activeId;
  final Duration position;
  final Duration duration;
  final bool playing;

  const VoicePlaybackState({
    this.activeId,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
  });

  // Progress 0..1 for the active bubble; 0 for any other bubble.
  double progressFor(String messageId) {
    if (messageId != activeId || duration.inMilliseconds <= 0) return 0;
    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  bool isActive(String messageId) => messageId == activeId;
  bool isPlaying(String messageId) => messageId == activeId && playing;

  VoicePlaybackState copyWith({
    String? activeId,
    Duration? position,
    Duration? duration,
    bool? playing,
  }) =>
      VoicePlaybackState(
        activeId: activeId ?? this.activeId,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
      );
}

class VoicePlaybackNotifier extends Notifier<VoicePlaybackState> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  VoicePlaybackState build() {
    _posSub = _player.positionStream.listen((pos) {
      if (state.activeId != null) state = state.copyWith(position: pos);
    });
    _stateSub = _player.playerStateStream.listen((ps) {
      if (state.activeId == null) return;
      // On natural completion, reset to the start and stop — the bubble shows total.
      if (ps.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        state = state.copyWith(playing: false, position: Duration.zero);
      } else {
        state = state.copyWith(playing: ps.playing);
      }
    });
    ref.onDispose(() {
      _posSub?.cancel();
      _stateSub?.cancel();
      _player.dispose(); // never leak — audio would keep playing after leaving
    });
    return const VoicePlaybackState();
  }

  // Play/pause this note. Loading a DIFFERENT note replaces the source on the shared
  // player, which stops the previous one — only one ever plays.
  Future<void> toggle(String messageId, String url) async {
    if (state.activeId == messageId) {
      if (state.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }
    // Different note → switch the source (stops the current), then play.
    state = const VoicePlaybackState(); // reset while (re)loading
    try {
      final dur = await _player.setUrl(url);
      state = VoicePlaybackState(
        activeId: messageId,
        duration: dur ?? Duration.zero,
        position: Duration.zero,
        playing: false,
      );
      await _player.play();
    } catch (_) {
      state = const VoicePlaybackState();
    }
  }

  // Tap-to-seek on the waveform: fraction 0..1 of the loaded note.
  Future<void> seekFraction(String messageId, double fraction) async {
    if (state.activeId != messageId) return;
    final ms = (state.duration.inMilliseconds * fraction.clamp(0.0, 1.0)).round();
    await _player.seek(Duration(milliseconds: ms));
  }

  // Stop playback when the app is backgrounded.
  Future<void> stopForBackground() async {
    if (state.playing) {
      await _player.pause();
      state = state.copyWith(playing: false);
    }
  }
}

final voicePlaybackProvider =
    NotifierProvider.autoDispose<VoicePlaybackNotifier, VoicePlaybackState>(
        VoicePlaybackNotifier.new);
