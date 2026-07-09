import 'package:go_router/go_router.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/onboarding/presentation/screens/setup_screen.dart';
import '../../features/onboarding/presentation/screens/role_selection_screen.dart';
import 'package:flutter/material.dart';

// Saari app ke routes ek jagah — jaise backend mein endpoints ka map
final appRouter = GoRouter(
  initialLocation: '/splash', // app yahan se khulegi
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
    // Country + Language — dono ek hi setup screen pe
    GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
    GoRoute( path: '/role-selection', builder: (context, state) => const RoleSelectionScreen(),),
GoRoute( path: '/auth-placeholder', builder: (context, state) => const Scaffold(   body: Center(child: Text('Sign Up / Sign In — Phase F2 🔐')),
  ),
),
  ],
);
