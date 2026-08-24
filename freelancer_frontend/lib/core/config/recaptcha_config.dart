// reCAPTCHA v2 (checkbox + image challenge) configuration.
class RecaptchaConfig {
  RecaptchaConfig._();

  // TODO: move to env config (--dart-define / flavors) before production —
  // real site key ko source mein hardcode nahi rakhna. Yahan reCAPTCHA admin
  // console se banai hui v2 "I'm not a robot" Checkbox wali SITE KEY paste karo.
  static const String siteKey = '6LddBF4tAAAAAEMcY5v_ISfCd0Pe1s9JBCByCqAZ';

  // v2 widget sirf us domain pe render hota hai jo admin console mein site key
  // ke sath registered hai. WebView isi baseUrl ke sath HTML load karta hai —
  // apna registered domain yahan do (e.g. https://skillora.app).
  static const String hostDomain = 'https://localhost';

  // Placeholder/khaali key = reCAPTCHA abhi set nahi. Aisi surat mein screen
  // real check skip karke stub token bhejti hai — backend ka Captcha:Enabled=false
  // (Development) usay verify nahi karta, to signup flow end-to-end chalta hai.
  // Real key paste hote hi ye true ho jayega → asli v2 checkbox chalega.
  static bool get isConfigured =>
      siteKey.isNotEmpty && !siteKey.startsWith('YOUR_');

  // Dev bypass: localhost pe WebView reCAPTCHA kholna UX problem hai (user ko
  // do alag "I'm not a robot" prompts dikhte hain — custom card + WebView sheet).
  // Backend Captcha:Enabled=false to token verify waise bhi nahi hota.
  // Production mein hostDomain = real domain hoga → bypass nahi chalega.
  static bool get useDevBypass =>
      !isConfigured || hostDomain.contains('localhost');

  // Non-empty stub — backend validator ka "token required" rule pass karta hai
  // jabke dev mein verification disabled hai.
  static const String devBypassToken = 'dev-recaptcha-bypass';
}
