import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// Ek slide ka data — overline (chhota caps label) + title + description
class _Slide {
  final IconData icon;
  final String overline;
  final String title;
  final String desc;

  const _Slide(this.icon, this.overline, this.title, this.desc);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  // Luxury palette — poori screen pe sirf 3 rang, isse premium feel aati hai
  static const _bg = Color(0xFFFAFAF8); // soft ivory white
  static const _navy = Color(0xFF0A1633); // deep navy (splash se match)
  static const _gold = Color(0xFFC0A062); // muted gold accent

  static const List<_Slide> _slides = [
    _Slide(
      Icons.search_rounded,
      'SMART MATCHING',
      'Find work that\nfinds you',
      'An AI-powered job feed that shows opportunities matched to your skills.',
    ),
    _Slide(
      Icons.verified_user_rounded,
      'TRUSTED NETWORK',
      'Every user,\nverified',
      'Identity verification helps keep every user real, making hiring and earning safer.',
    ),
    _Slide(
      Icons.trending_up_rounded,
      'CAREER GROWTH',
      'Grow beyond\nthe gig',
      'Personalized learning roadmaps and courses help you build skills and move forward.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage == _slides.length - 1) {
      context.go('/setup'); // last slide → country + language setup
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: page number left, Skip right — dono subtle
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '0${_currentPage + 1} — 0${_slides.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: _navy.withValues(alpha: 0.35),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/setup'),
                    style: TextButton.styleFrom(
                      foregroundColor: _navy.withValues(alpha: 0.45),
                    ),
                    child: const Text('Skip',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon — thin gold ring, andar navy icon. Minimal, classy
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.45),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _navy.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(slide.icon, size: 38, color: _navy),
                        ),
                        const SizedBox(height: 44),

                        // Overline — chhota gold caps label, luxury typography ka touch
                        Text(
                          slide.overline,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3.5,
                            color: _gold,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Title — bara, deep navy, tight line height
                        Text(
                          slide.title,
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -0.5,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Description — muted, aaram se parhne wali
                        Text(
                          slide.desc,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.6,
                            color: _navy.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom bar: dots left, next button right
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dots — active dot gold, lambi pill shape
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        height: 6,
                        width: _currentPage == index ? 26 : 6,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? _gold
                              : _navy.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),

                  // Next — navy circle; last slide pe "Get Started" pill
                  isLast
                      ? FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 17),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Get Started',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                        )
                      : FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(18),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded,
                              size: 22),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
