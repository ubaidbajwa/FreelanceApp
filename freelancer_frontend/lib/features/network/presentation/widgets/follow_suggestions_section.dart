// PROVIDER STRATEGY (shared): home section and FollowSuggestionsScreen use ONE
// followSuggestionsProvider. The home section shows items.take(3); the full screen
// appends pages via loadMore(). No paging conflict: _loadFirst fires once on provider
// creation (when this section mounts). The full screen reuses the already-loaded list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/follow_suggestions_notifier.dart';
import 'follow_suggestion_card.dart';
import 'follow_suggestion_card_skeleton.dart';

class FollowSuggestionsSection extends ConsumerStatefulWidget {
  const FollowSuggestionsSection({super.key});

  @override
  ConsumerState<FollowSuggestionsSection> createState() =>
      _FollowSuggestionsSectionState();
}

class _FollowSuggestionsSectionState
    extends ConsumerState<FollowSuggestionsSection> {
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

    // Loading — 2 card skeletons while first page fetches
    if (state.loading && state.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(showArrow: false),
          const SizedBox(height: 12),
          const FollowSuggestionCardSkeleton(),
          const SizedBox(height: 8),
          const FollowSuggestionCardSkeleton(),
        ],
      );
    }

    // Error — inline card so it doesn't blank sibling sections
    if (state.error != null && state.items.isEmpty) {
      return _ErrorCard(
        onRetry: () =>
            ref.read(followSuggestionsProvider.notifier).refresh(),
      );
    }

    // Empty — cold-start returns popular users, so this is rare. Render nothing
    // rather than an empty header, so the home screen layout stays clean.
    if (state.items.isEmpty) return const SizedBox.shrink();

    // Show at most 3 cards. This Column is inside MyNetworkHomeScreen's
    // SingleChildScrollView — no nested scrollable on the same axis allowed.
    final preview = state.items.take(3).toList();
    final hasMore = state.items.length >= 3 || state.hasNextPage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          showArrow: hasMore,
          onTap: hasMore ? () => context.push('/follow-suggestions') : null,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < preview.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          FollowSuggestionCard(
            suggestion: preview[i],
            isFollowing:
                state.followedIds.contains(preview[i].userId),
            isBusy: state.busyIds.contains(preview[i].userId),
            onFollow: () => _follow(preview[i].userId),
            onUnfollow: () => _unfollow(preview[i].userId),
            onDismiss: () => _dismiss(preview[i].userId, preview[i].fullName),
          ),
        ],
        if (hasMore) ...[
          const SizedBox(height: 8),
          _ShowAllButton(
            onTap: () => context.push('/follow-suggestions'),
          ),
        ],
      ],
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.showArrow, this.onTap});
  final bool showArrow;
  final VoidCallback? onTap;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Popular on Skillora',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _navy,
          ),
        ),
        const Spacer(),
        if (showArrow)
          GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: _navy.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

// ── "Show all" footer button ───────────────────────────────────────────────────

class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({required this.onTap});
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: _gold.withValues(alpha: 0.5), width: 1.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'Show all',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _navy.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

// ── Inline error card ─────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.08), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: _navy.withValues(alpha: 0.5), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Could not load popular people.',
              style:
                  TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.65)),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry', style: TextStyle(color: _navy)),
          ),
        ],
      ),
    );
  }
}
