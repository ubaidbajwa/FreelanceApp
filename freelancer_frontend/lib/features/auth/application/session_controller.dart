import 'package:flutter_riverpod/flutter_riverpod.dart';

// App-wide session signal. Ye token store NAHI hai (wo SecureStorage hai) — ye
// reactive flag hai: "kya hum signed out ho gaye, aur kyun". Interceptor jab
// refresh fail pe session khatam karta hai to `expire()` call karta hai; login
// screen us par session-expired message dikhati hai, phir `acknowledge()`.
//
// Riverpod 3 Notifier — project rule: StateProvider use NAHI karna.
enum SessionStatus { active, expired }

class SessionController extends Notifier<SessionStatus> {
  @override
  SessionStatus build() => SessionStatus.active;

  // Refresh fail / koi refresh token nahi — session over.
  void expire() => state = SessionStatus.expired;

  // Login screen message dikhane ke baad call karti hai (dobara na dikhe).
  void acknowledge() => state = SessionStatus.active;
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionStatus>(SessionController.new);
