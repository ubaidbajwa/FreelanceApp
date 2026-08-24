import 'package:flutter/material.dart';

// No existing UserAvatar found in the codebase — created here as the shared widget.
// Navy fill + gold initials matches the _avatar helper pattern already in InvitationsScreen.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.fullName,
    this.photoUrl,
    required this.radius,
  });

  final String fullName;
  final String? photoUrl;
  final double radius;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  String get _initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _navy,
      foregroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
      child: Text(
        _initials,
        style: TextStyle(
          color: _gold,
          fontSize: radius * 0.55,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
