import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/models/profile_model.dart';
import '../../data/repositories/profile_repository.dart';
import '../widgets/step_progress_bar.dart';

class ProfileStep1Screen extends ConsumerStatefulWidget {
  const ProfileStep1Screen({super.key});

  @override
  ConsumerState<ProfileStep1Screen> createState() => _ProfileStep1ScreenState();
}

class _ProfileStep1ScreenState extends ConsumerState<ProfileStep1Screen> {
  final _nameController = TextEditingController();
  final _headlineController = TextEditingController();
  final _bioController = TextEditingController();

  String? _photoUrl;        // backend se aayi photo ka URL
  bool _isLoading = false;  // Continue button ka spinner
  bool _isUploading = false; // photo upload ka spinner

  @override
  void initState() {
    super.initState();
    _loadProfile(); // screen khulte hi profile lao (pre-fill ke liye)
  }

  @override
  void dispose() {
    _nameController.dispose();
    _headlineController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // Backend se profile la kar fields pre-fill karo
  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      if (!mounted) return; // async ke baad — yaad hai kyun
      setState(() {
        _nameController.text = profile.displayName ?? '';
        _headlineController.text = profile.headline ?? '';
        _bioController.text = profile.bio ?? '';
        _photoUrl = profile.profilePhotoUrl;
      });
    } catch (_) {
      // pre-fill fail ho to bhi screen chalti rahe — par chupke se nahi,
      // user ko batao ke data load nahi hua (pehle ye silently kha jata tha)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load your profile. Check your connection.'),
        ),
      );
    }
  }

  // Photo choose + upload
  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    // gallery kholo — user cancel kare to photo null hoga
    final photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo == null) return; // user ne cancel kiya — kuch mat karo

    setState(() => _isUploading = true);
    try {
      final updated =
          await ref.read(profileRepositoryProvider).uploadPhoto(photo.path);
      if (!mounted) return;
      setState(() => _photoUrl = updated.profilePhotoUrl);
    } on DioException catch (e) {
      if (!mounted) return;
      final detail = e.response?.data?['detail'] ?? 'Photo upload failed';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail.toString())));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // Continue — teen fields save karo
  Future<void> _handleContinue() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            UpdateProfileRequest(
              displayName: _nameController.text.trim(),
              headline: _headlineController.text.trim(),
              bio: _bioController.text.trim(),
            ),
          );
      if (!mounted) return;
      context.go('/profile-step2'); // placeholder — Step 2 F3.3 mein banega
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
      backgroundColor: const Color(0xFFFAFAF8), // ivory
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Skip — top right
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: () => context.go('/profile-step2'),
                  child: const Text('Skip for now'),
                ),
              ),
              // Gold overline — luxury style
              const Text(
                'SET UP YOUR PROFILE',
                style: TextStyle(
                  color: Color(0xFFC0A062), // gold
                  letterSpacing: 3,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Step 1 of 3',
                style: TextStyle(
                  color: Color(0xFF0A1633), // navy
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const StepProgressBar(currentStep: 1),
              const SizedBox(height: 32),

              // Photo avatar — center, tap to pick
              Center(
                child: GestureDetector(
                  onTap: _isUploading ? null : _pickPhoto,
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: const Color(0xFF0A1633),
                    // photo hai to dikhao, nahi to camera icon
                    backgroundImage:
                        _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                    child: _isUploading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : (_photoUrl == null
                            ? const Icon(Icons.add_a_photo,
                                color: Colors.white, size: 32)
                            : null),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _headlineController,
                decoration: const InputDecoration(
                  labelText: 'Headline',
                  hintText: 'e.g. Flutter Developer | ASP.NET Expert',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bioController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell clients about yourself...',
                ),
              ),
              const SizedBox(height: 32),

              // Navy pill Continue button
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
                          height: 20,
                          width: 20,
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