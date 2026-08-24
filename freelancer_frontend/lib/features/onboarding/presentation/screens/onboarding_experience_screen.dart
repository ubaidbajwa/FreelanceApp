import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/presentation/widgets/job_title_sheet.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../config/onboarding_flow.dart';
import '../../../profile/data/models/profile_model.dart';
import '../../../profile/data/repositories/profile_repository.dart';

// Post-signup onboarding — step 2: most recent experience (LinkedIn-style).
// Student toggle se do modes: professional (job title + company) ya student
// (school/degree/field/year + age check). Continue pe backend ko sirf woh
// fields jate hain jo aaj API support karti hai (country, city, headline);
// baaki detail abhi sirf SignupFlowNotifier mein.
class OnboardingExperienceScreen extends ConsumerStatefulWidget {
  const OnboardingExperienceScreen({super.key});

  @override
  ConsumerState<OnboardingExperienceScreen> createState() =>
      _OnboardingExperienceScreenState();
}

class _OnboardingExperienceScreenState
    extends ConsumerState<OnboardingExperienceScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _noCompany = 'None at this time';

  bool _isStudent = false;
  String? _jobTitle;

  final _companyController = TextEditingController();
  final _schoolController = TextEditingController();
  final _degreeController = TextEditingController();
  final _fieldOfStudyController = TextEditingController();
  int? _startYear;
  bool _over16 = false;

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
    // Wapas aaye to pehle ka data pre-fill
    final flow = ref.read(signupFlowProvider);
    _isStudent = flow.isStudent ?? false;
    _jobTitle = flow.jobTitle;
    _companyController.text = flow.company ?? '';
    _schoolController.text = flow.school ?? '';
    _degreeController.text = flow.degree ?? '';
    _fieldOfStudyController.text = flow.fieldOfStudy ?? '';
    _startYear = flow.startYear;
  }

  @override
  void dispose() {
    _companyController.dispose();
    _schoolController.dispose();
    _degreeController.dispose();
    _fieldOfStudyController.dispose();
    super.dispose();
  }

  bool get _isValid {
    if (_isStudent) {
      return _schoolController.text.trim().isNotEmpty &&
          _fieldOfStudyController.text.trim().isNotEmpty &&
          _startYear != null &&
          _over16;
    }
    return (_jobTitle?.trim().isNotEmpty ?? false) &&
        _companyController.text.trim().isNotEmpty;
  }

  Future<void> _pickJobTitle() async {
    final picked = await showJobTitleSheet(context, initial: _jobTitle ?? '');
    if (picked != null) setState(() => _jobTitle = picked);
  }

  // Backend headline compose — mode ke hisab se
  String _composeHeadline() {
    if (_isStudent) {
      return 'Student at ${_schoolController.text.trim()}';
    }
    final title = _jobTitle!.trim();
    final company = _companyController.text.trim();
    // "None at this time" pe sirf title dikhao
    if (company == _noCompany) return title;
    return '$title at $company';
  }

  Future<void> _continue() async {
    final flow = ref.read(signupFlowProvider);
    final next = OnboardingFlow.nextRouteAfter(OnboardingStep.experience, flow.role)!;

    // 1. Sab kuch flow notifier mein save
    ref.read(signupFlowProvider.notifier).setExperience(
          jobTitle: _isStudent ? null : _jobTitle,
          company: _isStudent ? null : _companyController.text.trim(),
          isStudent: _isStudent,
          school: _isStudent ? _schoolController.text.trim() : null,
          degree: _isStudent && _degreeController.text.trim().isNotEmpty
              ? _degreeController.text.trim()
              : null,
          fieldOfStudy:
              _isStudent ? _fieldOfStudyController.text.trim() : null,
          startYear: _isStudent ? _startYear : null,
        );

    setState(() => _isSubmitting = true);

    // 2. Backend ko sirf supported fields: country, city, headline
    // TODO: push to Education/Experience API when backend slice ready
    final request = UpdateProfileRequest(
      country: flow.country,
      city: flow.city,
      headline: _composeHeadline(),
    );

    try {
      await ref.read(profileRepositoryProvider).updateProfile(request);
      if (!mounted) return;
      // 3. Success — availability step pe bhejo (clear wahan hoga)
      context.go(next);
    } on DioException catch (_) {
      // 4. Fail — data non-critical hai, user ko trap mat karo. Aage bhejo.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save right now")),
      );
      context.go(next);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstName = ref.watch(signupFlowProvider).firstName.trim();
    final heading = firstName.isEmpty
        ? "What's your most recent experience?"
        : "$firstName, what's your most recent experience?";

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Slim gold progress — experience = 0.75
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
              // Back arrow (experience screen only)
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

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        'You can always change this later.',
                        style: TextStyle(
                          fontSize: 15,
                          color: _navy.withValues(alpha: 0.6),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Student toggle
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              "I'm a student",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _navy,
                              ),
                            ),
                          ),
                          Switch(
                            value: _isStudent,
                            activeThumbColor: _navy,
                            activeTrackColor: _gold,
                            onChanged: (v) => setState(() => _isStudent = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Mode switch — professional <-> student
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _isStudent
                            ? _buildStudentMode()
                            : _buildProfessionalMode(),
                      ),
                    ],
                  ),
                ),
              ),

              // Continue
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
                      (_isValid && !_isSubmitting) ? _continue : null,
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ---- PROFESSIONAL MODE ----
  Widget _buildProfessionalMode() {
    return Column(
      key: const ValueKey('professional'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Job title*'),
        const SizedBox(height: 8),
        // Read-only field → job title search sheet
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: _pickJobTitle,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (_jobTitle?.isNotEmpty ?? false)
                      ? _gold
                      : _gold.withValues(alpha: 0.45),
                  width: (_jobTitle?.isNotEmpty ?? false) ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (_jobTitle?.isNotEmpty ?? false)
                          ? _jobTitle!
                          : 'Select or type your title',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        color: (_jobTitle?.isNotEmpty ?? false)
                            ? _navy
                            : _navy.withValues(alpha: 0.35),
                        fontWeight: (_jobTitle?.isNotEmpty ?? false)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Icon(Icons.search, color: _navy.withValues(alpha: 0.5)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        _label('Company / Employer*'),
        const SizedBox(height: 8),
        TextField(
          controller: _companyController,
          style: const TextStyle(color: _navy),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Enter company or employer'),
        ),
        const SizedBox(height: 10),
        // Helper chip — literal "None at this time" bhar deta hai
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            label: const Text(_noCompany),
            labelStyle: const TextStyle(color: _navy, fontSize: 13),
            backgroundColor: Colors.white,
            side: BorderSide(color: _gold.withValues(alpha: 0.45)),
            shape: const StadiumBorder(),
            onPressed: () {
              _companyController.text = _noCompany;
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  // ---- STUDENT MODE ----
  Widget _buildStudentMode() {
    final currentYear = DateTime.now().year;
    final years = [for (int y = currentYear; y >= 1990; y--) y];

    return Column(
      key: const ValueKey('student'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('School, college or university*'),
        const SizedBox(height: 8),
        TextField(
          controller: _schoolController,
          style: const TextStyle(color: _navy),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('Enter your institution'),
        ),
        const SizedBox(height: 20),

        _label('Degree'),
        const SizedBox(height: 8),
        TextField(
          controller: _degreeController,
          style: const TextStyle(color: _navy),
          decoration: _inputDecoration('e.g. Bachelor of Science (optional)'),
        ),
        const SizedBox(height: 20),

        _label('Field of study*'),
        const SizedBox(height: 8),
        TextField(
          controller: _fieldOfStudyController,
          style: const TextStyle(color: _navy),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration('e.g. Computer Science'),
        ),
        const SizedBox(height: 20),

        _label('Start year*'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _startYear,
          isExpanded: true,
          style: const TextStyle(color: _navy, fontSize: 16),
          decoration: _inputDecoration('Select start year'),
          items: years
              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
              .toList(),
          onChanged: (v) => setState(() => _startYear = v),
        ),
        const SizedBox(height: 12),

        // Over-16 check — gold tick, required
        InkWell(
          onTap: () => setState(() => _over16 = !_over16),
          child: Row(
            children: [
              Checkbox(
                value: _over16,
                activeColor: _gold,
                checkColor: _navy,
                onChanged: (v) => setState(() => _over16 = v ?? false),
              ),
              const Expanded(
                child: Text(
                  "I'm over 16 years of age",
                  style: TextStyle(fontSize: 15, color: _navy),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _navy,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
      );
}
