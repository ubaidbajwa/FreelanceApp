// STATE APPROACH (a): reuses the existing invitationsProvider — unchanged.
// A separate InvitesPreviewNotifier would duplicate the accept/reject pessimistic
// logic and per-card busyIds. Shared provider keeps both consumers in sync:
// accepting on the home preview removes the card from the invitations screen too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../connections/application/invitations_notifier.dart';
import '../../../connections/presentation/widgets/received_invite_card.dart';
import 'invite_card_skeleton.dart';

class InvitesReceivedSection extends ConsumerWidget {
  const InvitesReceivedSection({super.key});

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(invitationsProvider);

    // Badge reads received.totalCount from the paged result — not items.length,
    // which is capped by pageSize and would undercount when there are many pages.
    final pendingCount = state.received.totalCount;

    if (state.loading && state.incoming.isEmpty) {
      return const InviteCardSkeleton();
    }

    if (state.error != null && state.incoming.isEmpty) {
      return _ErrorCard(
        onRetry: () => ref.read(invitationsProvider.notifier).load(),
      );
    }

    // Empty: render nothing — showing an empty "Invitations" block on a busy home
    // screen is noise. The user sees real content only when there's something to act on.
    // (Contrast with InvitationsScreen which always shows an explicit empty state,
    // because the user navigated there specifically to manage invitations.)
    if (state.incoming.isEmpty) return const SizedBox.shrink();

    final notifier = ref.read(invitationsProvider.notifier);
    final preview = state.incoming.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ──────────────────────────────────────────────────────
        Row(
          children: [
            const Text(
              'Invites received',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _navy,
              ),
            ),
            const Spacer(),
            if (pendingCount > 0) ...[
              _PendingBadge(count: pendingCount),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onTap: () => context.push('/connections/invitations'),
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
        ),
        const SizedBox(height: 12),

        // ── Preview cards (max 2) ────────────────────────────────────────────
        ReceivedInviteCard(
          request: preview[0],
          busy: state.busyIds.contains(preview[0].connectionId),
          onAccept: () => _run(context, ref, () => notifier.accept(preview[0].connectionId)),
          onReject: () => _run(context, ref, () => notifier.reject(preview[0].connectionId)),
        ),
        if (preview.length > 1) ...[
          const SizedBox(height: 8),
          ReceivedInviteCard(
            request: preview[1],
            busy: state.busyIds.contains(preview[1].connectionId),
            onAccept: () => _run(context, ref, () => notifier.accept(preview[1].connectionId)),
            onReject: () => _run(context, ref, () => notifier.reject(preview[1].connectionId)),
          ),
        ],
      ],
    );
  }

  // Overview refresh is handled inside InvitationsNotifier._act() — not here.
  // Keeping business logic in the notifier means it fires regardless of whether
  // the action was triggered from the home preview or the full invitations screen.
  static Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<String?> Function() action,
  ) async {
    final error = await action();
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
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
              'Could not load invitations.',
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

// ── Pending badge ──────────────────────────────────────────────────────────────

class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count});
  final int count;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count pending',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _navy.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}
