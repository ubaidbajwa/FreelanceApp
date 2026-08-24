import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size; // monogram box ka size
  final bool showWordmark; // neeche app name dikhana hai ya nahi
  const AppLogo({super.key, this.size = 72, this.showWordmark = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1633), // navy
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          alignment: Alignment.center,
          child: Text(
            'S', // Skillora monogram
            style: TextStyle(
              color: const Color(0xFFC0A062), // gold
              fontSize: size * 0.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(height: 12),
          const Text(
            'SKILLORA',
            style: TextStyle(
              color: Color(0xFF0A1633),
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ],
    );
  }
}
