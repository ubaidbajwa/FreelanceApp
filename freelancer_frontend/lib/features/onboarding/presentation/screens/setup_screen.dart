import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/country_config.dart';
import '../../../../core/constants/languages.dart';
import '../../providers/onboarding_providers.dart';

// Country + Language — dono EK screen pe, dropdown-style selector cards
// Tap karo → search wala bottom sheet khulta hai → select karo → card pe likha aa jata hai
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  static const _accent = Color(0xFF3949AB);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final country = ref.watch(selectedCountryProvider);
    final language = ref.watch(selectedLanguageProvider);
    final bothSelected = country != null && language != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // Header
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.public_rounded,
                    size: 32, color: _accent),
              ),
              const SizedBox(height: 24),
              Text(
                "Let's set you up",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[900],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your country and language to set your phone code and verification details.',
                style: TextStyle(
                    fontSize: 15, height: 1.5, color: Colors.grey[600]),
              ),
              const SizedBox(height: 36),

              // ---- COUNTRY selector card ----
              _SelectorCard(
                label: 'Country',
                icon: Icons.flag_rounded,
                // Select hone ke baad: flag + naam + dial code card pe dikhta hai
                value: country == null
                    ? null
                    : '${country.flag}  ${country.name}  (${country.dialCode})',
                hint: 'Select your country',
                onTap: () => _pickCountry(context, ref),
              ),
              const SizedBox(height: 16),

              // ---- LANGUAGE selector card ----
              _SelectorCard(
                label: 'Language',
                icon: Icons.translate_rounded,
                value: language == null
                    ? null
                    : '${language.name}  ·  ${language.nativeName}',
                hint: 'Select your language',
                onTap: () => _pickLanguage(context, ref),
              ),

              const Spacer(),

              // Continue — dono select hon tab hi enable
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: !bothSelected
                      ? null
                      : () {
                          // TODO: agla step — role selection / phone verification
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              behavior: SnackBarBehavior.floating,
                              content: Text(
                                '${country.flag} ${country.name} + ${language.name} saved — next: phone (${country.dialCode})',
                              ),
                            ),
                          );
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Continue',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // Country picker — search ke saath bottom sheet
  void _pickCountry(BuildContext context, WidgetRef ref) {
    _showSearchPicker<CountryConfig>(
      context: context,
      title: 'Select Country',
      items: allCountries,
      // naam, ISO (pk, uae) ya dial code (+92) — teeno se search
      matches: (c, q) =>
          c.name.toLowerCase().contains(q) ||
          c.isoCode.toLowerCase().contains(q) ||
          c.dialCode.contains(q),
      itemBuilder: (c) => ListTile(
        leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
        title: Text(c.name),
        trailing: Text(c.dialCode,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600])),
      ),
      onSelected: (c) =>
          ref.read(selectedCountryProvider.notifier).select(c),
    );
  }

  // Language picker — same style ka bottom sheet
  void _pickLanguage(BuildContext context, WidgetRef ref) {
    _showSearchPicker<LanguageOption>(
      context: context,
      title: 'Select Language',
      items: allLanguages,
      matches: (l, q) =>
          l.name.toLowerCase().contains(q) ||
          l.nativeName.toLowerCase().contains(q),
      itemBuilder: (l) => ListTile(
        leading: const Icon(Icons.language_rounded, color: _accent),
        title: Text(l.name),
        trailing: Text(l.nativeName,
            style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      ),
      onSelected: (l) =>
          ref.read(selectedLanguageProvider.notifier).select(l),
    );
  }
}

// ---------- Reusable widgets / helpers ----------

// Dropdown-jaisa selector card — label upar, selected value neeche
class _SelectorCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value; // null = abhi kuch select nahi hua
  final String hint;
  final VoidCallback onTap;

  const _SelectorCard({
    required this.label,
    required this.icon,
    required this.value,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasValue
                  ? SetupScreen._accent.withValues(alpha: 0.5)
                  : Colors.grey.shade300,
              width: hasValue ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: hasValue ? SetupScreen._accent : Colors.grey[400]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[500],
                            letterSpacing: 0.5)),
                    const SizedBox(height: 3),
                    Text(
                      value ?? hint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            hasValue ? FontWeight.w600 : FontWeight.normal,
                        color:
                            hasValue ? Colors.grey[900] : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey[500]),
            ],
          ),
        ),
      ),
    );
  }
}

// Generic search picker — country aur language dono ke liye ek hi code
void _showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required bool Function(T item, String query) matches,
  required ListTile Function(T item) itemBuilder,
  required void Function(T item) onSelected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true, // keyboard khulne pe sheet upar aa jaye
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      String query = '';
      // StatefulBuilder — sirf sheet ke andar ka setState, poori screen nahi
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final q = query.toLowerCase().trim();
          final filtered =
              items.where((item) => matches(item, q)).toList();

          return Padding(
            // Keyboard ki height jitna neeche se padding — fields chhupti nahi
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),

                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: false,
                      onChanged: (value) =>
                          setSheetState(() => query = value),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Results
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text('No results',
                                style: TextStyle(color: Colors.grey[500])),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final tile = itemBuilder(item);
                              return ListTile(
                                leading: tile.leading,
                                title: tile.title,
                                trailing: tile.trailing,
                                onTap: () {
                                  onSelected(item);
                                  Navigator.pop(sheetContext);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
