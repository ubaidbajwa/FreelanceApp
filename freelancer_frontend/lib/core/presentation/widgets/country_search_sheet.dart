import 'package:flutter/material.dart';
import '../../constants/country_config.dart';

// Reusable country picker — search wala bottom sheet.
// Data source config-driven hai (`allCountries` from country_config.dart) —
// list yahan DOBARA nahi banti, sirf reuse hoti hai. Old F1 onboarding wala
// pattern, ab navy/gold luxury theme mein.
//
// Use: `final country = await showCountrySearchSheet(context);`
// null = user ne bina select kiye sheet band kar di.

const _ivory = Color(0xFFFAFAF8);
const _navy = Color(0xFF0A1633);
const _gold = Color(0xFFC0A062);

Future<CountryConfig?> showCountrySearchSheet(BuildContext context) {
  return showModalBottomSheet<CountryConfig>(
    context: context,
    isScrollControlled: true, // keyboard khulne pe sheet upar aa jaye
    backgroundColor: _ivory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CountrySearchSheet(),
  );
}

class _CountrySearchSheet extends StatefulWidget {
  const _CountrySearchSheet();

  @override
  State<_CountrySearchSheet> createState() => _CountrySearchSheetState();
}

class _CountrySearchSheetState extends State<_CountrySearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    // naam, ISO (pk, us) ya dial code (+92) — teeno se search
    final filtered = allCountries.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.isoCode.toLowerCase().contains(q) ||
          c.dialCode.contains(q);
    }).toList();

    return Padding(
      // Keyboard ki height jitna neeche se padding — fields chhupti nahi
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Country',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(color: _navy),
                decoration: InputDecoration(
                  hintText: 'Search country or code...',
                  prefixIcon: const Icon(Icons.search, color: _navy),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _gold, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Results
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No results',
                        style: TextStyle(color: _navy.withValues(alpha: 0.5)),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final c = filtered[index];
                        return ListTile(
                          leading:
                              Text(c.flag, style: const TextStyle(fontSize: 26)),
                          title: Text(
                            c.name,
                            style: const TextStyle(color: _navy),
                          ),
                          trailing: Text(
                            c.dialCode,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.5),
                            ),
                          ),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
