import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/country_config.dart';
import '../../../core/constants/languages.dart';
import '../../../core/constants/user_role.dart';

// Riverpod 3 mein StateProvider legacy ho gaya hai — ab Notifier use hota hai
// Notifier = state + usko badalne ke methods, ek class mein (jaise C# mein service class)

// Selected country — poori app mein accessible (phone code + KYC isi se chalega)
class SelectedCountryNotifier extends Notifier<CountryConfig?> {
  @override
  CountryConfig? build() => null; // shuru mein kuch select nahi

  void select(CountryConfig country) => state = country;
}

final selectedCountryProvider =
    NotifierProvider<SelectedCountryNotifier, CountryConfig?>(
      SelectedCountryNotifier.new,
    );

// Selected language — country se bilkul alag selection
class SelectedLanguageNotifier extends Notifier<LanguageOption?> {
  @override
  LanguageOption? build() => null;

  void select(LanguageOption language) => state = language;
}

final selectedLanguageProvider =
    NotifierProvider<SelectedLanguageNotifier, LanguageOption?>(
      SelectedLanguageNotifier.new,
    );

// Selected role — Notifier pattern (Riverpod 3)
class SelectedRoleNotifier extends Notifier<UserRole?> {
  @override
  UserRole? build() => null;

  void select(UserRole role) => state = role;
}

final selectedRoleProvider = NotifierProvider<SelectedRoleNotifier, UserRole?>(
  SelectedRoleNotifier.new,
);
