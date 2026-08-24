import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/storage/saved_account_service.dart';
import '../../../../core/presentation/widgets/app_logo.dart'; // path apne project ke hisaab se

class WelcomeBackScreen extends ConsumerStatefulWidget {
  const WelcomeBackScreen({super.key});
  @override
  ConsumerState<WelcomeBackScreen> createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends ConsumerState<WelcomeBackScreen> {
  ({String name, String email})? _account;

  @override
  void initState() {
    super.initState();
    _load(); // secure storage async hai, isliye initState mein load
  }

  Future<void> _load() async {
    final acc = await ref.read(savedAccountServiceProvider).get();
    if (!mounted) return;
    if (acc == null) {
      context.go('/login'); // account remove ho chuka ho to yahan rukna nahi
      return;
    }
    setState(() => _account = acc);
  }

  Future<void> _removeAccount() async {
    await ref.read(savedAccountServiceProvider).clear();
    if (mounted) context.go('/login'); // ab yaad rakhne ko kuch nahi
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0A1633);
    const gold = Color(0xFFC0A062);
    final acc = _account;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF8), // ivory
      body: SafeArea(
        child: acc == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    const AppLogo(size: 56, showWordmark: true),
                    const SizedBox(height: 40),
                    const Text('Welcome Back',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: navy)),
                    const SizedBox(height: 8),
                    Text("Don't miss your next opportunity.\nSign in to continue.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: navy.withValues(alpha: 0.6))),
                    const SizedBox(height: 32),
                    _accountCard(acc, navy, gold),
                    const SizedBox(height: 12),
                    _anotherAccountCard(navy),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('New here? ', style: TextStyle(color: navy.withValues(alpha: 0.7))),
                        GestureDetector(
                          onTap: () => context.go('/signup'),
                          child: const Text('Join now',
                              style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _accountCard(({String name, String email}) acc, Color navy, Color gold) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: navy.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => context.go('/login', extra: acc.email), // email prefill ke liye
        leading: CircleAvatar(
          backgroundColor: navy,
          child: Text(acc.name.isNotEmpty ? acc.name[0].toUpperCase() : '?',
              style: TextStyle(color: gold, fontWeight: FontWeight.w700)),
        ),
        title: Text(acc.name,
            style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
        subtitle: Text(SavedAccountService.maskEmail(acc.email)),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: navy.withValues(alpha: 0.6)),
          onSelected: (v) { if (v == 'remove') _removeAccount(); },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'remove', child: Text('Remove account')),
          ],
        ),
      ),
    );
  }

  Widget _anotherAccountCard(Color navy) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: navy.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () => context.go('/login'), // extra nahi = khali form
        leading: CircleAvatar(
          backgroundColor: navy.withValues(alpha: 0.08),
          child: Icon(Icons.person_outline, color: navy.withValues(alpha: 0.5)),
        ),
        title: Text('Sign in using another account',
            style: TextStyle(color: navy.withValues(alpha: 0.75))),
      ),
    );
  }
}