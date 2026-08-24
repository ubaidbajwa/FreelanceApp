import 'package:go_router/go_router.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/landing_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/security_check_screen.dart';
import '../../features/auth/presentation/screens/welcome_back_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_location_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_experience_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_availability_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_job_preferences_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_about_you_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_hiring_interests_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_photo_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/reset_password_screen.dart';
import '../../features/onboarding/presentation/screens/signup_screen.dart';
import '../../features/onboarding/presentation/screens/verify_email_screen.dart';
import '../../features/profile/presentation/screens/profile_step1_screen.dart';
import '../../features/profile/presentation/screens/profile_step2_screen.dart';
import '../../features/profile/presentation/screens/profile_step3_screen.dart';
import '../../features/profile/presentation/screens/username_screen.dart';
import '../../features/connections/presentation/screens/invitations_screen.dart';
import '../../features/connections/presentation/screens/my_connections_screen.dart';
import '../../features/people/presentation/screens/people_screen.dart';
import '../../features/network/presentation/screens/suggestions_screen.dart';
import '../../features/network/presentation/screens/follow_suggestions_screen.dart';
import '../../features/network/presentation/screens/connection_privacy_screen.dart';
// Shell + tabs
import '../../features/shell/presentation/screens/app_shell.dart';
import '../../features/shell/presentation/screens/home_tab.dart';
import '../../features/network/presentation/screens/my_network_home_screen.dart';
import '../../features/shell/presentation/screens/jobs_tab.dart';
import '../../features/messaging/presentation/screens/conversations_screen.dart';
import '../../features/messaging/presentation/screens/chat_screen.dart';
import '../../features/messaging/data/models/messaging_models.dart';
import '../../features/shell/presentation/screens/more_tab.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    // ── Auth / onboarding (outside shell — full screen) ──────────────────────
    GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
    GoRoute(path: '/landing', builder: (c, s) => const LandingScreen()),
    GoRoute(path: '/signup', builder: (c, s) => const SignupScreen()),
    GoRoute(path: '/security-check', builder: (c, s) => const SecurityCheckScreen()),
    GoRoute(path: '/onboarding-location', builder: (c, s) => const OnboardingLocationScreen()),
    GoRoute(path: '/onboarding-experience', builder: (c, s) => const OnboardingExperienceScreen()),
    GoRoute(path: '/onboarding-availability', builder: (c, s) => const OnboardingAvailabilityScreen()),
    GoRoute(path: '/onboarding-job-preferences', builder: (c, s) => const OnboardingJobPreferencesScreen()),
    GoRoute(path: '/onboarding-about-you', builder: (c, s) => const OnboardingAboutYouScreen()),
    GoRoute(path: '/onboarding-hiring-interests', builder: (c, s) => const OnboardingHiringInterestsScreen()),
    GoRoute(path: '/onboarding-photo', builder: (c, s) => const OnboardingPhotoScreen()),
    GoRoute(
      path: '/verify-email',
      builder: (c, s) {
        final email = s.extra as String?;
        if (email == null || email.isEmpty) return const SignupScreen();
        return VerifyEmailScreen(email: email);
      },
    ),
    GoRoute(path: '/welcome-back', builder: (c, s) => const WelcomeBackScreen()),
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
    GoRoute(
      path: '/reset-password',
      builder: (c, s) {
        final email = s.extra as String?;
        if (email == null || email.isEmpty) return const ForgotPasswordScreen();
        return ResetPasswordScreen(email: email);
      },
    ),
    // ── Profile wizard (outside shell — full screen flow) ────────────────────
    GoRoute(path: '/profile-step1', builder: (c, s) => const ProfileStep1Screen()),
    GoRoute(path: '/profile-step2', builder: (c, s) => const ProfileStep2Screen()),
    GoRoute(path: '/profile-step3', builder: (c, s) => const ProfileStep3Screen()),
    GoRoute(path: '/username', builder: (c, s) => const UsernameScreen()),
    // ── Connections (outside shell — pushed over it from network tab) ─────────
    GoRoute(path: '/connections', builder: (c, s) => const MyConnectionsScreen()),
    GoRoute(
      path: '/connections/invitations',
      builder: (c, s) => const InvitationsScreen(),
    ),
    GoRoute(path: '/people', builder: (c, s) => const PeopleScreen()),
    // ── Chat (outside shell — pushed over the Messages tab, keeps its state) ──
    // F-M2 asli chat screen banayega; abhi placeholder isi route/args ko use karta.
    GoRoute(
      path: '/chat/:conversationId',
      builder: (c, s) {
        final id = s.pathParameters['conversationId']!;
        // F-M2: extra ab poori ConversationSummary hai (status/isRequest/otherUser).
        // Cold deep-link / push isay null bhej sakta hai — screen us par depend nahi karti.
        final summary = s.extra as ConversationSummary?;
        return ChatScreen(conversationId: id, summary: summary);
      },
    ),
    GoRoute(path: '/suggestions', builder: (c, s) => const SuggestionsScreen()),
    GoRoute(
      path: '/follow-suggestions',
      builder: (c, s) => const FollowSuggestionsScreen(),
    ),
    GoRoute(
      path: '/connection-privacy',
      builder: (c, s) => const ConnectionPrivacyScreen(),
    ),

    // ── Main shell — StatefulShellRoute keeps each tab's stack alive ──────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        // Tab 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/home', builder: (c, s) => const HomeTab()),
          ],
        ),
        // Tab 1: My Network — LinkedIn-style home screen (F-N1)
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/network', builder: (c, s) => const MyNetworkHomeScreen()),
          ],
        ),
        // Tab 2: Jobs
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/jobs', builder: (c, s) => const JobsTab()),
          ],
        ),
        // Tab 3: Messages
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/messages', builder: (c, s) => const ConversationsScreen()),
          ],
        ),
        // Tab 4: More
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/more', builder: (c, s) => const MoreTab()),
          ],
        ),
      ],
    ),
  ],
);
