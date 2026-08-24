// F-M6: Forward picker — lets the user pick a conversation to forward selected
// messages into. Pessimistic: the forward call completes before returning to
// the chat screen. Single-target only; multi-target forwarding is in docs/TODO.md.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/utils/number_format.dart';
import '../../application/message_actions.dart';
import '../../data/messaging_repository.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';
import '../widgets/conversation_tile.dart';

class ForwardPickerScreen extends ConsumerStatefulWidget {
  const ForwardPickerScreen({
    super.key,
    required this.sourceConversationId,
    required this.messageIds,
  });

  final String sourceConversationId;
  final List<String> messageIds;

  @override
  ConsumerState<ForwardPickerScreen> createState() =>
      _ForwardPickerScreenState();
}

class _ForwardPickerScreenState extends ConsumerState<ForwardPickerScreen> {
  static const _ivory = Color(0xFFFAFAF8);
  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  final _searchCtrl = TextEditingController();
  String _query = '';
  List<ConversationSummary> _all = [];
  bool _isLoading = true;
  String? _loadError;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _loadError = null; });
    try {
      // pageSize 50 gives a full picker list. Conversations are bounded in practice
      // (see docs/TODO.md: multi-page picker as follow-up).
      final result = await ref
          .read(messagingRepositoryProvider)
          .getConversations(pageSize: 50);
      if (!mounted) return;
      setState(() { _all = result.items; _isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loadError = appErrorMessage(e); _isLoading = false; });
    }
  }

  List<ConversationSummary> get _eligible {
    final count = widget.messageIds.length;
    return _all.where((c) {
      if (c.id == widget.sourceConversationId) return false;
      if (!isForwardEligible(c, count)) return false;
      if (_query.isNotEmpty &&
          !c.otherUser.fullName.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _forward(ConversationSummary target) async {
    setState(() => _isSending = true);
    try {
      await ref.read(messagingRepositoryProvider).forwardMessages(
        widget.sourceConversationId,
        targetConversationId: target.id,
        messageIds: widget.messageIds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true); // signal success to ChatScreen
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appErrorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.messageIds.length;

    return Scaffold(
      backgroundColor: _ivory,
      appBar: AppBar(
        backgroundColor: _ivory,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: _navy.withValues(alpha: 0.08),
        surfaceTintColor: Colors.transparent,
        foregroundColor: _navy,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: _navy,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              MessagingStrings.forwardPickerTitle,
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
            Text(
              MessagingStrings.forwardingCount(count),
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 12,
                color: _navy.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
      body: _isSending
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _gold),
              ),
            )
          : _body(),
    );
  }

  Widget _body() {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: _navy.withValues(alpha: 0.3)),
              const SizedBox(height: 16),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _load,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: BorderSide(color: _navy.withValues(alpha: 0.35)),
                  shape: const StadiumBorder(),
                ),
                child: const Text(MessagingStrings.retry),
              ),
            ],
          ),
        ),
      );
    }

    // No eligible conversations at all (before search filter).
    final allEligible = _all.where((c) {
      if (c.id == widget.sourceConversationId) return false;
      return isForwardEligible(c, widget.messageIds.length);
    }).toList();

    if (allEligible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            MessagingStrings.forwardNoConversations,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 14, color: _navy.withValues(alpha: 0.55)),
          ),
        ),
      );
    }

    final results = _eligible;

    return Column(
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: _navy, fontSize: 15),
            decoration: InputDecoration(
              hintText: MessagingStrings.forwardSearchHint,
              hintStyle: TextStyle(color: _navy.withValues(alpha: 0.40)),
              prefixIcon:
                  Icon(Icons.search_rounded, color: _navy.withValues(alpha: 0.45)),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide:
                    BorderSide(color: _navy.withValues(alpha: 0.12)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide:
                    BorderSide(color: _navy.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(
                    color: _gold.withValues(alpha: 0.65), width: 1.2),
              ),
            ),
          ),
        ),
        // Result count header
        if (results.isNotEmpty)
          Padding(
            padding:
                const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 6),
            child: Text(
              formatCount(results.length),
              textAlign: TextAlign.start,
              style: TextStyle(
                  fontSize: 12, color: _navy.withValues(alpha: 0.45)),
            ),
          ),
        // List
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    MessagingStrings.forwardNoResults,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: _navy.withValues(alpha: 0.55)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: results.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => ConversationTile(
                    summary: results[i],
                    onTap: () => _forward(results[i]),
                  ),
                ),
        ),
      ],
    );
  }
}