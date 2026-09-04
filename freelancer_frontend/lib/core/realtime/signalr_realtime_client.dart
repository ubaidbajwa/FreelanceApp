// ⚠️ THIS IS THE ONLY FILE THAT MAY IMPORT signalr_netcore.
// All other files depend on RealtimeClient (abstract). Verify with:
//   grep -r "signalr_netcore" lib/ --include="*.dart" -l
// Exactly one file should be listed.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../constants/api_constants.dart';
import '../storage/secure_storage_service.dart';
import 'realtime_client.dart';

class SignalRRealtimeClient implements RealtimeClient {
  final SecureStorageService _storage;

  SignalRRealtimeClient(this._storage) {
    if (kDebugMode) {
      // signalr_netcore uses package:logging. Enable INFO so transport selection
      // ("Selecting transport: WebSockets") is visible in the console.
      // Level.ALL would flood the console; INFO is enough to diagnose negotiation.
      hierarchicalLoggingEnabled = true;
      _logger = Logger('SignalR')..level = Level.INFO;
      _logSub = _logger!.onRecord.listen(
        (r) => debugPrint('[SignalR][${r.level.name}] ${r.message}'),
      );
    }
  }

  static final String _hubUrl = '${ApiConstants.baseUrl}/hubs/chat';

  Logger? _logger;
  StreamSubscription<LogRecord>? _logSub;

  final _stateController =
      StreamController<RealtimeConnectionState>.broadcast();
  final _eventController = StreamController<RealtimeEvent>.broadcast();

  HubConnection? _hub;
  bool _stopping = false; // true while disconnect() is running — suppresses onclose

  @override
  Stream<RealtimeConnectionState> get connectionState =>
      _stateController.stream;

  @override
  Stream<RealtimeEvent> get events => _eventController.stream;

  @override
  Future<void> connect() async {
    if (_hub != null) return; // already connected or connecting

    _emit(RealtimeConnectionState.connecting);

    final hub = _buildHub();
    _hub = hub;

    try {
      await hub.start();
      _emit(RealtimeConnectionState.connected);
    } catch (e) {
      debugPrint('[Realtime] connect failed: $e');
      _hub = null;
      _emit(RealtimeConnectionState.failed);
    }
  }

  @override
  Future<void> disconnect() async {
    final h = _hub;
    if (h == null) return;
    _stopping = true;
    _hub = null;
    _emit(RealtimeConnectionState.disconnected);
    try {
      await h.stop();
    } catch (_) {
      // best-effort — socket may already be gone
    } finally {
      _stopping = false;
    }
  }

  @override
  void dispose() {
    disconnect(); // fire-and-forget — acceptable at app shutdown
    _stateController.close();
    _eventController.close();
    _logSub?.cancel();
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  HubConnection _buildHub() {
    final hub = HubConnectionBuilder()
        .withUrl(
          _hubUrl,
          options: HttpConnectionOptions(
            // accessTokenFactory is invoked by the library on EVERY connect and
            // reconnect attempt. It reads from storage on each call so that after
            // AuthInterceptor rotates the access token, SignalR reconnects with
            // the fresh value. Capturing the token once at construction would cause
            // every reconnect to retry with a dead token — permanent failure that
            // looks like a network problem.
            accessTokenFactory: () async =>
                await _storage.getAccessToken() ?? '',
            logger: _logger,
          ),
        )
        .withAutomaticReconnect()
        .build();

    hub.onclose(({error}) => _onClosed(error));
    hub.onreconnecting(({error}) {
      debugPrint('[Realtime] reconnecting: $error');
      _emit(RealtimeConnectionState.reconnecting);
    });
    hub.onreconnected(({connectionId}) {
      debugPrint('[Realtime] reconnected: connectionId=$connectionId');
      _emit(RealtimeConnectionState.connected);
    });

    // Register all business events so they feed the broadcast stream.
    // Consumers filter by name via .where((e) => e.name == 'EventName').
    for (final event in const [
      'MessageReceived',
      'ConversationRequestReceived',
      'ConversationAccepted',
      // M2 message actions — must be registered so the server's SendAsync finds
      // a bound handler; consumers (ChatNotifier) filter by name off the stream.
      'MessageDeleted',
      'MessagePinChanged',
      'MessageEdited',
      'ReactionChanged',
      // M4 — read receipts: fires to the OTHER participant with the new watermark.
      'ConversationRead',
    ]) {
      hub.on(event, _makeInvocationFunc(event));
    }

    return hub;
  }

  void _onClosed(Object? error) {
    if (_stopping) return; // disconnect() already emitted the state
    debugPrint('[Realtime] onclose: ${error ?? "(clean)"}');
    _hub = null;
    // onclose fires when withAutomaticReconnect gives up (error != null) or after
    // stop(). AppLifecycleListener drives reconnection on resume.
    _emit(error != null
        ? RealtimeConnectionState.failed
        : RealtimeConnectionState.disconnected);
  }

  // Wraps each hub event in a MethodInvocationFunc, logs raw args, and feeds
  // the broadcast stream. Logging answers payload-casing questions at runtime.
  MethodInvocationFunc _makeInvocationFunc(String event) {
    return (List<Object?>? args) {
      debugPrint('[Realtime] ★ event=$event  raw=$args');
      _emitEvent(RealtimeEvent(event, _extractPayload(event, args)));
    };
  }

  // Server calls SendAsync("EventName", dto) → args == [dto].
  // Most events: dto is a JSON-deserialized Map.
  // ConversationAccepted: dto is a bare Guid string — wrap for uniform consumers.
  Map<String, dynamic> _extractPayload(String event, List<Object?>? args) {
    if (args == null || args.isEmpty) return const {};
    final first = args.first;
    if (event == 'ConversationAccepted') {
      // Server sends a bare Guid string, not an object.
      return first is String ? {'conversationId': first} : const {};
    }
    if (first is Map) return first.cast<String, dynamic>();
    return const {};
  }

  void _emit(RealtimeConnectionState s) {
    if (!_stateController.isClosed) _stateController.add(s);
  }

  void _emitEvent(RealtimeEvent e) {
    if (!_eventController.isClosed) _eventController.add(e);
  }
}
