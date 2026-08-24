// Manage invitations — Received / Sent tabs with infinite scroll.
// Single source of truth: invitationsProvider feeds both this screen and the
// home InvitesReceivedSection (F-N2). Actions from either surface stay in sync.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../../network/presentation/widgets/invite_card_skeleton.dart';
import '../../application/invitations_notifier.dart';
import '../../data/models/connection_models.dart';
import '../widgets/received_invite_card.dart';

class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({super.key});

  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final ScrollController _receivedScroll;
  late final ScrollController _sentScroll;

  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _scrollThreshold = 300.0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _receivedScroll = ScrollController()..addListener(_onReceivedScroll);
    _sentScroll = ScrollController()..addListener(_onSentScroll);
    // Refresh on open — provider auto-loaded on first watch (build() microtask),
    // but the data could be stale if opened after a long session on the home tab.
    Future.microtask(() => ref.read(invitationsProvider.notifier).load());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _receivedScroll.dispose();
    _sentScroll.dispose();
    super.dispose();
  }

  void _onReceivedScroll() {
    final pos = _receivedScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(invitationsProvider.notifier).loadMoreIncoming();
    }
  }

  void _onSentScroll() {
    final pos = _sentScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(invitationsProvider.notifier).loadMoreOutgoing();
    }
  }

  Future<void> _run(Future<String?> Function() action) async {
    final error = await action();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(invitationsProvider);
    final notifier = ref.read(invitationsProvider.notifier);

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        backgroundColor: _ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'Manage invitations',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _navy,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: _navy,
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          indicatorWeight: 2.5,
          labelColor: _navy,
          unselectedLabelColor: _navy.withValues(alpha: 0.4),
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [Tab(text: 'Received'), Tab(text: 'Sent')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildReceivedTab(state, notifier),
          _buildSentTab(state, notifier),
        ],
      ),
    );
  }

  // ── Received tab ──────────────────────────────────────────────────────────────

  Widget _buildReceivedTab(InvitationsState state, InvitationsNotifier notifier) {
    final tab = state.received;

    if (state.loading && tab.items.isEmpty) {
      return _loadingView();
    }

    if (tab.error != null && tab.items.isEmpty) {
      return _tabErrorView(
        error: tab.error!,
        onRetry: notifier.load,
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: notifier.load,
      child: CustomScrollView(
        controller: _receivedScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FilterPillRow(totalCount: tab.totalCount),
          ),
          if (tab.items.isEmpty)
            // Empty state IS shown on this dedicated management screen — the user
            // navigated here specifically, so "nothing here" is informative context.
            // (Contrast with InvitesReceivedSection on home, which hides when empty.)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.mail_outline_rounded,
                title: 'No invitations yet',
                message:
                    'When people invite you to connect,\nyou\'ll see them here.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i.isOdd) return const SizedBox(height: 8);
                    final idx = i ~/ 2;
                    final request = tab.items[idx];
                    return ReceivedInviteCard(
                      request: request,
                      busy: state.busyIds.contains(request.connectionId),
                      onAccept: () => _run(
                        () => notifier.accept(request.connectionId),
                      ),
                      onReject: () => _run(
                        () => notifier.reject(request.connectionId),
                      ),
                    );
                  },
                  childCount: tab.items.length * 2 - 1,
                ),
              ),
            ),
            if (tab.isLoadingMore) const SliverToBoxAdapter(child: _BottomSpinner()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }

  // ── Sent tab ──────────────────────────────────────────────────────────────────

  Widget _buildSentTab(InvitationsState state, InvitationsNotifier notifier) {
    final tab = state.sent;

    if (state.loading && tab.items.isEmpty) {
      return _loadingView();
    }

    if (tab.error != null && tab.items.isEmpty) {
      return _tabErrorView(
        error: tab.error!,
        onRetry: notifier.load,
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: notifier.load,
      child: CustomScrollView(
        controller: _sentScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _FilterPillRow(totalCount: tab.totalCount),
          ),
          if (tab.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyState(
                icon: Icons.send_outlined,
                title: 'No sent invitations',
                message: 'Invites you send will appear here.',
              ),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i.isOdd) return const SizedBox(height: 8);
                    final idx = i ~/ 2;
                    final request = tab.items[idx];
                    return _SentCard(
                      request: request,
                      busy: state.busyIds.contains(request.connectionId),
                      onWithdraw: () => _run(
                        () => notifier.withdraw(request.connectionId),
                      ),
                    );
                  },
                  childCount: tab.items.length * 2 - 1,
                ),
              ),
            ),
            if (tab.isLoadingMore) const SliverToBoxAdapter(child: _BottomSpinner()),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ],
      ),
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────────

  // Reuses InviteCardSkeleton (hand-rolled shimmer from F-N2) for both tabs.
  Widget _loadingView() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: 3,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => const InviteCardSkeleton(),
    );
  }

  // Per-tab error — one tab erroring must not blank the other tab's content.
  Widget _tabErrorView({required String error, required VoidCallback onRetry}) {
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
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: _navy.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                shape: const StadiumBorder(),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Filter pill row ────────────────────────────────────────────────────────────
// Horizontal scrollable row so additional filters can be added in future slices.
// Currently only "All · N" exists.

class _FilterPillRow extends StatelessWidget {
  const _FilterPillRow({required this.totalCount});
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ActivePill(label: 'All · $totalCount'),
          ],
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1633),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Sent card ─────────────────────────────────────────────────────────────────
// Outgoing request: avatar + name/headline + Withdraw pill.
// Mutual context is absent for outgoing items — omit rather than show "0 mutual".

class _SentCard extends StatelessWidget {
  const _SentCard({
    required this.request,
    required this.busy,
    required this.onWithdraw,
  });

  final PendingRequest request;
  final bool busy;
  final VoidCallback onWithdraw;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(
            fullName: request.user.name,
            photoUrl: request.user.profilePhotoUrl,
            radius: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  request.user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _navy,
                  ),
                ),
                if (request.user.headline != null &&
                    request.user.headline!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    request.user.headline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Withdraw button or busy spinner
          if (busy)
            const SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                ),
              ),
            )
          else
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onWithdraw,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Withdraw',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

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

// ── Bottom paging spinner ──────────────────────────────────────────────────────

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
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFC0A062),
          ),
        ),
      ),
    );
  }
}
