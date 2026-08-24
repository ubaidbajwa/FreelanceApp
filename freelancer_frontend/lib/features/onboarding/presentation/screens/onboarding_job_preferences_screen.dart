import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/country_config.dart';
import '../../../../core/presentation/widgets/country_search_sheet.dart';
import '../../../../core/presentation/widgets/job_title_sheet.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../config/onboarding_flow.dart';

// Post-signup onboarding — step 4: job preferences.
// Desired job titles (max 5) + desired locations (max 5) + work preference
// (Remote/On-site/Hybrid). All fields nullable — Skip allowed.
// Continue: setJobPreferences notifier + PUT /api/profile/me (partial) +
//           navigate to photo step.
// Skip: navigate to photo step directly, no API call.
class OnboardingJobPreferencesScreen extends ConsumerStatefulWidget {
  const OnboardingJobPreferencesScreen({super.key});

  @override
  ConsumerState<OnboardingJobPreferencesScreen> createState() =>
      _OnboardingJobPreferencesScreenState();
}

class _OnboardingJobPreferencesScreenState
    extends ConsumerState<OnboardingJobPreferencesScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _maxItems = 5;

  final List<String> _titles = [];
  final List<String> _locations = [];
  int? _workPreference; // null = not selected; 0=Remote 1=OnSite 2=Hybrid

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

  // Continue enabled jab koi ek bhi selection ho
  bool get _canContinue =>
      _titles.isNotEmpty || _locations.isNotEmpty || _workPreference != null;

  Future<void> _addTitle() async {
    if (_titles.length >= _maxItems) return;
    final picked = await showJobTitleSheet(context, initial: '');
    if (picked == null || !mounted) return;
    final trimmed = picked.trim();
    if (trimmed.isEmpty) return;
    // Case-insensitive de-duplication
    if (_titles.any((t) => t.toLowerCase() == trimmed.toLowerCase())) return;
    setState(() => _titles.add(trimmed));
  }

  Future<void> _addLocation() async {
    if (_locations.length >= _maxItems) return;
    final CountryConfig? picked = await showCountrySearchSheet(context);
    if (picked == null || !mounted) return;
    final name = picked.name.trim();
    if (_locations.any((l) => l.toLowerCase() == name.toLowerCase())) return;
    setState(() => _locations.add(name));
  }

  Future<void> _continue() async {
    final next = OnboardingFlow.nextRouteAfter(
        OnboardingStep.jobPreferences, ref.read(signupFlowProvider).role)!;
    // 1. Save all three fields to flow notifier
    ref.read(signupFlowProvider.notifier).setJobPreferences(
          desiredJobTitles: List.of(_titles),
          desiredJobLocations: List.of(_locations),
          workPreference: _workPreference,
        );
    setState(() => _isSubmitting = true);

    // 2. Partial update — sirf ye 3 fields bhejo
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(
              desiredJobTitles: _titles.isEmpty ? null : List.of(_titles),
              desiredJobLocations:
                  _locations.isEmpty ? null : List.of(_locations),
              workPreference: _workPreference,
            ),
          );
      if (!mounted) return;
      context.go(next); // clear() photo step mein hoga
    } on DioException catch (_) {
      // Fail pe bhi user ko block mat karo — ye fields non-critical hain
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
    context.go(OnboardingFlow.nextRouteAfter(OnboardingStep.jobPreferences, role)!);
  }

  @override
  Widget build(BuildContext context) {
    final firstName = ref.watch(signupFlowProvider).firstName.trim();
    final heading = firstName.isEmpty
        ? "What are you looking for?"
        : "$firstName, what are you looking for?";

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
                  // Slim gold progress — last onboarding step
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
                  // Back arrow
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
                    'Add up to 5 job titles and 5 locations.',
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
                    // ---- JOB TITLES ----
                    _sectionLabel('Job titles'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._titles.map(
                          (t) => _removableChip(
                            t,
                            () => setState(() => _titles.remove(t)),
                          ),
                        ),
                        if (_titles.length < _maxItems)
                          _addPill(onTap: _addTitle)
                        else
                          _limitText(),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- JOB LOCATIONS ----
                    _sectionLabel('Job locations'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._locations.map(
                          (l) => _removableChip(
                            l,
                            () => setState(() => _locations.remove(l)),
                          ),
                        ),
                        if (_locations.length < _maxItems)
                          _addPill(onTap: _addLocation)
                        else
                          _limitText(),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ---- WORK PREFERENCE ----
                    _sectionLabel('Work preference'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        _workPrefChip('Remote', 0),
                        _workPrefChip('On-site', 1),
                        _workPrefChip('Hybrid', 2),
                      ],
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
                  // Continue — disabled until at least one selection
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        disabledBackgroundColor: _navy.withValues(alpha: 0.3),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: (_canContinue && !_isSubmitting)
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

  // Navy chip with gold X — same as profile_step2 chip pattern
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

  // Small gold-border pill — "+ Add" button
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

  // Shown in place of "+ Add" when list is full
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

  // Single-select chip — navy+gold when selected, white when not
  Widget _workPrefChip(String label, int value) {
    final selected = _workPreference == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // Tap again to deselect (set to null)
      onSelected: (v) => setState(() => _workPreference = v ? value : null),
      selectedColor: _navy,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : _navy,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      side: BorderSide(
        color: selected ? _gold : _gold.withValues(alpha: 0.45),
        width: selected ? 1.5 : 1.0,
      ),
      shape: const StadiumBorder(),
      showCheckmark: false,
    );
  }
}
