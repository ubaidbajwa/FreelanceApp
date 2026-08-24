// Google reCAPTCHA v2 (checkbox + image challenge) — WebView mein render hota
// hai kyunke v2 widget web-only hai (Flutter ke liye Google ka koi native v2
// SDK nahi). HTML shim mein wahi standard div hai:
//   <div class="g-recaptcha" data-sitekey="..."></div>
// User checkbox tick karta hai (zaroorat pe image challenge solve karta hai),
// data-callback token JS-channel se Flutter tak aata hai, sheet band ho ke
// token return kar deti hai. Cancel/expire/error → null.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../../core/config/recaptcha_config.dart';

/// v2 checkbox sheet kholti hai. Complete hone pe captcha token return karta
/// hai; user ne dismiss kiya ya widget error aya to `null`.
Future<String?> showRecaptchaV2Sheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _RecaptchaV2Sheet(),
  );
}

class _RecaptchaV2Sheet extends StatefulWidget {
  const _RecaptchaV2Sheet();

  @override
  State<_RecaptchaV2Sheet> createState() => _RecaptchaV2SheetState();
}

class _RecaptchaV2SheetState extends State<_RecaptchaV2Sheet> {
  static const _navy = Color(0xFF0A1633);

  late final WebViewController _controller;
  bool _loading = true;

  // Standard v2 markup — data-callback token milte hi Captcha channel pe
  // postMessage karta hai. expired/error par empty message (→ null return).
  static String get _html => '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://www.google.com/recaptcha/api.js" async defer></script>
  <style>
    html, body { margin: 0; padding: 0; background: #FFFFFF; }
    .wrap { display: flex; justify-content: center; padding-top: 24px; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="g-recaptcha"
         data-sitekey="${RecaptchaConfig.siteKey}"
         data-callback="onCaptchaSuccess"
         data-expired-callback="onCaptchaExpired"
         data-error-callback="onCaptchaError"></div>
  </div>
  <script>
    function onCaptchaSuccess(token) { Captcha.postMessage(token); }
    function onCaptchaExpired() { Captcha.postMessage(''); }
    function onCaptchaError() { Captcha.postMessage(''); }
  </script>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'Captcha',
        onMessageReceived: (message) {
          if (!mounted) return;
          final token = message.message;
          // Empty = expired/error → sheet band, caller null-check pe error
          // dikhayega. Warna token wapas.
          Navigator.of(context).pop(token.isEmpty ? null : token);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      // baseUrl zaroori hai — v2 widget sirf admin console mein registered
      // domain pe render hota hai, warna "invalid domain" error deta hai.
      ..loadHtmlString(_html, baseUrl: RecaptchaConfig.hostDomain);
  }

  @override
  Widget build(BuildContext context) {
    // Image challenge ke liye kaafi jagah — 70% screen height.
    final height = MediaQuery.of(context).size.height * 0.7;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Text(
            'Verify you are human',
            style: TextStyle(
              color: _navy.withValues(alpha: 0.85),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFC0A062), // gold
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
