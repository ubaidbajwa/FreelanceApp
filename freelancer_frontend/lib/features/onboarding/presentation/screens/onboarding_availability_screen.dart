import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../config/onboarding_flow.dart';

// Post-signup onboarding — step 3: job search status.
// 0=Actively looking, 1=Open to offers, 2=Not looking right now.
// Continue: sets availabilityStatus in notifier + PUT /api/profile/me
//           (availabilityStatus field) then goes to job-preferences step.
// Skip: goes directly to job-preferences — no API call.
class OnboardingAvailabilityScreen extends ConsumerStatefulWidget {
  const OnboardingAvailabilityScreen({super.key});

  @override
  ConsumerState<OnboardingAvailabilityScreen> createState() =>
      _OnboardingAvailabilityScreenState();
}

class _OnboardingAvailabilityScreenState
    extends ConsumerState<OnboardingAvailabilityScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  int? _selected; // null = kuch select nahi, Continue disabled rehta hai
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Role guard — clients is freelancer-only screen pe nahi aane chahiye
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(signupFlowProvider).role == 1) {
        context.go('/onboarding-photo');
      }
    });
  }

  Future<void> _continue() async {
    final next = OnboardingFlow.nextRouteAfter(
        OnboardingStep.availability, ref.read(signupFlowProvider).role)!;
    // 1. Flow notifier mein save (0/1/2)
    ref.read(signupFlowProvider.notifier).setAvailabilityStatus(_selected!);
    setState(() => _isSubmitting = true);

    // 2. availabilityStatus field backend ko bhejo (partial update)
    // JSON key 'availabilityStatus' — UpdateProfileRequestDto ka exact field naam
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(availabilityStatus: _selected),
          );
      if (!mounted) return;
      context.go(next); // clear() job-prefs / photo mein hoga
    } on DioException catch (_) {
      // Fail hone pe bhi user ko block mat karo — data non-critical
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save right now")),
      );
      context.go(next);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _skip() {
    final role = ref.read(signupFlowProvider).role;
    context.go(OnboardingFlow.nextRouteAfter(OnboardingStep.availability, role)!);
  }

  @override
  Widget build(BuildContext context) {
    final firstName = ref.watch(signupFlowProvider).firstName.trim();
    final heading = firstName.isEmpty
        ? "What's your availability?"
        : "$firstName, what's your availability?";

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Slim gold progress — 1.0 = last onboarding step
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 1.0,
                  minHeight: 4,
                  color: _gold,
                  backgroundColor: _navy.withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(height: 8),
              // Back arrow — experience screen pe wapas
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  icon: const Icon(Icons.arrow_back, color: _navy),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(height: 8),

              Text(
                heading,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Let clients know if you're open to new opportunities.",
                style: TextStyle(
                  fontSize: 15,
                  color: _navy.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // ---- THREE SINGLE-SELECT CARDS ----
              _AvailabilityCard(
                label: 'Actively looking',
                sublabel: 'Ready to start a new project soon',
                icon: Icons.bolt,
                selected: _selected == 0,
                onTap: () => setState(() => _selected = 0),
              ),
              _AvailabilityCard(
                label: 'Open to offers',
                sublabel: 'Available for the right opportunity',
                icon: Icons.inbox_outlined,
                selected: _selected == 1,
                onTap: () => setState(() => _selected = 1),
              ),
              _AvailabilityCard(
                label: 'Not looking right now',
                sublabel: 'Not accepting new projects at the moment',
                icon: Icons.do_not_disturb_on_outlined,
                selected: _selected == 2,
                onTap: () => setState(() => _selected = 2),
              ),

              const Spacer(),

              // ---- CONTINUE (disabled until selection) ----
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    disabledBackgroundColor: _navy.withValues(alpha: 0.3),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: (_selected != null && !_isSubmitting)
                      ? _continue
                      : null,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),

              // ---- SKIP (muted, below Continue) ----
              SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: _isSubmitting ? null : _skip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: _navy.withValues(alpha: 0.5),
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

// Full-width selectable card — WorkPreference card se inspired:
// selected = navy bg + gold border + gold icon + checkmark
// unselected = white bg + faint gold border + muted icon
class _AvailabilityCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AvailabilityCard({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: selected ? _navy : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _gold : _gold.withValues(alpha: 0.45),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? _gold : _navy.withValues(alpha: 0.45),
              size: 22,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.65)
                          : _navy.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: _gold, size: 20),
          ],
        ),
      ),
    );
  }
}
