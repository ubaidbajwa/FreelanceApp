import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/session_controller.dart';
import '../storage/secure_storage_service.dart';
import 'realtime_client.dart';
import 'signalr_realtime_client.dart';

// The client provider returns the abstract type — consumers never see SignalR types.
// Wired here (the single seam file) so signalr_realtime_client.dart is never
// imported outside core/realtime/.
final realtimeClientProvider = Provider<RealtimeClient>((ref) {
  final client = SignalRRealtimeClient(ref.read(secureStorageProvider));
  ref.onDispose(client.dispose);
  return client;
});

// Riverpod 3 Notifier (StateProvider use nahi karna — project rule).
// Tracks connection state, handles session teardown, exposes connectCount for F-M3b.
class RealtimeNotifier extends Notifier<RealtimeConnectionState> {
  StreamSubscription<RealtimeConnectionState>? _sub;

  // How many times the state has transitioned TO connected in this app session.
  // F-M3b reads this to decide whether to refetch on connection:
  //   connectCount == 1 → first connect → no gap
  //   connectCount  > 1 → reconnect    → gap possible, refetch needed
  int _connectCount = 0;
  int get connectCount => _connectCount;

  @override
  RealtimeConnectionState build() {
    _sub = ref.read(realtimeClientProvider).connectionState.listen((s) {
      if (s == RealtimeConnectionState.connected) _connectCount++;
      debugPrint('[Realtime] state → $s  (connectCount=$_connectCount)');
      state = s;
    });

    // Tear the hub down when the session expires (interceptor refresh failed).
    // SessionController does NOT import realtime — the wiring lives here.
    // Logout is handled separately: the drawer calls disconnect() directly
    // before clearing tokens and navigating.
    ref.listen(sessionControllerProvider, (_, next) {
      if (next == SessionStatus.expired) disconnect();
    });

    ref.onDispose(() => _sub?.cancel());
    return RealtimeConnectionState.disconnected;
  }

  Future<void> connect() => ref.read(realtimeClientProvider).connect();
  Future<void> disconnect() => ref.read(realtimeClientProvider).disconnect();
}

final realtimeNotifierProvider =
    NotifierProvider<RealtimeNotifier, RealtimeConnectionState>(
        RealtimeNotifier.new);
