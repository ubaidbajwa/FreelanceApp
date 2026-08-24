import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../data/models/profile_model.dart';
import '../../data/repositories/profile_repository.dart';
import '../widgets/step_progress_bar.dart';

class ProfileStep3Screen extends ConsumerStatefulWidget {
  const ProfileStep3Screen({super.key});

  @override
  ConsumerState<ProfileStep3Screen> createState() => _ProfileStep3ScreenState();
}

class _ProfileStep3ScreenState extends ConsumerState<ProfileStep3Screen> {
  final _rateController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();

  int? _availability;    // null = kuch select nahi
  int? _workPreference;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      if (!mounted) return;
      setState(() {
        if (profile.hourlyRate != null) {
          _rateController.text = profile.hourlyRate.toString();
        }
        _countryController.text = profile.country ?? '';
        _cityController.text = profile.city ?? '';
        _availability = profile.availability;
        _workPreference = profile.workPreference;
      });
    } catch (_) {}
  }

  Future<void> _handleFinish() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(
              // rate parse — invalid text to null (bhejo hi mat)
              hourlyRate: double.tryParse(_rateController.text.trim()),
              availability: _availability,
              workPreference: _workPreference,
              country: _countryController.text.trim().isEmpty
                  ? null
                  : _countryController.text.trim(),
              city: _cityController.text.trim().isEmpty
                  ? null
                  : _cityController.text.trim(),
            ),
          );
      if (!mounted) return;
      context.go('/username'); // wizard ka asli end ab username claim hai
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data?['detail'] ?? 'Something went wrong';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Reusable selectable card — dono groups isi se banenge
  Widget _choiceCard({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0A1633) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFFC0A062)   // gold border jab selected
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? const Color(0xFFC0A062) : Colors.grey),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : Colors.black87,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Skip for now'),
                ),
              ),
              const Text('WORK PREFERENCES',
                  style: TextStyle(
                      color: Color(0xFFC0A062),
                      letterSpacing: 3,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Step 3 of 3',
                  style: TextStyle(
                      color: Color(0xFF0A1633),
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const StepProgressBar(currentStep: 3),
              const SizedBox(height: 24),

              TextField(
                controller: _rateController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Hourly Rate (USD)',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 24),

              const Text('Availability',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                _choiceCard(
                  label: 'Full-time',
                  icon: Icons.work,
                  selected: _availability == 0,
                  onTap: () => setState(() => _availability = 0),
                ),
                _choiceCard(
                  label: 'Part-time',
                  icon: Icons.schedule,
                  selected: _availability == 1,
                  onTap: () => setState(() => _availability = 1),
                ),
                _choiceCard(
                  label: 'Custom',
                  icon: Icons.tune,
                  selected: _availability == 2,
                  onTap: () => setState(() => _availability = 2),
                ),
              ]),
              const SizedBox(height: 24),

              const Text('Work Preference',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                _choiceCard(
                  label: 'Remote',
                  icon: Icons.home,
                  selected: _workPreference == 0,
                  onTap: () => setState(() => _workPreference = 0),
                ),
                _choiceCard(
                  label: 'On-site',
                  icon: Icons.apartment,
                  selected: _workPreference == 1,
                  onTap: () => setState(() => _workPreference = 1),
                ),
                _choiceCard(
                  label: 'Hybrid',
                  icon: Icons.sync_alt,
                  selected: _workPreference == 2,
                  onTap: () => setState(() => _workPreference = 2),
                ),
              ]),
              const SizedBox(height: 24),

              TextField(
                controller: _countryController,
                decoration: const InputDecoration(labelText: 'Country'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _cityController,
                decoration: const InputDecoration(labelText: 'City'),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A1633),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isLoading ? null : _handleFinish,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Finish',
                          style:
                              TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}