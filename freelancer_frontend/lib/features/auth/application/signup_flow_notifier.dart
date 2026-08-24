import 'package:flutter_riverpod/flutter_riverpod.dart';

// Signup ke saare steps ka data ek jagah — screens yahan likhte hain,
// aur register call security-check ke baad hoti hai (login-time submit).
// Riverpod 3 Notifier pattern (StateProvider legacy hai).
class SignupFlowData {
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final int role; // 0 = freelancer, 1 = client

  final String? country;
  final String? city;

  // Experience/education — aage ki slices ke liye (abhi sirf hold karte hain)
  final String? jobTitle;
  final String? company;
  final bool? isStudent;
  final String? school;
  final String? degree;
  final String? fieldOfStudy;
  final int? startYear;

  // Availability step — 0=Actively looking, 1=Open to offers, 2=Not looking
  final int? availabilityStatus;

  // Job preferences step
  final List<String>? desiredJobTitles;     // max 5
  final List<String>? desiredJobLocations;  // max 5
  final int? workPreference;                // 0=Remote 1=OnSite 2=Hybrid

  // Client "About you" step — 0=Individual, 1=Business
  final int? clientType;
  final String? businessName;

  // Client "Hiring interests" step — max 5 categories
  final List<String>? hiringInterests;
  final int? hiringType; // 0=OneTimeProject 1=OngoingWork

  const SignupFlowData({
    this.email = '',
    this.password = '',
    this.firstName = '',
    this.lastName = '',
    this.role = 0,
    this.country,
    this.city,
    this.jobTitle,
    this.company,
    this.isStudent,
    this.school,
    this.degree,
    this.fieldOfStudy,
    this.startYear,
    this.availabilityStatus,
    this.desiredJobTitles,
    this.desiredJobLocations,
    this.workPreference,
    this.clientType,
    this.businessName,
    this.hiringInterests,
    this.hiringType,
  });

  // OTP screen isse decide karti hai ke auto-login karna hai ya nahi
  bool get hasPassword => password.isNotEmpty;

  SignupFlowData copyWith({
    String? email,
    String? password,
    String? firstName,
    String? lastName,
    int? role,
    String? country,
    String? city,
    String? jobTitle,
    String? company,
    bool? isStudent,
    String? school,
    String? degree,
    String? fieldOfStudy,
    int? startYear,
    int? availabilityStatus,
    List<String>? desiredJobTitles,
    List<String>? desiredJobLocations,
    int? workPreference,
    int? clientType,
    String? businessName,
    bool clearBusinessName = false, // clearError wala pattern — explicitly null set karne ke liye
    List<String>? hiringInterests,
    int? hiringType,
  }) =>
      SignupFlowData(
        email: email ?? this.email,
        password: password ?? this.password,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        role: role ?? this.role,
        country: country ?? this.country,
        city: city ?? this.city,
        jobTitle: jobTitle ?? this.jobTitle,
        company: company ?? this.company,
        isStudent: isStudent ?? this.isStudent,
        school: school ?? this.school,
        degree: degree ?? this.degree,
        fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
        startYear: startYear ?? this.startYear,
        availabilityStatus: availabilityStatus ?? this.availabilityStatus,
        desiredJobTitles: desiredJobTitles ?? this.desiredJobTitles,
        desiredJobLocations: desiredJobLocations ?? this.desiredJobLocations,
        workPreference: workPreference ?? this.workPreference,
        clientType: clientType ?? this.clientType,
        businessName: clearBusinessName ? null : (businessName ?? this.businessName),
        hiringInterests: hiringInterests ?? this.hiringInterests,
        hiringType: hiringType ?? this.hiringType,
      );
}

class SignupFlowNotifier extends Notifier<SignupFlowData> {
  @override
  SignupFlowData build() => const SignupFlowData();

  // Join screen ke naam-step pe call hota hai
  void setBasics({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required int role,
  }) {
    state = state.copyWith(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      role: role,
    );
  }

  void setLocation({String? country, String? city}) {
    state = state.copyWith(country: country, city: city);
  }

  void setExperience({
    String? jobTitle,
    String? company,
    bool? isStudent,
    String? school,
    String? degree,
    String? fieldOfStudy,
    int? startYear,
  }) {
    state = state.copyWith(
      jobTitle: jobTitle,
      company: company,
      isStudent: isStudent,
      school: school,
      degree: degree,
      fieldOfStudy: fieldOfStudy,
      startYear: startYear,
    );
  }

  // Availability step — 0=Actively looking, 1=Open to offers, 2=Not looking
  void setAvailabilityStatus(int status) {
    state = state.copyWith(availabilityStatus: status);
  }

  // Job preferences step
  void setJobPreferences({
    List<String>? desiredJobTitles,
    List<String>? desiredJobLocations,
    int? workPreference,
  }) {
    state = state.copyWith(
      desiredJobTitles: desiredJobTitles,
      desiredJobLocations: desiredJobLocations,
      workPreference: workPreference,
    );
  }

  // Client "About you" step — Individual (0) ka businessName hamesha null hota hai
  void setClientInfo({required int clientType, String? businessName}) {
    state = state.copyWith(
      clientType: clientType,
      businessName: clientType == 1 ? businessName : null,
      clearBusinessName: clientType != 1,
    );
  }

  // Client "Hiring interests" step — max 5 categories + optional type
  void setHiringInterests({List<String>? hiringInterests, int? hiringType}) {
    state = state.copyWith(
      hiringInterests: hiringInterests,
      hiringType: hiringType,
    );
  }

  void clear() => state = const SignupFlowData();
}

final signupFlowProvider =
    NotifierProvider<SignupFlowNotifier, SignupFlowData>(SignupFlowNotifier.new);
