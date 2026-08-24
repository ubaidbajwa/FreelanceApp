import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/presentation/widgets/app_logo.dart';
import '../../../../core/storage/saved_account_service.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../../profile/data/repositories/profile_repository.dart';

// ConsumerStatefulWidget — kyunke ref.read(secureStorageProvider) chahiye
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  static const _bg = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _scale = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    // 1 second baad decide karo: logged in? /home. Account yaad? /welcome-back. Naya? /signup
    Future.delayed(const Duration(milliseconds: 1000), _decideNextScreen);
  }

  Future<void> _decideNextScreen() async {
    final storage = ref.read(secureStorageProvider);
    // Refresh token = "yaad rakha hua login" — access token to jaldi expire hota hai
    final token = await storage.getRefreshToken();

    if (!mounted) return; // async ke baad zaroori — screen dispose ho chuki ho sakti hai

    if (token != null) {
      // Pehle se logged in — profile check karo: adhura? wizard. Poora? ghar.
      try {
        final profile =
            await ref.read(profileRepositoryProvider).getMyProfile();
        if (!mounted) return;
        if (profile.profileCompletionPercent < 50) {
          context.go('/profile-step1');
        } else {
          context.go('/home');
        }
      } catch (e) {
        if (!mounted) return;
        // Expired/dead session (401): AuthInterceptor pehle hi tokens clear kar
        // ke /login pe bhej chuka hai — yahan /home mat bhejo (warna zombie
        // authenticated state wapas aa jayega). Redirect ko rehne do.
        if (e is DioException && e.response?.statusCode == 401) return;
        // Transient (offline/5xx) — purana behavior: cached shell (home) jahan se
        // user retry kar sake.
        if (mounted) context.go('/home');
      }
    } else {
      // Logged out hai lekin account yaad hai? Welcome-back dikhao — warna naya user
      final saved = await ref.read(savedAccountServiceProvider).get();
      if (!mounted) return;
      if (saved != null) {
        context.go('/welcome-back');
      } else {
        context.go('/landing'); // bilkul naya user — landing (choice) screen
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 4),
              FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Column(
                    children: [
                      // Brand monogram — asli logo aane pe sirf AppLogo widget update hoga
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(116 * 0.28),
                          boxShadow: [
                            BoxShadow(
                              color: _navy.withValues(alpha: 0.18),
                              blurRadius: 32,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: const AppLogo(size: 116, showWordmark: false),
                      ),
                      const SizedBox(height: 34),
                      const Text(
                        'SKILLORA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 35,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'WORK GLOBAL · EARN ANYWHERE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _gold.withValues(alpha: 0.95),
                          letterSpacing: 2.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 3),
              FadeTransition(
                opacity: _fade,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return SizedBox(
                      width: 96,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: _controller.value,
                          backgroundColor: _navy.withValues(alpha: 0.12),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            _gold,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 46),
            ],
          ),
        ),
      ),
    );
  }
}
