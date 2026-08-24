import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/presentation/widgets/hiring_interests_sheet.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../config/onboarding_flow.dart';

// Client-only onboarding — step 3 of 4: hiring interests + optional hiring type.
// Max 5 skills/categories (case-insensitive de-dup enforced here).
// HiringType is optional — user may leave neither card selected.
// Continue: save to SignupFlowNotifier + PUT /api/profile/me + next route.
//           On API failure: SnackBar but still proceed (non-critical fields).
// Skip: go to next route without any API call.
class OnboardingHiringInterestsScreen extends ConsumerStatefulWidget {
  const OnboardingHiringInterestsScreen({super.key});

  @override
  ConsumerState<OnboardingHiringInterestsScreen> createState() =>
      _OnboardingHiringInterestsScreenState();
}

class _OnboardingHiringInterestsScreenState
    extends ConsumerState<OnboardingHiringInterestsScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _maxItems = 5;

  final List<String> _interests = [];
  int? _hiringType; // null = not selected, 0 = OneTimeProject, 1 = OngoingWork
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Role guard — freelancers is client-only screen pe nahi aane chahiye
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(signupFlowProvider).role == 0) {
        context.go('/onboarding-photo');
      }
    });
    // Wapas aaye to pehle ka data pre-fill (screen revisit)
    final flow = ref.read(signupFlowProvider);
    if (flow.hiringInterests != null) {
      _interests.addAll(flow.hiringInterests!);
    }
    _hiringType = flow.hiringType;
  }

  // Continue at least one interest chahiye; hiring type optional hai
  bool get _canContinue => _interests.isNotEmpty;

  Future<void> _addInterest() async {
    if (_interests.length >= _maxItems) return;
    final picked = await showHiringInterestsSheet(context);
    if (picked == null || !mounted) return;
    final trimmed = picked.trim();
    if (trimmed.isEmpty) return;
    // Case-insensitive de-dup — trim + lowercase compare karo
    if (_interests.any((i) => i.toLowerCase() == trimmed.toLowerCase())) return;
    setState(() => _interests.add(trimmed));
  }

  Future<void> _continue() async {
    final role = ref.read(signupFlowProvider).role;
    final next =
        OnboardingFlow.nextRouteAfter(OnboardingStep.hiringInterests, role)!;

    // 1. Save to flow notifier
    ref.read(signupFlowProvider.notifier).setHiringInterests(
          hiringInterests: List.of(_interests),
          hiringType: _hiringType,
        );

    setState(() => _isSubmitting = true);

    // 2. Partial update — sirf ye 2 fields bhejo (hiringType null ho to omit)
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(
              hiringInterests: List.of(_interests),
              hiringType: _hiringType,
            ),
          );
      if (!mounted) return;
      context.go(next);
    } on DioException catch (_) {
      // Fail pe bhi block mat karo — profile baad mein complete ho sakta hai
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
    context.go(
        OnboardingFlow.nextRouteAfter(OnboardingStep.hiringInterests, role)!);
  }

  @override
  Widget build(BuildContext context) {
    final firstName = ref.watch(signupFlowProvider).firstName.trim();
    final heading = firstName.isEmpty
        ? "What are you hiring for?"
        : "$firstName, what are you hiring for?";

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- FIXED HEADER ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Slim gold progress — client step 3 of 4
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.75,
                      minHeight: 4,
                      color: _gold,
                      backgroundColor: _navy.withValues(alpha: 0.1),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                    'Pick up to 5 skills or categories.',
                    style: TextStyle(
                      fontSize: 15,
                      color: _navy.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ---- SCROLLABLE MIDDLE ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---- HIRING INTERESTS ----
                    _sectionLabel('Hiring interests'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._interests.map(
                          (i) => _removableChip(
                            i,
                            () => setState(() => _interests.remove(i)),
                          ),
                        ),
                        if (_interests.length < _maxItems)
                          _addPill(onTap: _addInterest)
                        else
                          _limitText(),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ---- HIRING TYPE (optional) ----
                    _sectionLabel('Hiring type'),
                    const SizedBox(height: 4),
                    Text(
                      'Optional',
                      style: TextStyle(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _HiringTypeCard(
                      label: 'One-time project',
                      sublabel: 'A defined scope with a clear deliverable',
                      icon: Icons.task_outlined,
                      selected: _hiringType == 0,
                      // Tap again to deselect
                      onTap: () => setState(
                          () => _hiringType = _hiringType == 0 ? null : 0),
                    ),
                    _HiringTypeCard(
                      label: 'Ongoing work',
                      sublabel: 'Recurring tasks or a long-term engagement',
                      icon: Icons.autorenew,
                      selected: _hiringType == 1,
                      onTap: () => setState(
                          () => _hiringType = _hiringType == 1 ? null : 1),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ---- FIXED FOOTER ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Column(
                children: [
                  // Continue — disabled until at least one interest is added
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        disabledBackgroundColor: _navy.withValues(alpha: 0.3),
                        shape: const StadiumBorder(),
                      ),
                      onPressed:
                          (_canContinue && !_isSubmitting) ? _continue : null,
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

                  // Skip
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- HELPER WIDGETS ----

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _navy,
        ),
      );

  // Navy chip with gold X — same pattern as job preferences screen
  Widget _removableChip(String label, VoidCallback onRemove) => Chip(
        label: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: _navy,
        deleteIconColor: _gold,
        side: BorderSide(color: _gold.withValues(alpha: 0.35)),
        shape: const StadiumBorder(),
        onDeleted: onRemove,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      );

  // Small gold-border pill — shown when list < max
  Widget _addPill({required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _gold.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 15, color: _navy.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                'Add',
                style: TextStyle(
                  color: _navy.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );

  // Shown instead of "+ Add" when list is full — prevents silent tap-ignore
  Widget _limitText() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'Max. $_maxItems reached',
          style: TextStyle(
            fontSize: 12,
            color: _navy.withValues(alpha: 0.4),
          ),
        ),
      );
}

// ---- HIRING TYPE CARD ----
// Same visual pattern as _ClientTypeCard in about_you_screen.
// Tap again to deselect (toggle: selected → null).

class _HiringTypeCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _HiringTypeCard({
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
