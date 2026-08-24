import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/user_role.dart';
import '../../providers/onboarding_providers.dart';

class RoleSelectionScreen extends ConsumerWidget {
  const RoleSelectionScreen({super.key});

  // Theme tokens (CLAUDE.md ke mutabiq)
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedRole = ref.watch(selectedRoleProvider);

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              // Gold overline label — theme ka signature style
              Text(
                'STEP 2 OF 2',
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'How will you use\nSkillora?',
                style: TextStyle(
                  color: _navy,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 40),

              // Role cards — enum se auto-generate (config-driven soch!)
              ...UserRole.values.map((role) {
                final isSelected = selectedRole == role;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () =>
                        ref.read(selectedRoleProvider.notifier).select(role),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isSelected ? _navy : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? _gold : Colors.grey.shade300,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            role == UserRole.freelancer
                                ? Icons.work_outline_rounded
                                : Icons.business_center_outlined,
                            size: 36,
                            color: isSelected ? _gold : _navy,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  role.label,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : _navy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  role.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isSelected
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: _gold),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const Spacer(), // bachi hui jagah — button neeche push

              // Continue — tabhi enable jab role selected ho
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: const StadiumBorder(), // theme ka pill style
                  ),
                  onPressed: selectedRole == null
                      ? null // null = button disabled
                      : () => context.go('/signup'),
                  child: const Text('Continue',
                      style: TextStyle(fontSize: 16, letterSpacing: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
