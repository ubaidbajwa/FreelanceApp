import 'package:flutter/material.dart';
import '../../constants/job_titles.dart';

// Job title picker — DraggableScrollableSheet: back arrow + Done upar,
// autofocus search field, aur neeche live-filtered suggestions
// (`commonJobTitles` se). Suggestion tap ya typed text ke saath Done —
// dono field bhar dete hain. Returns chosen title, ya null (cancel).

const _ivory = Color(0xFFFAFAF8);
const _navy = Color(0xFF0A1633);
const _gold = Color(0xFFC0A062);

Future<String?> showJobTitleSheet(
  BuildContext context, {
  String initial = '',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _ivory,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _JobTitleSheet(initial: initial),
  );
}

class _JobTitleSheet extends StatefulWidget {
  final String initial;
  const _JobTitleSheet({required this.initial});

  @override
  State<_JobTitleSheet> createState() => _JobTitleSheetState();
}

class _JobTitleSheetState extends State<_JobTitleSheet> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initial);
    _query = widget.initial;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _done() {
    final typed = _searchController.text.trim();
    Navigator.pop(context, typed.isEmpty ? null : typed);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().trim();
    final filtered = q.isEmpty
        ? commonJobTitles
        : commonJobTitles
            .where((t) => t.toLowerCase().contains(q))
            .toList();

    return Padding(
      // Keyboard ke upar sheet — fields chhupti nahi
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Back arrow + Done
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: _navy),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _done,
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          color: _navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Search field (autofocus)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: _navy),
                  onChanged: (value) => setState(() => _query = value),
                  onSubmitted: (_) => _done(),
                  decoration: InputDecoration(
                    hintText: 'Search or type your job title',
                    hintStyle: TextStyle(color: _navy.withValues(alpha: 0.35)),
                    prefixIcon: const Icon(Icons.search, color: _navy),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: _gold.withValues(alpha: 0.45)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: _gold, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Live suggestions
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No matches — tap Done to use "${_searchController.text.trim()}"',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: _navy.withValues(alpha: 0.5)),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final title = filtered[index];
                          return ListTile(
                            title: Text(
                              title,
                              style: const TextStyle(color: _navy),
                            ),
                            onTap: () => Navigator.pop(context, title),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
