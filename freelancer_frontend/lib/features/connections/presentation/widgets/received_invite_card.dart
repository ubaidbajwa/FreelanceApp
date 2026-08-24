// Shared card widget used by BOTH:
//   - InvitesReceivedSection (home preview, F-N2)
//   - InvitationsScreen Received tab (F-N5)
// Extracted here so the card layout, mutual avatar stack, and action buttons
// are never duplicated. Any visual change applies to both consumers at once.
import 'package:flutter/material.dart';

import '../../../../core/presentation/widgets/user_avatar.dart';
import '../../data/models/connection_models.dart';

class ReceivedInviteCard extends StatelessWidget {
  const ReceivedInviteCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  final PendingRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  static const _gold = Color(0xFFC0A062);
  static const _navy = Color(0xFF0A1633);

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
          // Avatar — 56×56 (radius 28)
          UserAvatar(
            fullName: request.user.name,
            photoUrl: request.user.profilePhotoUrl,
            radius: 28,
          ),
          const SizedBox(width: 12),

          // Middle content — Expanded so it never overflows
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name — constrained to one line; long names (60+ chars) get ellipsis
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
                  const SizedBox(height: 2),
                  Text(
                    request.user.headline!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                _MutualRow(request: request),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Right side — action buttons or spinner
          if (busy)
            const _BusyWidget()
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.close,
                  iconColor: _navy.withValues(alpha: 0.5),
                  borderColor: _navy.withValues(alpha: 0.25),
                  tooltip: 'Ignore invitation from ${request.user.name}',
                  onTap: onReject,
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.check,
                  iconColor: _gold,
                  borderColor: _gold,
                  tooltip: 'Accept invitation from ${request.user.name}',
                  onTap: onAccept,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Mutual connections row ─────────────────────────────────────────────────────

class _MutualRow extends StatelessWidget {
  const _MutualRow({required this.request});
  final PendingRequest request;

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    final count = request.mutualConnectionsCount;

    if (count == 0) {
      return Text(
        'No mutual connections',
        style: TextStyle(fontSize: 12, color: _navy.withValues(alpha: 0.4)),
      );
    }

    final label =
        count == 1 ? '1 mutual connection' : '$count mutual connections';

    return Row(
      children: [
        if (request.mutualPreview.isNotEmpty) ...[
          _OverlappingAvatarStack(users: request.mutualPreview),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: _navy.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Overlapping mutual avatar stack ───────────────────────────────────────────
// Uses Positioned (no negative margins). Spec: "REUSE — do not rebuild the stack".

class _OverlappingAvatarStack extends StatelessWidget {
  const _OverlappingAvatarStack({required this.users});
  final List<MutualPreview> users;

  static const _avatarSize = 20.0;
  static const _step = 13.0;

  @override
  Widget build(BuildContext context) {
    final count = users.length.clamp(0, 3);
    if (count == 0) return const SizedBox.shrink();
    final stackWidth = _avatarSize + (count - 1) * _step;

    return SizedBox(
      width: stackWidth,
      height: _avatarSize,
      child: Stack(
        children: List.generate(
          count,
          (i) => Positioned(
            left: i * _step,
            child: _SmallAvatar(user: users[i]),
          ),
        ),
      ),
    );
  }
}

class _SmallAvatar extends StatelessWidget {
  const _SmallAvatar({required this.user});
  final MutualPreview user;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;

    // 20×20 circle with 1.5px white border so overlapping avatars appear separated.
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        color: _navy,
        image: hasPhoto
            ? DecorationImage(
                image: NetworkImage(user.photoUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                user.fullName.isNotEmpty
                    ? user.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}

// ── Action button (× reject / ✓ accept) ───────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.borderColor,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color borderColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 44×44 tap target (Semantics + SizedBox); 40×40 visual circle inside.
    return Semantics(
      label: tooltip,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 1.5),
              ),
              child: Center(child: Icon(icon, color: iconColor, size: 18)),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Busy spinner — replaces both buttons while API call is in-flight ──────────

class _BusyWidget extends StatelessWidget {
  const _BusyWidget();

  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    // Same height as two-button column (44 + 8 + 44 = 96px) — card does not
    // resize when switching between buttons and spinner.
    return const SizedBox(
      width: 44,
      height: 96,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
        ),
      ),
    );
  }
}
