// PROVIDER STRATEGY (shared): home section and SuggestionsScreen use ONE
// suggestionsProvider. The home section shows items.take(6); the full screen
// appends pages via loadMore(). No conflict: build() fires _loadFirst once
// on provider creation (when this section first mounts). The full screen
// reuses the already-loaded list and appends from there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/suggestions_notifier.dart';
import 'suggestion_card.dart';
import 'suggestion_card_skeleton.dart';

class SuggestionsSection extends ConsumerStatefulWidget {
  const SuggestionsSection({super.key});

  @override
  ConsumerState<SuggestionsSection> createState() => _SuggestionsSectionState();
}

class _SuggestionsSectionState extends ConsumerState<SuggestionsSection> {
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
    // Capture messenger before the async SnackBar action fires
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

    // Loading skeleton — 2 cards matching SuggestionCard shape
    if (state.loading && state.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(onShowAll: null),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.55,
            ),
            itemCount: 2,
            itemBuilder: (_, _) => const SuggestionCardSkeleton(),
          ),
        ],
      );
    }

    // Error: inline — does not blank the rest of the home screen
    if (state.error != null && state.items.isEmpty) {
      return _ErrorCard(
        onRetry: () => ref.read(suggestionsProvider.notifier).refresh(),
      );
    }

    // Empty: nothing to show — avoids rendering a blank section header
    if (state.items.isEmpty) return const SizedBox.shrink();

    final preview = state.items.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          onShowAll: state.items.length >= 6 || state.hasNextPage
              ? () => context.push('/suggestions')
              : null,
        ),
        const SizedBox(height: 12),
        // NeverScrollableScrollPhysics: this grid is inside MyNetworkHomeScreen's
        // SingleChildScrollView. Two nested scrollables on the same axis would conflict.
        // The 6-card cap makes the fixed height predictable without scroll-back shimming.
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 0.55,
          ),
          itemCount: preview.length,
          itemBuilder: (_, i) {
            final s = preview[i];
            return SuggestionCard(
              suggestion: s,
              isRequested: state.requestedIds.contains(s.userId),
              isBusy: state.busyIds.contains(s.userId),
              onConnect: () => _connect(s.userId),
              onDismiss: () => _dismiss(s.userId, s.fullName),
            );
          },
        ),
        // "Show all" footer — only when there are more than 6 or next page exists
        if (state.items.length >= 6 || state.hasNextPage) ...[
          const SizedBox(height: 8),
          _ShowAllButton(onTap: () => context.push('/suggestions')),
        ],
      ],
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onShowAll});
  final VoidCallback? onShowAll;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'People you may know',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: _navy,
          ),
        ),
        const Spacer(),
        if (onShowAll != null)
          GestureDetector(
            onTap: onShowAll,
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

// ── "Show all" button ──────────────────────────────────────────────────────────

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
          'Show all suggestions',
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

// ── Error card ─────────────────────────────────────────────────────────────────

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
              'Could not load suggestions.',
              style: TextStyle(
                  fontSize: 14, color: _navy.withValues(alpha: 0.65)),
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
