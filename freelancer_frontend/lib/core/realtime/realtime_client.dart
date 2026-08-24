// Abstract seam for real-time transport. Nothing outside this folder may import
// signalr_netcore — if the library is swapped, only signalr_realtime_client.dart
// changes. This mirrors the backend pattern: Application depends on IChatNotifier;
// only the Api layer touches SignalR. Same reasoning, opposite side of the wire.

enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  failed,
}

// A single hub event as it crosses the seam — name + decoded JSON payload.
// ConversationAccepted is a bare Guid on the wire; the adapter wraps it as
// {'conversationId': id} so all consumers get a uniform Map<String, dynamic>.
class RealtimeEvent {
  final String name;
  final Map<String, dynamic> payload;
  const RealtimeEvent(this.name, this.payload);
}

abstract class RealtimeClient {
  // Emits every time the connection state changes. Broadcast stream — multiple
  // listeners allowed (notifier + F-M3b consumers).
  Stream<RealtimeConnectionState> get connectionState;

  // Broadcast stream of all hub events. Filter by name: .where((e) => e.name == 'X').
  // Cancel the StreamSubscription on dispose — a leaked subscription on a broadcast
  // stream means a disposed notifier keeps receiving events and will throw.
  Stream<RealtimeEvent> get events;

  Future<void> connect();
  Future<void> disconnect();

  // Release resources (StreamControllers, logging subscriptions, etc.).
  // Called by realtimeClientProvider via ref.onDispose().
  void dispose();
}
