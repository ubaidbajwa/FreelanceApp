// Basic smoke test — app boot hoti hai aur splash screen dikhti hai
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/main.dart';

void main() {
  testWidgets('App boots and shows splash screen', (WidgetTester tester) async {
    // ProviderScope zaroori hai — app Riverpod use karti hai
    await tester.pumpWidget(const ProviderScope(child: FreelanceApp()));

    // Splash pe app ka naam dikhna chahiye
    expect(find.text('FreelanceApp'), findsOneWidget);

    // Splash ka 2-second timer flush karo warna test fail hota hai
    // (pending timer + navigation to onboarding)
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}
