import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../config/onboarding_flow.dart';

// Client-only onboarding — step 2: Individual ya Business?
// Business select hone pe business name field AnimatedSize se reveal hota hai.
// Continue pe PUT /api/profile/me (clientType + businessName). Fail pe bhi agy jao.
class OnboardingAboutYouScreen extends ConsumerStatefulWidget {
  const OnboardingAboutYouScreen({super.key});

  @override
  ConsumerState<OnboardingAboutYouScreen> createState() =>
      _OnboardingAboutYouScreenState();
}

class _OnboardingAboutYouScreenState
    extends ConsumerState<OnboardingAboutYouScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  int? _clientType; // null = kuch select nahi, 0 = Individual, 1 = Business
  final _businessNameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Role guard — freelancers is client-only screen pe nahi aane chahiye
    Future.microtask(() {
      if (!mounted) return;
      if (ref.read(signupFlowProvider).role == 0) {
        context.go('/onboarding-experience');
      }
    });
    // Wapas aaye to pehle ka data pre-fill
    final flow = ref.read(signupFlowProvider);
    _clientType = flow.clientType;
    _businessNameController.text = flow.businessName ?? '';
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_clientType == null) return false;
    if (_clientType == 1) return _businessNameController.text.trim().isNotEmpty;
    return true; // Individual ko business name ki zaroorat nahi
  }

  Future<void> _continue() async {
    final role = ref.read(signupFlowProvider).role;
    final next = OnboardingFlow.nextRouteAfter(OnboardingStep.aboutYou, role)!;
    final businessName =
        _clientType == 1 ? _businessNameController.text.trim() : null;

    ref
        .read(signupFlowProvider.notifier)
        .setClientInfo(clientType: _clientType!, businessName: businessName);

    setState(() => _isSubmitting = true);

    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(
              clientType: _clientType,
              businessName: businessName,
            ),
          );
      if (!mounted) return;
      context.go(next);
    } on DioException catch (_) {
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
    context.go(OnboardingFlow.nextRouteAfter(OnboardingStep.aboutYou, role)!);
  }

  @override
  Widget build(BuildContext context) {
    final firstName = ref.watch(signupFlowProvider).firstName.trim();
    final heading = firstName.isEmpty
        ? 'Tell us about yourself'
        : '$firstName, tell us about yourself';

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Slim gold progress — client step 2 of 4
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0.5,
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
                'Are you hiring as an individual or on behalf of a business?',
                style: TextStyle(
                  fontSize: 15,
                  color: _navy.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // ---- Individual card ----
              _ClientTypeCard(
                label: 'Individual',
                sublabel: 'Hiring for personal or freelance projects',
                icon: Icons.person_outline,
                selected: _clientType == 0,
                onTap: () => setState(() {
                  _clientType = 0;
                  _businessNameController.clear();
                }),
              ),

              // ---- Business card ----
              _ClientTypeCard(
                label: 'Business',
                sublabel: 'Hiring on behalf of a company or organisation',
                icon: Icons.business_outlined,
                selected: _clientType == 1,
                onTap: () => setState(() => _clientType = 1),
              ),

              // ---- Business name field — reveals only when Business is selected ----
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _clientType == 1
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: _businessNameController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: const TextStyle(color: _navy, fontSize: 15),
                          decoration: InputDecoration(
                            labelText: 'Business name',
                            labelStyle: TextStyle(
                              color: _navy.withValues(alpha: 0.55),
                              fontSize: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: _gold.withValues(alpha: 0.45),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: _gold, width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              const Spacer(),

              // ---- CONTINUE (disabled until valid) ----
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    disabledBackgroundColor: _navy.withValues(alpha: 0.3),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: (_isValid && !_isSubmitting) ? _continue : null,
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

              // ---- SKIP ----
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

class _ClientTypeCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ClientTypeCard({
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
