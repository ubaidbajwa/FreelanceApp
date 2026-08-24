// Messages tab — App Shell ke andar mount hota hai (shell khud AppBar + bottom
// nav deta hai, is liye yahan apna Scaffold/AppBar NAHI). Do segments:
// Messages (accepted) + Requests (pending incoming, badge jab > 0). Segmented
// control InvitationsScreen wala hi TabBar/TabBarView hai — naya control nahi.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/number_format.dart';
import '../../application/conversation_requests_notifier.dart';
import '../../application/conversations_notifier.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';
import '../widgets/conversation_tile.dart';
import '../widgets/request_tile.dart';

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen>
    with TickerProviderStateMixin {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _scrollThreshold = 300.0;

  late final TabController _tabCtrl;
  late final ScrollController _messagesScroll;
  late final ScrollController _requestsScroll;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _messagesScroll = ScrollController()..addListener(_onMessagesScroll);
    _requestsScroll = ScrollController()..addListener(_onRequestsScroll);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _messagesScroll.dispose();
    _requestsScroll.dispose();
    super.dispose();
  }

  void _onMessagesScroll() {
    final pos = _messagesScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(conversationsProvider.notifier).loadMore();
    }
  }

  void _onRequestsScroll() {
    final pos = _requestsScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(conversationRequestsProvider.notifier).loadMore();
    }
  }

  // Accept/decline — pessimistic; fail pe SnackBar, row waisa hi rehta hai.
  Future<void> _runAction(Future<String?> Function() action) async {
    final error = await action();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Badge ke liye pendingCount watch — badalne pe tab label rebuild ho.
    final pendingCount =
        ref.watch(conversationRequestsProvider.select((s) => s.pendingCount));

    return Container(
      color: _ivory,
      child: Column(
        children: [
          _header(pendingCount),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _MessagesTabView(
                  scrollController: _messagesScroll,
                  onOpen: _openChat,
                ),
                _RequestsTabView(
                  scrollController: _requestsScroll,
                  onAccept: (id) => _runAction(
                    () => ref
                        .read(conversationRequestsProvider.notifier)
                        .accept(id),
                  ),
                  onDecline: (id) => _runAction(
                    () => ref
                        .read(conversationRequestsProvider.notifier)
                        .decline(id),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tap → chat route push (shell ke UPAR, is liye tab state unwind nahi hoti).
  // Poori summary `extra` mein — chat screen isse status/isRequest/otherUser
  // dono nikaalti hai (F-M2). (Koi single-conversation GET endpoint nahi, is liye
  // state ka wahid reliable source yahi nav-time summary hai.)
  void _openChat(ConversationSummary summary) {
    context.push('/chat/${summary.id}', extra: summary);
  }

  Widget _header(int pendingCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
          child: Text(
            MessagingStrings.overline,
            textAlign: TextAlign.start,
            style: TextStyle(
              color: _gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 3.5,
            ),
          ),
        ),
        TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          indicatorWeight: 2.5,
          labelColor: _navy,
          unselectedLabelColor: _navy.withValues(alpha: 0.4),
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          tabs: [
            const Tab(text: MessagingStrings.tabMessages),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(MessagingStrings.tabRequests),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: pendingCount),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Messages (accepted) tab ─────────────────────────────────────────────────────

class _MessagesTabView extends ConsumerWidget {
  const _MessagesTabView({
    required this.scrollController,
    required this.onOpen,
  });

  final ScrollController scrollController;
  final void Function(ConversationSummary) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationsProvider);
    final notifier = ref.read(conversationsProvider.notifier);

    if (state.isLoading && state.items.isEmpty) {
      return const _LoadingView();
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(message: state.error!, onRetry: notifier.refresh);
    }

    return RefreshIndicator(
      color: const Color(0xFFC0A062),
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.forum_outlined,
                title: MessagingStrings.emptyConversationsTitle,
                message: MessagingStrings.emptyConversationsBody,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i.isOdd) return const SizedBox(height: 8);
                    final summary = state.items[i ~/ 2];
                    return ConversationTile(
                      summary: summary,
                      onTap: () => onOpen(summary),
                    );
                  },
                  childCount: state.items.length * 2 - 1,
                ),
              ),
            ),
            if (state.isLoadingMore)
              const SliverToBoxAdapter(child: _BottomSpinner()),
            if (state.loadMoreFailed)
              SliverToBoxAdapter(
                child: _LoadMoreError(onRetry: notifier.loadMore),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }
}

// ── Requests (pending) tab ──────────────────────────────────────────────────────

class _RequestsTabView extends ConsumerWidget {
  const _RequestsTabView({
    required this.scrollController,
    required this.onAccept,
    required this.onDecline,
  });

  final ScrollController scrollController;
  final void Function(String id) onAccept;
  final void Function(String id) onDecline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationRequestsProvider);
    final notifier = ref.read(conversationRequestsProvider.notifier);

    if (state.isLoading && state.items.isEmpty) {
      return const _LoadingView();
    }
    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(message: state.error!, onRetry: notifier.refresh);
    }

    return RefreshIndicator(
      color: const Color(0xFFC0A062),
      onRefresh: notifier.refresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (state.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.mark_email_unread_outlined,
                title: MessagingStrings.emptyRequestsTitle,
                message: MessagingStrings.emptyRequestsBody,
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i.isOdd) return const SizedBox(height: 8);
                    final summary = state.items[i ~/ 2];
                    return RequestTile(
                      summary: summary,
                      busy: state.busyIds.contains(summary.id),
                      onAccept: () => onAccept(summary.id),
                      onDecline: () => onDecline(summary.id),
                    );
                  },
                  childCount: state.items.length * 2 - 1,
                ),
              ),
            ),
            if (state.isLoadingMore)
              const SliverToBoxAdapter(child: _BottomSpinner()),
            if (state.loadMoreFailed)
              SliverToBoxAdapter(
                child: _LoadMoreError(onRetry: notifier.loadMore),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }
}

// ── Shared bits ─────────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        formatCount(count),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _gold,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC0A062)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: _navy.withValues(alpha: 0.15)),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: _navy.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// First-load failure — full-screen error + retry.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: _navy.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                shape: const StadiumBorder(),
              ),
              child: const Text(MessagingStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}

// Load-more failure — inline retry at list bottom; existing items preserved.
class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            MessagingStrings.loadMoreFailed,
            style: TextStyle(fontSize: 13, color: _navy.withValues(alpha: 0.55)),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: BorderSide(color: _navy.withValues(alpha: 0.35)),
              shape: const StadiumBorder(),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              MessagingStrings.retry,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomSpinner extends StatelessWidget {
  const _BottomSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC0A062)),
        ),
      ),
    );
  }
}
