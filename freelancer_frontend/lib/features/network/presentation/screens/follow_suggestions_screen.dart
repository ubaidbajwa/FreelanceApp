import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/follow_suggestions_notifier.dart';
import '../widgets/follow_suggestion_card.dart';
import '../widgets/follow_suggestion_card_skeleton.dart';

class FollowSuggestionsScreen extends ConsumerStatefulWidget {
  const FollowSuggestionsScreen({super.key});

  @override
  ConsumerState<FollowSuggestionsScreen> createState() =>
      _FollowSuggestionsScreenState();
}

class _FollowSuggestionsScreenState
    extends ConsumerState<FollowSuggestionsScreen> {
  late final ScrollController _scrollCtrl;

  static const _navy = Color(0xFF0A1633);
  // Trigger loadMore when within 300px of the bottom — same threshold as SuggestionsScreen
  static const _scrollThreshold = 300.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      ref.read(followSuggestionsProvider.notifier).loadMore();
    }
  }

  Future<void> _follow(String userId) async {
    final error =
        await ref.read(followSuggestionsProvider.notifier).follow(userId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _unfollow(String userId) async {
    final error =
        await ref.read(followSuggestionsProvider.notifier).unfollow(userId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _dismiss(String userId, String fullName) async {
    final error =
        await ref.read(followSuggestionsProvider.notifier).dismiss(userId);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('$fullName dismissed'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undoError = await ref
                .read(followSuggestionsProvider.notifier)
                .undoDismiss(userId);
            if (undoError != null) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(undoError),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(followSuggestionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF8),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'Popular on Skillora',
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
      ),
      body: RefreshIndicator(
        color: _navy,
        // Pull-to-refresh resets to page 1 via _loadFirst (stale-page guard fires)
        onRefresh: () =>
            ref.read(followSuggestionsProvider.notifier).refresh(),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(FollowSuggestionsState state) {
    // Initial loading — skeleton list before any items arrive
    if (state.loading && state.items.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, _) => const FollowSuggestionCardSkeleton(),
      );
    }

    // Error with empty list — full-screen error, still scrollable for pull-to-refresh
    if (state.error != null && state.items.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 48,
                        color: _navy.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text(
                      state.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: _navy.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () =>
                          ref.read(followSuggestionsProvider.notifier).refresh(),
                      child: const Text(
                        'Try again',
                        style: TextStyle(color: _navy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Empty after successful fetch — unlikely (cold-start returns global popular users),
    // but handled cleanly so the screen is never stuck in an unrecoverable blank state.
    if (state.items.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 48, color: _navy.withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text(
                      'No suggestions right now.\nCheck back later.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: _navy.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Normal list — vertical SliverList + bottom spinner while paging
    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                if (i.isOdd) return const SizedBox(height: 8);
                final idx = i ~/ 2;
                final s = state.items[idx];
                return FollowSuggestionCard(
                  suggestion: s,
                  isFollowing: state.followedIds.contains(s.userId),
                  isBusy: state.busyIds.contains(s.userId),
                  onFollow: () => _follow(s.userId),
                  onUnfollow: () => _unfollow(s.userId),
                  onDismiss: () => _dismiss(s.userId, s.fullName),
                );
              },
              // Each item is card + spacer, except the last card has no trailing spacer
              childCount: state.items.length * 2 - 1,
            ),
          ),
        ),
        // loadMore spinner — appears below list while next page fetches
        if (state.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
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
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
