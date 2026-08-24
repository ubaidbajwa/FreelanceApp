import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/suggestions_notifier.dart';
import '../widgets/suggestion_card.dart';
import '../widgets/suggestion_card_skeleton.dart';

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  late final ScrollController _scrollCtrl;

  static const _navy = Color(0xFF0A1633);
  // Trigger loadMore when within 300px of the bottom — matches PeopleScreen threshold
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
      ref.read(suggestionsProvider.notifier).loadMore();
    }
  }

  Future<void> _connect(String userId) async {
    final error =
        await ref.read(suggestionsProvider.notifier).connect(userId);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  Future<void> _dismiss(String userId, String fullName) async {
    final error =
        await ref.read(suggestionsProvider.notifier).dismiss(userId);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
        ),
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
            final undoError =
                await ref.read(suggestionsProvider.notifier).undoDismiss(userId);
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
    final state = ref.watch(suggestionsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF8),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _navy,
        title: const Text(
          'People you may know',
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
        onRefresh: () => ref.read(suggestionsProvider.notifier).refresh(),
        child: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(SuggestionsState state) {
    // Initial loading — skeleton grid before any items arrive
    if (state.loading && state.items.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.55,
        ),
        itemCount: 4,
        itemBuilder: (_, _) => const SuggestionCardSkeleton(),
      );
    }

    // Error with empty list — full-screen error state
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
                        color: const Color(0xFF0A1633).withValues(alpha: 0.2)),
                    const SizedBox(height: 16),
                    Text(
                      state.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF0A1633).withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () =>
                          ref.read(suggestionsProvider.notifier).refresh(),
                      child: const Text(
                        'Try again',
                        style: TextStyle(color: Color(0xFF0A1633)),
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

    // Empty list after successful fetch
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
                        size: 48,
                        color: _navy.withValues(alpha: 0.2)),
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

    // Normal list — CustomScrollView with SliverGrid + loadMore spinner sliver
    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.55,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final s = state.items[i];
                return SuggestionCard(
                  suggestion: s,
                  isRequested: state.requestedIds.contains(s.userId),
                  isBusy: state.busyIds.contains(s.userId),
                  onConnect: () => _connect(s.userId),
                  onDismiss: () => _dismiss(s.userId, s.fullName),
                );
              },
              childCount: state.items.length,
            ),
          ),
        ),
        // loadMore spinner — appears below the grid while the next page fetches
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
