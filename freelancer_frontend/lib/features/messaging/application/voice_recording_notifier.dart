// F-M11 — voice RECORDING lifecycle (Riverpod Notifier, no StateProvider).
//
// Owns the recorder, the pause-correct timer, the amplitude samples, the 300 s
// auto-stop, and clean handling of interruptions (another app taking the mic) and
// backgrounding. The UI (voice_recorder_bar.dart) only maps gestures to these
// methods; all timing/lifecycle correctness lives here so it is one place.
//
// Elapsed time counts ONLY recorded audio: a paused note must not keep ticking, or
// the client duration will disagree with what the server measures.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../messaging_strings.dart';
import 'message_actions.dart';

// idle → holding (finger down, unlocked) → locked (hands-free) ⇄ paused.
enum VoiceRecordPhase { idle, holding, locked, paused }

// A finished recording ready to send.
class VoiceResult {
  final String path;
  final int durationMs;
  final String? waveform; // null when no amplitude was available (flat bar)
  const VoiceResult({
    required this.path,
    required this.durationMs,
    this.waveform,
  });
}

class VoiceRecordingState {
  final VoiceRecordPhase phase;
  final int elapsedMs; // recorded audio only (excludes paused time)
  final int level; // latest amplitude 0–100 (subtle live indicator)
  // One-shot signals the screen consumes then clears:
  final VoiceResult? completed; // ready to send (manual send OR 300 s auto-stop)
  final String? error; // e.g. mic taken by another app
  final bool tooShort; // released under 1 s — show the "hold to record" hint

  const VoiceRecordingState({
    this.phase = VoiceRecordPhase.idle,
    this.elapsedMs = 0,
    this.level = 0,
    this.completed,
    this.error,
    this.tooShort = false,
  });

  bool get isActive =>
      phase == VoiceRecordPhase.holding ||
      phase == VoiceRecordPhase.locked ||
      phase == VoiceRecordPhase.paused;
  bool get isPaused => phase == VoiceRecordPhase.paused;
  bool get isLocked =>
      phase == VoiceRecordPhase.locked || phase == VoiceRecordPhase.paused;

  VoiceRecordingState copyWith({
    VoiceRecordPhase? phase,
    int? elapsedMs,
    int? level,
    VoiceResult? completed,
    bool clearCompleted = false,
    String? error,
    bool clearError = false,
    bool? tooShort,
  }) =>
      VoiceRecordingState(
        phase: phase ?? this.phase,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        level: level ?? this.level,
        completed: clearCompleted ? null : (completed ?? this.completed),
        error: clearError ? null : (error ?? this.error),
        tooShort: tooShort ?? this.tooShort,
      );
}

class VoiceRecordingNotifier extends Notifier<VoiceRecordingState> {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _ampSub;
  StreamSubscription<RecordState>? _stateSub;
  Timer? _ticker;

  final List<int> _samples = [];
  String? _path;
  int _accumulatedMs = 0; // completed (pre-pause) segments
  DateTime? _segmentStart; // start of the current running segment
  bool _stopping = false; // guards the onStateChanged interruption handler

  @override
  VoiceRecordingState build() {
    ref.onDispose(_teardown);
    return const VoiceRecordingState();
  }

  void _log(String m) {
    if (kDebugMode) debugPrint('[Voice] $m');
  }

  // ── Public API (driven by the recorder bar) ─────────────────────────────────

  // Returns false if microphone permission is denied — the screen then shows the
  // permission dialog. On success, recording starts and phase becomes `holding`.
  Future<bool> start() async {
    if (state.isActive) return true;
    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    _path = path;
    _samples.clear();
    _accumulatedMs = 0;
    _stopping = false;

    // aacLc → .m4a (audio/mp4): the most broadly supported accepted type.
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    // Start the clock AFTER the recorder is actually capturing, so the elapsed time
    // excludes start latency and stays in step with the file the server measures.
    _segmentStart = DateTime.now();

    _ampSub = _recorder
        .onAmplitudeChanged(VoiceLimits.sampleInterval)
        .listen(_onAmplitude);
    // If the OS/another app stops the recorder out from under us, react cleanly.
    _stateSub = _recorder.onStateChanged().listen(_onRecorderState);

    _startTicker();
    state = const VoiceRecordingState(phase: VoiceRecordPhase.holding);
    return true;
  }

  // Hands-free: keep recording after the finger lifts.
  void lock() {
    if (state.phase == VoiceRecordPhase.holding) {
      state = state.copyWith(phase: VoiceRecordPhase.locked);
    }
  }

  Future<void> pause() async {
    if (state.phase != VoiceRecordPhase.locked) return;
    _accumulateSegment();
    await _recorder.pause();
    state = state.copyWith(phase: VoiceRecordPhase.paused);
  }

  Future<void> resume() async {
    if (state.phase != VoiceRecordPhase.paused) return;
    _segmentStart = DateTime.now();
    await _recorder.resume();
    state = state.copyWith(phase: VoiceRecordPhase.locked);
  }

