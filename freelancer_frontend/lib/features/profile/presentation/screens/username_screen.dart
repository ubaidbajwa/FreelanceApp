import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../data/repositories/profile_repository.dart';

class UsernameScreen extends ConsumerStatefulWidget {
  const UsernameScreen({super.key});

  @override
  ConsumerState<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends ConsumerState<UsernameScreen> {
  final _usernameController = TextEditingController();
  Timer? _debounce;

  // Backend ka exact regex — invalid format pe API call hi mat karo
  // (warna backend 400 deta aur user ko koi feedback nahi milta)
  static final _usernameRegex = RegExp(r'^[a-z][a-z0-9_]{2,29}$');

  bool? _isAvailable;      // null = abhi check nahi hua
  bool _isChecking = false;
  bool _isClaiming = false;
  String? _formatError;    // null = format theek hai

  @override
  void dispose() {
    _usernameController.dispose();
    _debounce?.cancel(); // pending timer bhi saaf karo — warna disposed
    super.dispose();     // state pe _checkAvailability chal sakta hai
  }

  void _onUsernameChanged(String value) {
    _debounce?.cancel(); // purana timer khatam (naya letter aya!)

    final username = value.trim();
    // 3 se chhota check hi mat karo — backend regex min 3 chars mangta hai
    if (username.length < 3) {
      setState(() {
        _isAvailable = null;
        _formatError = null; // abhi type kar raha hai — error mat dikhao
      });
      return;
    }

    // Format galat (uppercase, digit se start, space...) — instant feedback,
    // API call bachao
    if (!_usernameRegex.hasMatch(username)) {
      setState(() {
        _isAvailable = null;
        _formatError =
            'Lowercase letters, digits, underscore — start with a letter';
      });
      return;
    }

    // setState yahan bhi — preview text ('skillora.com/@...') live update ho
    setState(() => _formatError = null);
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _checkAvailability(username); // 500ms khamoshi ke baad hi ye chalega
    });
  }

  Future<void> _checkAvailability(String username) async {
    setState(() => _isChecking = true);
    try {
      final available =
          await ref.read(profileRepositoryProvider).isUsernameAvailable(username);
      if (!mounted) return;
      // Stale response guard — jawab aane tak user aage type kar chuka ho
      // to ye purana result hai, ignore karo (debounce ke bawajood ho sakta hai)
      if (username != _usernameController.text.trim()) return;
      setState(() => _isAvailable = available);
    } on DioException catch (_) {
      // network/server error pe availability ka dawa mat karo
      if (!mounted) return;
      setState(() => _isAvailable = null);
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _handleClaim() async {
    final username = _usernameController.text.trim();
    setState(() => _isClaiming = true);
    try {
      await ref.read(profileRepositoryProvider).claimUsername(username);
      if (!mounted) return;
      context.go('/home');
    } on DioException catch (e) {
      // 409 aa sakta hai — race condition (do banday same second!)
      if (!mounted) return;
      final detail = e.response?.data?['detail'] ?? 'Something went wrong';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(detail.toString())));
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  // Suffix icon — checking spinner / green check / red cross
  Widget? _buildSuffixIcon() {
    if (_isChecking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          height: 16, width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_isAvailable == true) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (_isAvailable == false) {
      return const Icon(Icons.cancel, color: Colors.red);
    }
    return null; // null state = kuch mat dikhao
  }

  @override
  Widget build(BuildContext context) {
    final username = _usernameController.text.trim();

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
                  onPressed: () => context.go('/home'),
                  child: const Text('Skip for now'),
                ),
              ),
              const Text(
                'CLAIM YOUR USERNAME',
                style: TextStyle(
                  color: Color(0xFFC0A062),
                  letterSpacing: 3,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Pick a unique handle',
                style: TextStyle(
                  color: Color(0xFF0A1633),
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _usernameController,
                onChanged: _onUsernameChanged,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  hintText: 'e.g. ubaid_dev',
                  errorText: _formatError,
                  suffixIcon: _buildSuffixIcon(),
                ),
              ),
              const SizedBox(height: 12),

              // Live preview — profile ka public URL aisa dikhega
              Text(
                username.isEmpty
                    ? 'skillora.com/@username'
                    : 'skillora.com/@$username',
                style: TextStyle(
                  color: const Color(0xFF0A1633).withValues(alpha: 0.55),
                  fontSize: 13,
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A1633),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  // enabled SIRF jab available confirm ho (aur claim na chal raha ho)
                  onPressed: (_isAvailable == true && !_isClaiming)
                      ? _handleClaim
                      : null,
                  child: _isClaiming
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Claim',
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
