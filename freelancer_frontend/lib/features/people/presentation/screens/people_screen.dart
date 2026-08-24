// People — discover users to connect with. Debounced search, infinite-scroll
// pagination, aur har row pe connectionStatus-driven button. Send request
// pessimistic hai: API success ke baad hi row "Pending" hota hai.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../connections/data/models/connection_models.dart';
import '../../application/people_notifier.dart';
import '../../data/models/person_model.dart';

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // List ke neeche 300px ke andar pahunchte hi agli page. Double-fetch se
  // bachao notifier.loadMore() ke andar hai (loadingMore/hasNextPage guard).
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(peopleProvider.notifier).loadMore();
    }
  }

  Future<void> _connect(String userId) async {
    final error = await ref.read(peopleProvider.notifier).sendConnect(userId);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(peopleProvider);

    return Scaffold(
      backgroundColor: _ivory,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            _searchBar(),
            const SizedBox(height: 8),
            Expanded(child: _body(state)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: _navy),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NETWORK',
                  style: TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'People',
                  style: TextStyle(
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

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => ref.read(peopleProvider.notifier).onSearchChanged(v),
        autocorrect: false,
        style: const TextStyle(color: _navy),
        decoration: InputDecoration(
          hintText: 'Search people',
          hintStyle: TextStyle(color: _navy.withValues(alpha: 0.4)),
          prefixIcon: Icon(Icons.search, color: _navy.withValues(alpha: 0.5)),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide(color: _gold.withValues(alpha: 0.6), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _body(PeopleState state) {
    // Pehli load
    if (state.loading && state.items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
      );
    }

    // Initial load fail — retry ke sath
    if (state.error != null && state.items.isEmpty) {
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
              onPressed: () => ref.read(peopleProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: () => ref.read(peopleProvider.notifier).refresh(),
      child: state.items.isEmpty
          ? _emptyState()
          : ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              // +1 row for the bottom loadingMore spinner
              itemCount: state.items.length + (state.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _gold),
                      ),
                    ),
                  );
                }
                return _personRow(state.items[index], state);
              },
            ),
    );
  }

  Widget _emptyState() {
    // Empty bhi scrollable rahe taake pull-to-refresh chale
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _navy.withValues(alpha: 0.08)),
            ),
            child: Text(
              'No people found',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: _navy.withValues(alpha: 0.45), fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _personRow(PersonModel person, PeopleState state) {
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
          _avatar(person),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (person.headline != null && person.headline!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    person.headline!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _navy.withValues(alpha: 0.55),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusButton(person, state),
        ],
      ),
    );
  }

  Widget _avatar(PersonModel person) {
    final photo = person.photoUrl;
    return CircleAvatar(
      radius: 24,
      backgroundColor: _navy,
      foregroundImage:
          photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
      child: Text(
        person.fullName.isNotEmpty ? person.fullName[0].toUpperCase() : '?',
        style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
      ),
    );
  }

  // connectionStatus se button/label. None = tappable gold pill; baqi teen
  // states non-Connect (Pending/Connected muted, Respond → Invitations).
  Widget _statusButton(PersonModel person, PeopleState state) {
    // Per-row loading — sirf isi row ki call in-flight ho to spinner
    if (state.connectingIds.contains(person.userId)) {
      return const SizedBox(
        width: 92,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
          ),
        ),
      );
    }

    switch (person.connectionStatus) {
      case ConnectionStatusWith.none:
        return FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _navy,
            shape: const StadiumBorder(),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onPressed: () => _connect(person.userId),
          child: const Text('Connect'),
        );

      case ConnectionStatusWith.pendingOutgoing:
        return _mutedLabel('Pending');

      case ConnectionStatusWith.pendingIncoming:
        // Users endpoint request-id nahi deta — Accept/Withdraw yahan nahi.
        // Respond pe Invitations screen kholo.
        return OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _navy,
            side: BorderSide(color: _navy.withValues(alpha: 0.35)),
            shape: const StadiumBorder(),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 20),
          ),
          onPressed: () => context.push('/connections/invitations'),
          child: const Text('Respond'),
        );

      case ConnectionStatusWith.connected:
        return _mutedLabel('Connected');
    }
  }

  Widget _mutedLabel(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        style: TextStyle(
          color: _navy.withValues(alpha: 0.4),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
