import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../data/models/experience_model.dart';
import '../../data/models/profile_model.dart';
import '../../data/repositories/profile_repository.dart';
import '../widgets/step_progress_bar.dart';

class ProfileStep2Screen extends ConsumerStatefulWidget {
  const ProfileStep2Screen({super.key});

  @override
  ConsumerState<ProfileStep2Screen> createState() => _ProfileStep2ScreenState();
}

class _ProfileStep2ScreenState extends ConsumerState<ProfileStep2Screen> {
  final _skillController = TextEditingController();
  final List<String> _skills = []; // thali — chips isi se draw hongi
  final List<ExperienceModel> _experiences = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile(); // pehle se saved skills + experiences lao (save-progress ka faida)
  }

  @override
  void dispose() {
    _skillController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      if (!mounted) return;
      setState(() {
        _skills.addAll(profile.skills);
        _experiences.addAll(profile.experiences);
      });
    } catch (_) {}
  }

  void _addSkill() {
    final text = _skillController.text.trim();
    if (text.isEmpty) return;
    // duplicate check — case-insensitive (Flutter aur flutter same hain)
    final exists = _skills.any((s) => s.toLowerCase() == text.toLowerCase());
    if (exists) {
      _skillController.clear();
      return;
    }
    if (_skills.length >= 30) {
      // backend limit 30 max — chupke se rukna nahi, user ko batao
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 30 skills allowed')),
      );
      return;
    }
    setState(() {
      _skills.add(text);
      _skillController.clear();
    });
  }

  void _showAddExperienceSheet() {
    final titleController = TextEditingController();
    final companyController = TextEditingController();
    DateTime? startDate;
    DateTime? endDate;
    bool isCurrent = true; // "I currently work here" — default checked

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // keyboard ke liye jagah
      builder: (sheetContext) {
        // StatefulBuilder — sheet ke ANDAR setState ke liye
        // (sheet ka apna chota setState hota hai — setSheetState)
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom, // keyboard push
                left: 24, right: 24, top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Experience',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyController,
                    decoration: const InputDecoration(labelText: 'Company'),
                  ),
                  const SizedBox(height: 12),
                  // Start date picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(startDate == null
                        ? 'Start date'
                        : 'Start: ${startDate!.toString().split(' ').first}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(1980),
                        lastDate: DateTime.now(), // future nahi — backend rule
                      );
                      if (picked != null) {
                        setSheetState(() => startDate = picked);
                      }
                    },
                  ),
                  // Currently working checkbox
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('I currently work here'),
                    value: isCurrent,
                    onChanged: (v) => setSheetState(() => isCurrent = v ?? true),
                  ),
                  // End date — sirf tab jab currently working NAHI
                  if (!isCurrent)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(endDate == null
                          ? 'End date'
                          : 'End: ${endDate!.toString().split(' ').first}'),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(1980),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => endDate = picked);
                        }
                      },
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A1633),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () async {
                        // simple validation
                        if (titleController.text.trim().isEmpty ||
                            companyController.text.trim().isEmpty ||
                            startDate == null) {
                          return;
                        }
                        final request = AddExperienceRequest(
                          title: titleController.text.trim(),
                          company: companyController.text.trim(),
                          startDate: startDate!,
                          endDate: isCurrent ? null : endDate,
                        );
                        try {
                          final added = await ref
                              .read(profileRepositoryProvider)
                              .addExperience(request);
                          if (!mounted || !sheetContext.mounted) return;
                          setState(() => _experiences.add(added)); // main list
                          Navigator.pop(sheetContext); // sheet band
                        } on DioException catch (e) {
                          if (!sheetContext.mounted) return;
                          final detail =
                              e.response?.data?['detail'] ?? 'Failed to add';
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(content: Text(detail.toString())));
                        }
                      },
                      child: const Text('Add',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleContinue() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(skills: _skills),
          );
      if (!mounted) return;
      context.go('/profile-step3'); // placeholder — F3.4 mein banega
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data?['detail'] ?? 'Something went wrong';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => context.go('/profile-step3'),
                  child: const Text('Skip for now'),
                ),
              ),
              const Text(
                'YOUR SKILLS',
                style: TextStyle(
                  color: Color(0xFFC0A062),
                  letterSpacing: 3,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Step 2 of 3',
                style: TextStyle(
                  color: Color(0xFF0A1633),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const StepProgressBar(currentStep: 2),
              const SizedBox(height: 24),

              // Input + Add button ek row mein
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _skillController,
                      decoration: const InputDecoration(
                        labelText: 'Add a skill',
                        hintText: 'e.g. Flutter',
                      ),
                      // keyboard ka "done" bhi add kare — chota UX touch
                      onSubmitted: (_) => _addSkill(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _addSkill,
                    icon: const Icon(Icons.add_circle,
                        color: Color(0xFF0A1633), size: 36),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Chips + Experience — dono ek hi scrollable Column mein
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Chips — Wrap = jagah khatam to agli line pe (Row overflow karta)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _skills.map((skill) {
                          return Chip(
                            label: Text(skill),
                            backgroundColor: const Color(0xFF0A1633),
                            labelStyle: const TextStyle(color: Colors.white),
                            deleteIconColor: const Color(0xFFC0A062),
                            onDeleted: () {
                              setState(() => _skills.remove(skill));
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Experience',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0A1633))),
                          TextButton.icon(
                            onPressed: _showAddExperienceSheet,
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      // Experience cards:
                      ..._experiences.map((exp) => Card(
                            child: ListTile(
                              title: Text(exp.title),
                              subtitle: Text(
                                  '${exp.company} • ${exp.startDate.year} - ${exp.endDate?.year ?? 'Present'}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(profileRepositoryProvider)
                                        .deleteExperience(exp.id);
                                    if (!context.mounted) return;
                                    setState(() => _experiences.remove(exp));
                                  } on DioException catch (_) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Delete failed')));
                                  }
                                },
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),

              // Counter — kitni add ho gayi
              Text(
                '${_skills.length}/30 skills',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A1633),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _isLoading ? null : _handleContinue,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Continue',
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
