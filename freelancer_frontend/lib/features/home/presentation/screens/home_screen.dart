import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../profile/data/repositories/profile_repository.dart';

// PLACEHOLDER — F4 mein proper home screen banegi. Abhi sirf:
// profile completion % + wizard pe wapis jane ka rasta.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int? _completionPercent; // null = abhi load nahi hua

  @override
  void initState() {
    super.initState();
    _loadPercent();
  }

  Future<void> _loadPercent() async {
    try {
      final profile = await ref.read(profileRepositoryProvider).getMyProfile();
      if (!mounted) return;
      setState(() => _completionPercent = profile.profileCompletionPercent);
    } catch (_) {} // fail ho to button percent ke baghair dikhega
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // TEMPORARY logout — sirf tokens clear (saved account bacha rehta hai → Welcome Back).
          // TODO(Settings phase): proper logout — backend /api/auth/logout call + refresh token revoke.
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF0A1633)),
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(secureStorageProvider).clearTokens();
              if (context.mounted) context.go('/welcome-back'); // pehchan bachi hai
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Home — logged in!',
              style: TextStyle(
                color: Color(0xFF0A1633),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // 100% wale ko wizard ka rasta dikhane ki zaroorat nahi
            if (_completionPercent == null || _completionPercent! < 100)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  // thin gold border — CLAUDE.md style rule
                  side: const BorderSide(color: Color(0xFFC0A062), width: 1.2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                onPressed: () => context.go('/profile-step1'),
                child: Text(
                  _completionPercent == null
                      ? 'Complete your profile'
                      : 'Complete your profile ($_completionPercent%)',
                  style: const TextStyle(color: Color(0xFF0A1633)),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                side: const BorderSide(color: Color(0xFFC0A062), width: 1.2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () => context.push('/connections'),
              child: const Text(
                'My Connections',
                style: TextStyle(color: Color(0xFF0A1633)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
