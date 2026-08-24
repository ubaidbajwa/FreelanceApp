import 'package:flutter/material.dart';

// Reusable progress bar — 3 dots/lines, current step highlighted
class StepProgressBar extends StatelessWidget {
  final int currentStep; // 1, 2, ya 3
  const StepProgressBar({super.key, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (index) {
        final stepNumber = index + 1;
        final isDone = stepNumber <= currentStep;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              // done = gold, baqi = halka grey
              color: isDone ? const Color(0xFFC0A062) : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
