import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/country_config.dart';
import '../../../../core/presentation/widgets/country_search_sheet.dart';
import '../../../auth/application/signup_flow_notifier.dart';
import '../../config/onboarding_flow.dart';

// Post-signup onboarding (LinkedIn-style) — step 1: location.
// OTP verify + auto-login ke BAAD chalti hai. Data SignupFlowNotifier mein.
class OnboardingLocationScreen extends ConsumerStatefulWidget {
  const OnboardingLocationScreen({super.key});

  @override
  ConsumerState<OnboardingLocationScreen> createState() =>
      _OnboardingLocationScreenState();
}

class _OnboardingLocationScreenState
    extends ConsumerState<OnboardingLocationScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _cityController = TextEditingController();
  CountryConfig? _country;

  @override
  void initState() {
    super.initState();
    // Wapas aaye to pehle ka data pre-fill — flow notifier source of truth hai
    final flow = ref.read(signupFlowProvider);
    if (flow.country != null) {
      _country = _findCountry(flow.country!);
    }
    _cityController.text = flow.city ?? '';
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  // Saved country name se config dhoondo (flag/dialCode dikhane ke liye)
  CountryConfig? _findCountry(String name) {
    for (final c in allCountries) {
      if (c.name == name) return c;
    }
    return null;
  }

  Future<void> _pickCountry() async {
    final picked = await showCountrySearchSheet(context);
    if (picked != null) setState(() => _country = picked);
  }

  void _continue() {
    final role = ref.read(signupFlowProvider).role;
    ref.read(signupFlowProvider.notifier).setLocation(
          country: _country!.name,
          city: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
        );
    context.go(OnboardingFlow.nextRouteAfter(OnboardingStep.location, role)!);
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _country != null;

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Slim gold progress — client step 1 of 4 (0.25), freelancer step 1 of 5 (0.5 legacy)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ref.watch(signupFlowProvider).role == 1 ? 0.25 : 0.5,
                  minHeight: 4,
                  color: _gold,
                  backgroundColor: _navy.withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(height: 36),

              const Text(
                'Add your location',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This helps us recommend the right jobs for you.',
                style: TextStyle(
                  fontSize: 15,
                  color: _navy.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // ---- COUNTRY* (tappable → search sheet) ----
              _fieldLabel('Country*'),
              const SizedBox(height: 8),
              _CountryField(country: _country, onTap: _pickCountry),
              const SizedBox(height: 20),

              // ---- CITY (optional plain field) ----
              _fieldLabel('City'),
              const SizedBox(height: 8),
              TextField(
                controller: _cityController,
                style: const TextStyle(color: _navy),
                decoration: _inputDecoration('Enter your city'),
              ),

              const Spacer(),

              // ---- CONTINUE ----
              _ContinueButton(
                enabled: canContinue,
                onPressed: _continue,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _navy,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _gold, width: 1.5),
        ),
      );
}

// Tappable country field — sheet kholta hai, selected value dikhata hai
class _CountryField extends StatelessWidget {
  final CountryConfig? country;
  final VoidCallback onTap;

  const _CountryField({required this.country, required this.onTap});

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final hasValue = country != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasValue ? _gold : _gold.withValues(alpha: 0.45),
              width: hasValue ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (hasValue) ...[
                Text(country!.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  hasValue ? country!.name : 'Select your country',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    color: hasValue ? _navy : _navy.withValues(alpha: 0.35),
                    fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: _navy.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// Full-width navy pill Continue — disabled tak jab tak required valid na ho
class _ContinueButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _ContinueButton({required this.enabled, required this.onPressed});

  static const _navy = Color(0xFF0A1633);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _navy,
          disabledBackgroundColor: _navy.withValues(alpha: 0.3),
          shape: const StadiumBorder(),
        ),
        onPressed: enabled ? onPressed : null,
        child: const Text(
          'Continue',
          style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 1),
        ),
      ),
    );
  }
}
