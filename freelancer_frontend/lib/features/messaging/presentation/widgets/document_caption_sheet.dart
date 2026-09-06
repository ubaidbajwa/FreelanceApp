// F-M8 Part 3 — the compact confirmation shown AFTER picking a document and BEFORE
// sending. A document has nothing to preview (unlike an image/video), so this is a
// bottom sheet, not a full-screen preview: file icon, filename, size, an optional
// caption field, and send. Dismissing (back / drag-down) cancels and uploads nothing.
// An in-progress reply is carried through and its quoted preview shown here too.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/chat_notifier.dart';
import '../../application/message_actions.dart';
import '../../data/models/messaging_models.dart';
import '../../messaging_strings.dart';

// Opens the sheet. Returns after it is dismissed; the actual optimistic send happens
// inside (ChatNotifier.sendDocument), so nothing is returned to the caller.
Future<void> showDocumentCaptionSheet(
  BuildContext context, {
  required String path,
  required String fileName,
  required int sizeBytes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true, // so the caption field rises above the keyboard
    backgroundColor: const Color(0xFFFAFAF8),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DocumentCaptionSheet(
      path: path,
      fileName: fileName,
      sizeBytes: sizeBytes,
    ),
  );
}

class _DocumentCaptionSheet extends ConsumerStatefulWidget {
  const _DocumentCaptionSheet({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
  });

  final String path;
  final String fileName;
  final int sizeBytes;

  @override
  ConsumerState<_DocumentCaptionSheet> createState() =>
      _DocumentCaptionSheetState();
}

class _DocumentCaptionSheetState extends ConsumerState<_DocumentCaptionSheet> {
  static const _navy = Color(0xFF0A1633);
  static const _pdf = Color(0xFFE5484D);
  static const _word = Color(0xFF3B82C4);
  static const _excel = Color(0xFF2E9E5B);
  static const _powerpoint = Color(0xFFE06B2C);

  final _caption = TextEditingController();
  bool _sending = false; // double-tap guard — one upload per pick

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() {
    if (_sending) return; // a second tap must not spawn a second upload
    setState(() => _sending = true);
    ref.read(chatProvider.notifier).sendDocument(
          path: widget.path,
          fileName: widget.fileName,
          sizeBytes: widget.sizeBytes,
          caption: _caption.text,
        );
    Navigator.of(context).pop();
  }

  Color _iconColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => _pdf,
        DocumentKind.word => _word,
        DocumentKind.excel => _excel,
        DocumentKind.powerpoint => _powerpoint,
        DocumentKind.text || DocumentKind.generic => _navy,
      };

  IconData _iconData(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => Icons.picture_as_pdf_rounded,
        DocumentKind.word => Icons.description_rounded,
        DocumentKind.excel => Icons.table_chart_rounded,
        DocumentKind.powerpoint => Icons.slideshow_rounded,
        DocumentKind.text => Icons.article_rounded,
        DocumentKind.generic => Icons.insert_drive_file_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final reply = ref.watch(chatProvider.select((s) => s.draftReply));
    final otherUserId = ref.watch(chatProvider.select((s) => s.otherUserId));

    final kind = documentKindForName(widget.fileName);
    final iconColor = _iconColor(kind);
    final displayName = middleEllipsize(widget.fileName, maxChars: 40);
    final ext = documentExtensionLabel(widget.fileName);
    final size = formatFileSize(widget.sizeBytes);
    final subtitle = ext.isEmpty ? size : '$ext · $size';

    return SafeArea(
      child: Padding(
        // Rise above the keyboard when the caption field is focused.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (reply != null)
              _QuotedStrip(reply: reply, otherUserId: otherUserId),
            // File row — icon chip + name + size/extension.
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_iconData(kind), size: 24, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: 12,
                            color: _navy.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Caption + send.
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      enabled: !_sending,
                      style: const TextStyle(color: _navy, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: MessagingStrings.mediaCaptionHint,
                        hintStyle: TextStyle(
                          color: _navy.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: _navy.withValues(alpha: 0.04),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Send — navy fill circle (gold is never a button fill).
                  Material(
                    color: _sending ? _navy.withValues(alpha: 0.4) : _navy,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sending ? null : _send,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _sending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Tooltip(
                                message: MessagingStrings.mediaSendTooltip,
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                      ),
                    ),
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

// Compact quoted-reply strip shown above the file row (light theme variant).
class _QuotedStrip extends StatelessWidget {
  const _QuotedStrip({required this.reply, required this.otherUserId});

  final MessageReply reply;
  final String? otherUserId;

  static const _navy = Color(0xFF0A1633);
  static const _gold = Color(0xFFC0A062);

  @override
  Widget build(BuildContext context) {
    final isReplyMine = otherUserId != null && reply.senderId != otherUserId;
    final name = isReplyMine ? MessagingStrings.replyYou : reply.senderName;
    final snippet = reply.isDeleted
        ? MessagingStrings.replyDeletedQuote
        : switch (reply.type) {
            MessageType.image => MessagingStrings.replyPhoto,
            MessageType.video => MessagingStrings.replyVideo,
            // F-M8 — a file quote shows its filename when present, else the label.
            MessageType.file =>
              (reply.fileName?.isNotEmpty ?? false)
                  ? reply.fileName!
                  : MessagingStrings.replyFile,
            MessageType.voice => MessagingStrings.replyVoice,
            _ => reply.bodySnippet,
          };

    return Container(
      width: double.infinity,
      color: _navy.withValues(alpha: 0.04),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Row(
        children: [
          Container(width: 3, height: 32, color: _gold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  textAlign: TextAlign.start,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 12,
                    color: _navy.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
