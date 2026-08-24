import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/realtime/realtime_client.dart';
import '../../../../core/realtime/realtime_notifier.dart';
import '../../../../core/storage/secure_storage_service.dart';
import '../../application/profile_summary_notifier.dart';

// Persistent shell: bottom nav (5 tabs), top app bar, Post FAB, right drawer.
// body = StatefulNavigationShell — IndexedStack tab state automatically preserve hoti hai.

class AppShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _ivory = Color(0xFFFAFAF8);

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Shell mount = authenticated session reached. Connect after the first frame
    // so the Riverpod tree is fully built before network calls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(realtimeNotifierProvider.notifier).connect();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Mobile OSes suspend sockets on background — disconnect deliberately so we
  // know the exact state, then reconnect cleanly on resume rather than relying
  // on a half-dead socket the client believes is alive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        ref.read(realtimeNotifierProvider.notifier).disconnect();
        break;
      case AppLifecycleState.resumed:
        ref.read(realtimeNotifierProvider.notifier).connect();
        break;
      case AppLifecycleState.inactive:
        break; // transitional state — no action
    }
  }

  // Agar same tab fir tap ho to branch root pe reset hota hai (Instagram behavior)
  void _onTabTap(int index) {
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileSummaryProvider);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _ivory,
      endDrawer: _RightDrawer(
        profile: profile,
        scaffoldKey: _scaffoldKey,
      ),
      appBar: _buildAppBar(profile),
      body: widget.shell,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: posts module
        },
        backgroundColor: _navy,
        foregroundColor: _gold,
        elevation: 3,
        tooltip: 'Create post',
        child: const Icon(Icons.edit_outlined),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildNavBar(),
    );
  }

  AppBar _buildAppBar(ProfileSummaryState profile) {
    return AppBar(
      backgroundColor: _ivory,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: _navy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: GestureDetector(
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          child: CircleAvatar(
            radius: 18,
            backgroundColor: _navy,
            foregroundImage: (profile.photoUrl?.isNotEmpty ?? false)
                ? NetworkImage(profile.photoUrl!)
                : null,
            child: Text(
              profile.displayName.isNotEmpty
                  ? profile.displayName[0].toUpperCase()
                  : 'S',
              style: const TextStyle(
                color: _gold,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
      title: GestureDetector(
        onTap: () {
          // TODO: search module
        },
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: _navy.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _gold.withValues(alpha: 0.35), width: 1.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Icon(Icons.search, color: _navy.withValues(alpha: 0.4), size: 18),
              const SizedBox(width: 8),
              Text(
                'Search Skillora',
                style: TextStyle(color: _navy.withValues(alpha: 0.4), fontSize: 14),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // Debug-only: real-time connection state dot. Removed in release builds —
        // a "connected" indicator in production invites users to interpret normal
        // reconnects as breakage.
        if (kDebugMode) const _RealtimeDot(),
        // Notifications with unread badge placeholder
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: _navy),
              onPressed: () {
                // TODO: notifications module
              },
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _gold,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        // Quick jump to messages tab
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline, color: _navy),
          onPressed: () => _onTabTap(3),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildNavBar() {
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: _ivory,
          indicatorColor: _navy.withValues(alpha: 0.08),
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? _navy
                  : _navy.withValues(alpha: 0.45),
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected)
                  ? _navy
                  : _navy.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: _onTabTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'My Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.message_outlined),
            selectedIcon: Icon(Icons.message),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ------- Right Drawer -------

class _RightDrawer extends ConsumerWidget {
  final ProfileSummaryState profile;
  final GlobalKey<ScaffoldState> scaffoldKey;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);
  static const _ivory = Color(0xFFFAFAF8);

  const _RightDrawer({required this.profile, required this.scaffoldKey});

  void _close() => scaffoldKey.currentState?.closeEndDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      width: 288,
      backgroundColor: _ivory,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: _navy,
                    foregroundImage: (profile.photoUrl?.isNotEmpty ?? false)
                        ? NetworkImage(profile.photoUrl!)
                        : null,
                    child: Text(
                      profile.displayName.isNotEmpty
                          ? profile.displayName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.displayName.isEmpty
                        ? 'Skillora User'
                        : profile.displayName,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (profile.headline?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 3),
                    Text(
                      profile.headline!,
                      style: TextStyle(
                        color: _navy.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Profile completion bar
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: profile.completionPercent / 100,
                            backgroundColor: _navy.withValues(alpha: 0.1),
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(_gold),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${profile.completionPercent}%',
                        style: TextStyle(
                          color: _navy.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Divider(color: _navy.withValues(alpha: 0.08), height: 1),
            const SizedBox(height: 8),
            // Menu
            _DrawerTile(
              icon: Icons.person_outline,
              label: 'View profile',
              onTap: () {
                _close();
                // TODO: profile view screen
              },
            ),
            _DrawerTile(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                _close();
                // TODO: settings module
              },
            ),
            const Spacer(),
            Divider(color: _navy.withValues(alpha: 0.08), height: 1),
            _DrawerTile(
              icon: Icons.logout,
              label: 'Logout',
              onTap: () async {
                _close();
                // Disconnect hub before clearing tokens — socket must not
                // outlive the session (authenticated socket = security problem).
                await ref.read(realtimeClientProvider).disconnect();
                await ref.read(secureStorageProvider).clearTokens();
                if (context.mounted) context.go('/welcome-back');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  static const _navy = Color(0xFF0A1633);

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _navy, size: 22),
      title: Text(label, style: const TextStyle(color: _navy, fontSize: 15)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

// Debug-only connection state dot — not visible in release builds.
// Color: grey=disconnected, orange=connecting/reconnecting, green=connected, red=failed.
class _RealtimeDot extends ConsumerWidget {
  const _RealtimeDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(realtimeNotifierProvider);
    final color = switch (state) {
      RealtimeConnectionState.connected => const Color(0xFF4CAF50),
      RealtimeConnectionState.connecting ||
      RealtimeConnectionState.reconnecting =>
        const Color(0xFFFF9800),
      RealtimeConnectionState.failed => const Color(0xFFF44336),
      RealtimeConnectionState.disconnected => const Color(0xFF9E9E9E),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
