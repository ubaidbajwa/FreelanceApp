// Onboarding ka central flow definition — role ke hisab se branching yahan
// hoti hai, har screen mein nahi. Screens sirf nextRouteAfter() call karti
// hain aur result pe go() karte hain. Koi hardcoded route string screens mein
// nahi hona chahiye.
//
// Role values: 0 = freelancer, 1 = client (SignupFlowData.role se match karta)

enum OnboardingStep {
  location,
  experience,       // freelancer only
  availability,     // freelancer only
  jobPreferences,   // freelancer only
  aboutYou,         // client only
  hiringInterests,  // client only
  photo,
}

class OnboardingFlow {
  OnboardingFlow._(); // utility class — instantiate mat karo

  static const List<OnboardingStep> freelancerSteps = [
    OnboardingStep.location,
    OnboardingStep.experience,
    OnboardingStep.availability,
    OnboardingStep.jobPreferences,
    OnboardingStep.photo,
  ];

  static const List<OnboardingStep> clientSteps = [
    OnboardingStep.location,
    OnboardingStep.aboutYou,
    OnboardingStep.hiringInterests,
    OnboardingStep.photo,
  ];

  static List<OnboardingStep> stepsFor(int role) =>
      role == 1 ? clientSteps : freelancerSteps;

  static String routeOf(OnboardingStep step) => switch (step) {
        OnboardingStep.location => '/onboarding-location',
        OnboardingStep.experience => '/onboarding-experience',
        OnboardingStep.availability => '/onboarding-availability',
        OnboardingStep.jobPreferences => '/onboarding-job-preferences',
        OnboardingStep.aboutYou => '/onboarding-about-you',
        OnboardingStep.hiringInterests => '/onboarding-hiring-interests',
        OnboardingStep.photo => '/onboarding-photo',
      };

  // Agla step ka route return karo. Null agar current aakhri step hai —
  // photo screen terminal routing khud handle karti hai (routeByProfileCompletion).
  static String? nextRouteAfter(OnboardingStep current, int role) {
    final steps = stepsFor(role);
    final idx = steps.indexOf(current);
    if (idx == -1 || idx >= steps.length - 1) return null;
    return routeOf(steps[idx + 1]);
  }
}