  // Finish and hand the result to the screen (manual release / send button). A note
  // shorter than the minimum is treated as an accidental tap: discarded with a hint.
  Future<void> finish() async {
    if (!state.isActive) return;
    final elapsed = _currentElapsedMs();
    if (elapsed < VoiceLimits.minDurationMs) {
      await _discard();
      state = const VoiceRecordingState(tooShort: true);
      return;
    }
    final path = await _stop();
    if (path == null) {
      state = const VoiceRecordingState();
      return;
    }
    final waveform = downsampleWaveform(_samples);
    state = VoiceRecordingState(
      phase: VoiceRecordPhase.idle,
      completed: VoiceResult(
        path: path,
        durationMs: elapsed,
        // Empty string (no amplitude available) → null: server + bubble treat null
        // as "flat bar". Never fabricate values.
        waveform: waveform.isEmpty ? null : waveform,
      ),
    );
  }

  // Cancel: discard AND delete the local file (a leftover file is a slow leak).
  Future<void> cancel() async {
    await _discard();
    state = const VoiceRecordingState();
  }

  // App backgrounded mid-recording: STOP capturing (pause) and keep what we have —
  // never record in the background. A locked note stays as a paused panel the user
  // can send or delete on return; an unlocked hold is promoted to locked+paused so
  // it isn't lost when the finger/app leaves.
  Future<void> onAppBackgrounded() async {
    if (state.phase == VoiceRecordPhase.holding ||
        state.phase == VoiceRecordPhase.locked) {
      _accumulateSegment();
      _stopTicker();
      try {
        await _recorder.pause();
      } catch (_) {}
      state = state.copyWith(phase: VoiceRecordPhase.paused);
    }
  }

  // Screen consumes the one-shot signals then clears them.
  void consumeCompleted() {
    if (state.completed != null) state = state.copyWith(clearCompleted: true);
  }

  void consumeError() {
    if (state.error != null) {
      state = const VoiceRecordingState(); // fully reset after an interruption
    }
  }

  void consumeTooShort() {
    if (state.tooShort) state = state.copyWith(tooShort: false);
  }

  // ── Internals ────────────────────────────────────────────────────────────────

  void _onAmplitude(Amplitude amp) {
    // Only sample while actively capturing — a paused recording contributes none.
    if (state.phase == VoiceRecordPhase.holding ||
        state.phase == VoiceRecordPhase.locked) {
      final level = amplitudeToLevel(amp.current);
      _samples.add(level);
      state = state.copyWith(level: level);
    }
  }

  // An unsolicited stop (state → stop while we're mid-recording and didn't ask) means
  // another app / a call took the microphone. Surface it cleanly, never crash.
  void _onRecorderState(RecordState rs) {
    if (rs == RecordState.stop && !_stopping && state.isActive) {
      _log('recorder stopped externally — mic taken');
      _teardownStreamsAndTimer();
      _deleteFile();
      state = const VoiceRecordingState(error: MessagingStrings.voiceMicBusy);
    }
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final elapsed = _currentElapsedMs();
      // Reached the server's 300 s cap → auto-stop into the send-ready state rather
      // than silently exceeding it and being rejected after upload.
      if (elapsed >= VoiceLimits.maxDurationMs) {
        _autoStopAtLimit();
        return;
      }
      state = state.copyWith(elapsedMs: elapsed);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> _autoStopAtLimit() async {
    _stopTicker();
    final path = await _stop();
    if (path == null) {
      state = const VoiceRecordingState();
      return;
    }
    final waveform = downsampleWaveform(_samples);
    state = VoiceRecordingState(
      phase: VoiceRecordPhase.idle,
      elapsedMs: VoiceLimits.maxDurationMs,
      completed: VoiceResult(
        path: path,
        durationMs: VoiceLimits.maxDurationMs,
        waveform: waveform.isEmpty ? null : waveform,
      ),
    );
  }

  // Elapsed = completed segments + the currently running segment (if any).
  int _currentElapsedMs() {
    var total = _accumulatedMs;
    final seg = _segmentStart;
    if (seg != null &&
        (state.phase == VoiceRecordPhase.holding ||
            state.phase == VoiceRecordPhase.locked)) {
      total += DateTime.now().difference(seg).inMilliseconds;
    }
    return total;
  }

  // Fold the running segment into the accumulated total and stop the running clock.
  void _accumulateSegment() {
    final seg = _segmentStart;
    if (seg != null) {
      _accumulatedMs += DateTime.now().difference(seg).inMilliseconds;
      _segmentStart = null;
    }
  }

  // Stop the recorder and return the finished file path (null on failure).
  Future<String?> _stop() async {
    _stopping = true;
    _teardownStreamsAndTimer();
    try {
      final path = await _recorder.stop();
      return path ?? _path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _discard() async {
    _stopping = true;
    _teardownStreamsAndTimer();
    try {
      await _recorder.cancel(); // stops + discards the platform file
    } catch (_) {}
    _deleteFile();
  }

  void _deleteFile() {
    final p = _path;
    if (p == null) return;
    _path = null;
    // Best-effort — a failure here just leaves a temp file, never crashes.
    unawaited(File(p).delete().catchError((_) => File(p)));
  }

  void _teardownStreamsAndTimer() {
    _ampSub?.cancel();
    _ampSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _stopTicker();
  }

  void _teardown() {
    _teardownStreamsAndTimer();
    // Fire-and-forget: never leave the platform recorder running after dispose.
    unawaited(_recorder.dispose());
  }
}

final voiceRecordingProvider = NotifierProvider.autoDispose<
    VoiceRecordingNotifier, VoiceRecordingState>(VoiceRecordingNotifier.new);
