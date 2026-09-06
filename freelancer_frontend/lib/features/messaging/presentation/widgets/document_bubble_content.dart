// F-M8 Part 5 + 6 — the document content inside a message bubble. A document has no
// thumbnail, so this is a distinct layout from image/video: a type-specific icon on
// the leading side, the filename (middle-ellipsised so the extension stays visible),
// the size + uppercase extension, and a download/open affordance.
//
// Tapping downloads the file (real progress), caches it by message id, and hands it
// to the OS handler — NEVER rendered in-app (backend ADR: don't extend that trust to
// untrusted files). "No app can open this" is handled by offering to share instead.
//
// Legibility on BOTH bubble styles is deliberate: text/size use the bubble's adaptive
// colour (white on the navy own-bubble, navy on the light other-bubble); the type
// glyph uses a fixed accent colour chosen to read on either background.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/chat_notifier.dart';
import '../../application/message_actions.dart';
import '../../data/document_downloader.dart';
import '../../messaging_strings.dart';

// Where a tap currently stands. `ready` = the file is cached on disk (open, don't
// re-download); `failed` = the last download errored (tap retries).
enum _DownloadStatus { idle, downloading, ready, failed }

class DocumentBubbleContent extends ConsumerStatefulWidget {
  const DocumentBubbleContent({
    super.key,
    required this.message,
    required this.mine,
  });

  final ChatMessage message;
  final bool mine;

  @override
  ConsumerState<DocumentBubbleContent> createState() =>
      _DocumentBubbleContentState();
}

class _DocumentBubbleContentState extends ConsumerState<DocumentBubbleContent> {
  static const _navy = Color(0xFF0A1633);

  // Type accent colours — picked to stay legible on BOTH the navy own-bubble and the
  // light other-bubble. text/generic fall back to the bubble's adaptive text colour.
  static const _pdf = Color(0xFFE5484D);
  static const _word = Color(0xFF3B82C4);
  static const _excel = Color(0xFF2E9E5B);
  static const _powerpoint = Color(0xFFE06B2C);

  _DownloadStatus _status = _DownloadStatus.idle;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  // If this document was already downloaded (cache keyed by message id), start in the
  // `ready` state so the button shows "open" and a tap never re-downloads.
  Future<void> _checkCache() async {
    final m = widget.message;
    final name = m.mediaFileName;
    if (m.id.isEmpty || name == null || name.isEmpty) return;
    final cached =
        await ref.read(documentDownloaderProvider).cachedFile(m.id, name);
    if (!mounted || cached == null) return;
    setState(() => _status = _DownloadStatus.ready);
  }

  Color get _textColor => widget.mine ? Colors.white : _navy;

  Color _iconColor(DocumentKind kind) => switch (kind) {
        DocumentKind.pdf => _pdf,
        DocumentKind.word => _word,
        DocumentKind.excel => _excel,
        DocumentKind.powerpoint => _powerpoint,
        // No distinct hue — use the adaptive text colour so it reads on either bubble.
        DocumentKind.text || DocumentKind.generic => _textColor,
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
    final m = widget.message;
    final rawName = m.mediaFileName ?? '';
    final kind = documentKindForName(rawName);
    final iconColor = _iconColor(kind);
    // Filename never blank in the bubble — a confirmed non-tombstone always has one;
    // fall back to the localised label only defensively.
    final displayName = rawName.isEmpty
        ? MessagingStrings.listDocument
        : middleEllipsize(rawName, maxChars: 40);
    final ext = documentExtensionLabel(rawName);
    final size = formatFileSize(m.mediaSizeBytes);
    final subtitle = ext.isEmpty ? size : '$ext · $size';

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Leading type icon on a subtle tinted chip.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: widget.mine ? 0.28 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconData(kind), size: 22, color: iconColor),
          ),
          const SizedBox(width: 10),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontSize: 11,
                    color: _textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _action(),
        ],
      ),
    );
  }

  Widget _action() {
    final m = widget.message;
    // A pending (uploading) document shows real upload progress, not a download
    // button — the file is local, there is nothing to fetch yet.
    if (m.status == ChatSendStatus.pending) {
      return _ring(m.uploadProgress);
    }
    // A failed SEND is handled by the shared meta row ("Failed — tap to retry"),
    // so no action glyph here — showing one would compete with that affordance.
    if (m.status == ChatSendStatus.failed) {
      return const SizedBox(width: 36, height: 36);
    }

    switch (_status) {
      case _DownloadStatus.downloading:
        return _ring(_progress);
      case _DownloadStatus.ready:
        return _iconButton(Icons.open_in_new_rounded, _open,
            tip: MessagingStrings.documentOpenTooltip);
      case _DownloadStatus.failed:
        return _iconButton(Icons.refresh_rounded, _startDownload,
            tip: MessagingStrings.retry);
      case _DownloadStatus.idle:
        return _iconButton(Icons.file_download_outlined, _startDownload,
            tip: MessagingStrings.documentOpenTooltip);
    }
  }

  Widget _ring(double? value) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: _textColor,
          // Determinate once dio reports bytes; indeterminate before the first tick.
          value: (value ?? 0) <= 0 ? null : value,
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {required String tip}) {
    return Material(
      color: _textColor.withValues(alpha: widget.mine ? 0.16 : 0.06),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tip,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: _textColor),
          ),
        ),
      ),
    );
  }

  // Download to the message-id cache, then open. Real progress drives the ring; a
  // failure flips to the retry state AND surfaces a snackbar (a long silence on a
  // slow 25 MB download is otherwise indistinguishable from a hang).
  Future<void> _startDownload() async {
    final m = widget.message;
    final url = m.mediaUrl;
    final name = m.mediaFileName;
    if (url == null || url.isEmpty || name == null || name.isEmpty) return;

    setState(() {
      _status = _DownloadStatus.downloading;
      _progress = 0;
    });
    try {
      await ref.read(documentDownloaderProvider).download(
            m.id,
            name,
            url,
            onProgress: (received, total) {
              if (!mounted || total <= 0) return;
              setState(() => _progress = (received / total).clamp(0.0, 1.0));
            },
          );
      if (!mounted) return;
      setState(() => _status = _DownloadStatus.ready);
      await _open();
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _DownloadStatus.failed);
      _snack(MessagingStrings.documentDownloadFailed);
    }
  }

  // Hand the cached file to the OS. If no installed app can open the type (a .csv on
  // a phone with no spreadsheet app is common), don't fail silently — offer to share.
  Future<void> _open() async {
    final m = widget.message;
    final name = m.mediaFileName;
    if (name == null || name.isEmpty) return;
    final cached =
        await ref.read(documentDownloaderProvider).cachedFile(m.id, name);
    if (!mounted || cached == null) {
      // Cache vanished (e.g. OS cleared temp) → download again.
      if (mounted) setState(() => _status = _DownloadStatus.idle);
      return;
    }
    final result = await OpenFilex.open(cached.path);
    if (!mounted) return;
    if (result.type == ResultType.noAppToOpen) {
      _offerShare(cached);
    } else if (result.type != ResultType.done) {
      _snack(MessagingStrings.documentDownloadFailed);
    }
  }

  void _offerShare(File file) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(MessagingStrings.documentNoHandler),
          action: SnackBarAction(
            label: MessagingStrings.documentShare,
            onPressed: () {
              SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
            },
          ),
        ),
      );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
