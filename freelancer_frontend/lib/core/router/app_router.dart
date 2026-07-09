import 'package:go_router/go_router.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';

// Saari app ke routes ek jagah — jaise backend mein endpoints ka map
final appRouter = GoRouter(
  initialLocation: '/splash', // app yahan se khulegi
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
  ],
);