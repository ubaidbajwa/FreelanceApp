import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0; // kaunsa slide chal raha hai

  // Slides ka data — alag list mein rakha, UI se separate (clean habit)
  final List<Map<String, dynamic>> _slides = [
    {
      'icon': Icons.search_rounded,
      'title': 'Find Jobs That Match You',
      'desc': 'AI-powered job feed — sirf wohi jobs jo aapki skills se match karein.',
    },
    {
      'icon': Icons.verified_user_rounded,
      'title': 'Verified & Trusted',
      'desc': 'Identity verification se har user real hai — safe hiring, safe earning.',
    },
    {
      'icon': Icons.trending_up_rounded,
      'title': 'Grow Your Career',
      'desc': 'Personalized learning roadmaps aur courses — skills seekho, aage barho.',
    },
  ];

  @override
  void dispose() {
    _controller.dispose(); // memory clean karo jab screen destroy ho
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button — top right
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => context.go('/country-selection'),
                child: const Text('Skip'),
              ),
            ),

            // Slides — Expanded matlab bachi hui saari jagah le lo
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index); // page badla → UI update
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(slide['icon'], size: 100, color: Colors.indigo),
                        const SizedBox(height: 32),
                        Text(
                          slide['title'],
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          slide['desc'],
                          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 24 : 8, // active dot lamba
                  decoration: BoxDecoration(
                    color: _currentPage == index ? Colors.indigo : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),

            // Next / Get Started button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity, // full width button
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    if (_currentPage == _slides.length - 1) {
                      context.go('/country-selection'); // last slide → aage
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: Text(
                    _currentPage == _slides.length - 1 ? 'Get Started' : 'Next',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}