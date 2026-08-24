import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/user_role.dart';

// Riverpod 3 mein StateProvider legacy ho gaya hai — ab Notifier use hota hai
// Notifier = state + usko badalne ke methods, ek class mein (jaise C# mein service class)

// Selected role — Notifier pattern (Riverpod 3)
class SelectedRoleNotifier extends Notifier<UserRole?> {
  @override
  UserRole? build() => null;

  void select(UserRole role) => state = role;
}

final selectedRoleProvider = NotifierProvider<SelectedRoleNotifier, UserRole?>(
  SelectedRoleNotifier.new,
);
