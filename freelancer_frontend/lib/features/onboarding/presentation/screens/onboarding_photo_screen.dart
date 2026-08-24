import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../auth/application/auth_session.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../../profile/data/repositories/profile_repository.dart';

// Post-signup onboarding — last step: profile photo.
// Shows a live preview card (avatar + display name + headline).
// Name/headline come from a GET /api/profile/me call on init,
// with firstName+lastName from SignupFlowNotifier as immediate fallback.
// Pick opens a sheet (gallery / camera). Local file previews immediately.
// Continue with photo: upload via uploadPhoto() repo method then route.
// Continue without photo, or Skip: route directly (no API call).
class OnboardingPhotoScreen extends ConsumerStatefulWidget {
  const OnboardingPhotoScreen({super.key});

  @override
  ConsumerState<OnboardingPhotoScreen> createState() =>
      _OnboardingPhotoScreenState();
}

class _OnboardingPhotoScreenState
    extends ConsumerState<OnboardingPhotoScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  XFile? _pickedFile;          // locally picked image (before upload)
  String _displayName = '';    // from backend profile (or flow fallback)
  String? _headline;           // from backend profile
  String? _initialPhotoUrl;    // existing photo URL from backend
  bool _isSubmitting = false;

  // Highest priority: local pick; fallback: backend URL; else null (shows icon)
  ImageProvider? get _avatarImage {
    if (_pickedFile != null) return FileImage(File(_pickedFile!.path));
    if (_initialPhotoUrl != null) return NetworkImage(_initialPhotoUrl!);
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Immediate name from signup flow — shows before backend responds
    final flow = ref.read(signupFlowProvider);
    final flowName = '${flow.firstName} ${flow.lastName}'.trim();
    if (flowName.isNotEmpty) _displayName = flowName;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      if (!mounted) return;
      setState(() {
        if (profile.displayName != null && profile.displayName!.isNotEmpty) {
          _displayName = profile.displayName!;
        }
        _headline = profile.headline;
        _initialPhotoUrl = profile.profilePhotoUrl;
      });
    } catch (_) {
      // Pre-fill fail pe bhi screen chalti rahe — signup fallback already set
    }
  }

  void _showPickSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: _navy),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_outlined, color: _navy),
              title: const Text(
                'Take photo',
                style: TextStyle(color: _navy, fontWeight: FontWeight.w500),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;
    // Immediately show local preview — no upload yet
    setState(() => _pickedFile = picked);
  }

  Future<void> _continue() async {
    if (_pickedFile == null) {
      // No photo selected — just proceed (no API call)
      ref.read(signupFlowProvider.notifier).clear();
      await routeByProfileCompletion(ref, context);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // Upload via existing repo method — same as profile_step1_screen
      await ref
          .read(profileRepositoryProvider)
          .uploadPhoto(_pickedFile!.path);
      if (!mounted) return;
      ref.read(signupFlowProvider.notifier).clear();
      await routeByProfileCompletion(ref, context);
    } on DioException catch (_) {
      // Upload fail pe bhi user ko trap mat karo
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't upload photo right now")),
      );
      ref.read(signupFlowProvider.notifier).clear();
      await routeByProfileCompletion(ref, context);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _skip() async {
    ref.read(signupFlowProvider.notifier).clear();
    await routeByProfileCompletion(ref, context);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHeadline =
        (_headline != null && _headline!.isNotEmpty) ? _headline! : 'Skillora Member';
    final effectiveName =
        _displayName.isEmpty ? 'Your Name' : _displayName;

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Progress — 1.0 = last onboarding step
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

              const Text(
                'Add a profile photo',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A photo helps clients recognise you.',
                style: TextStyle(
                  fontSize: 15,
                  color: _navy.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),

              // ---- PREVIEW CARD ----
              Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 260),
                  padding: const EdgeInsets.symmetric(
                      vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.3),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _navy.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Avatar + gold "+" badge — tap anywhere to pick
                      GestureDetector(
                        onTap: _isSubmitting ? null : _showPickSheet,
                        child: SizedBox(
                          width: 108,
                          height: 108,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 54,
                                backgroundColor: _navy,
                                backgroundImage: _avatarImage,
                                child: _avatarImage == null
                                    ? const Icon(Icons.person,
                                        color: Colors.white, size: 48)
                                    : null,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: _gold,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2.5),
                                  ),
                                  child: const Icon(Icons.add,
                                      color: Colors.white, size: 15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        effectiveName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _navy,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        effectiveHeadline,
                        style: TextStyle(
                          fontSize: 13,
                          color: _navy.withValues(alpha: 0.5),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // ---- CONTINUE ----
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    disabledBackgroundColor: _navy.withValues(alpha: 0.3),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: _isSubmitting ? null : _continue,
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
