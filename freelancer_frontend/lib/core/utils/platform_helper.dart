import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

enum SocialProvider { google, apple, microsoft }

// Join (signup) screen — LinkedIn style: kam options
// kIsWeb HAMESHA pehle (dart:io web pe available nahi — Platform.* crash karega)
List<SocialProvider> socialProvidersForJoin() {
  if (kIsWeb) return [SocialProvider.google, SocialProvider.microsoft];
  if (Platform.isIOS) return [SocialProvider.google, SocialProvider.apple];
  return [SocialProvider.google]; // Android/others
}

// Sign in screen — zyada options (Apple har platform pe)
List<SocialProvider> socialProvidersForSignIn() {
  if (kIsWeb) {
    return [
      SocialProvider.google,
      SocialProvider.apple,
      SocialProvider.microsoft,
    ];
  }
  if (Platform.isIOS) return [SocialProvider.google, SocialProvider.apple];
  return [SocialProvider.google, SocialProvider.apple]; // Android/others
}
