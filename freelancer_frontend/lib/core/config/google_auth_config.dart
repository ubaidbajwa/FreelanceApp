// Google Sign-In configuration.
class GoogleAuthConfig {
  GoogleAuthConfig._();

  // ⚠️ Yahan WEB client ID jati hai, Android wali NAHI.
  // serverClientId = jiske liye idToken banega = wohi audience jo backend
  // verify karta hai (backend ki ClientIds list mein Web + Android dono hone
  // chahiye, Flutter serverClientId mein sirf Web wali deni hai).
  //
  // TODO: move to env config (--dart-define / flavors) before production.
  static const String serverClientId =
      '28326512775-jfm0a2k06me4laes03viuood6cfiuig3.apps.googleusercontent.com';
}
