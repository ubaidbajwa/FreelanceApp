// My Connections — accepted connections ki list, client-side search ke sath.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/my_connections_notifier.dart';
import '../../data/models/connection_models.dart';

class MyConnectionsScreen extends ConsumerStatefulWidget {
  const MyConnectionsScreen({super.key});

  @override
  ConsumerState<MyConnectionsScreen> createState() =>
      _MyConnectionsScreenState();
}

class _MyConnectionsScreenState extends ConsumerState<MyConnectionsScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myConnectionsProvider);

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(context, state),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, MyConnectionsState state) {
    final count = state.connections.length;
    final showCount = !state.loading || count > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _navy),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Design system: letterspaced UPPERCASE gold overline
                const Text(
                  'NETWORK',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  showCount ? 'Connections · $count' : 'Connections',
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(MyConnectionsState state) {
    // Pehli load
    if (state.loading && state.connections.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      );
    }

    // Load fail
    if (state.error != null && state.connections.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: _navy.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                shape: const StadiumBorder(),
              ),
              onPressed: () =>
                  ref.read(myConnectionsProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Zero connections (koi nahi mila — Discover People ka rasta)
    if (state.connections.isEmpty) {
      return RefreshIndicator(
        color: _gold,
        onRefresh: () =>
            ref.read(myConnectionsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [_zeroConnectionsEmpty()],
        ),
      );
    }

    // Connections hain — search bar + list
    return Column(
      children: [
        _searchBar(),
        Expanded(
          child: RefreshIndicator(
            color: _gold,
            onRefresh: () =>
                ref.read(myConnectionsProvider.notifier).refresh(),
            child: state.filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [_noMatchesEmpty()],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    itemCount: state.filtered.length,
                    itemBuilder: (_, i) => _connectionRow(state.filtered[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) =>
            ref.read(myConnectionsProvider.notifier).onFilterChanged(v),
        style: const TextStyle(color: _navy),
        decoration: InputDecoration(
          hintText: 'Search connections...',
          hintStyle: TextStyle(color: _navy.withValues(alpha: 0.40)),
          prefixIcon:
              Icon(Icons.search, color: _navy.withValues(alpha: 0.40)),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear,
                      color: _navy.withValues(alpha: 0.40)),
                  onPressed: () {
                    _searchCtrl.clear();
                    ref
                        .read(myConnectionsProvider.notifier)
                        .onFilterChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: _navy.withValues(alpha: 0.12), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: _gold.withValues(alpha: 0.65), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _zeroConnectionsEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(
            'No connections yet',
            style: const TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Grow your network — find people to connect with.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _navy.withValues(alpha: 0.55),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
            onPressed: () => context.push('/people'),
            child: const Text('Discover People'),
          ),
        ],
      ),
    );
  }

  Widget _noMatchesEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navy.withValues(alpha: 0.08)),
      ),
      child: Text(
        'No matches for "${_searchCtrl.text}"',
        textAlign: TextAlign.center,
        style: TextStyle(color: _navy.withValues(alpha: 0.45), fontSize: 14),
      ),
    );
  }

  Widget _connectionRow(ConnectionUser user) {
    // TODO: navigate to user profile when profile screen exists
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _avatar(user),
          const SizedBox(width: 12),
          Expanded(child: _userInfo(user)),
        ],
      ),
    );
  }

  Widget _avatar(ConnectionUser user) {
    final photo = user.profilePhotoUrl;
    return CircleAvatar(
      radius: 24,
      backgroundColor: _navy,
      foregroundImage: photo != null && photo.isNotEmpty
          ? NetworkImage(photo)
          : null,
      child: Text(
        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
        style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _userInfo(ConnectionUser user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _navy,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (user.headline != null && user.headline!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            user.headline!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _navy.withValues(alpha: 0.55),
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
