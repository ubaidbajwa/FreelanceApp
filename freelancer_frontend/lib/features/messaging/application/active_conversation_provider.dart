import 'package:flutter_riverpod/flutter_riverpod.dart';

// Tracks the id of the conversation currently open in the chat screen.
// Set by ChatNotifier.open(); cleared when chatProvider is disposed (autoDispose).
// ConversationsNotifier reads this to avoid incrementing unread count while the
// user is already looking at that conversation.
class ActiveConversationNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void setActive(String? id) => state = id;

  // Deferred-safe clear — called from ChatScreen.dispose via a post-frame
  // callback. Ownership is re-checked HERE, at run time, not at dispose time:
  // if a newer chat wrote its id between the dispose and the callback, that
  // id is not ours to clear. ref.mounted guards container teardown (tests /
  // app shutdown), where the deferred callback may outlive the provider.
  void clearIfActive(String id) {
    if (!ref.mounted) return;
    if (state == id) state = null;
  }
}

final activeConversationProvider =
    NotifierProvider<ActiveConversationNotifier, String?>(
        ActiveConversationNotifier.new);
