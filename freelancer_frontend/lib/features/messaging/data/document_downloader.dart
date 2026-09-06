// F-M8 Part 6 — download a shared document and cache it on disk, keyed by MESSAGE ID
// so re-opening never re-downloads. The file is then handed to the OS handler
// (open_filex) by the bubble; it is NEVER rendered in-app — the backend's ADR says
// the client must not extend that trust to untrusted files.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class DocumentDownloader {
  // A FRESH Dio — deliberately NOT the authed app client. mediaUrl is a public
  // Cloudinary raw URL; sending our bearer token to a third party is needless
  // exposure (and the app dio's baseUrl/interceptors don't apply to an absolute URL).
  final Dio _dio;
  DocumentDownloader([Dio? dio]) : _dio = dio ?? Dio();

  // The already-downloaded copy for this message, or null if not cached yet. The
  // cache key is the message id (immutable), so a message opened twice re-uses the
  // same file. Filename is preserved for a sensible name at OS hand-off / share time.
  Future<File?> cachedFile(String messageId, String fileName) async {
    final f = await _target(messageId, fileName);
    return await f.exists() ? f : null;
  }

  // Download to the cache. Progress is real (dio onReceiveProgress) — a 25 MB file on
  // a slow connection is a long silence otherwise. Written to a ".part" sibling then
  // renamed, so a cancelled/failed transfer never leaves a truncated file that a
  // later cachedFile() would wrongly treat as complete.
  Future<File> download(
    String messageId,
    String fileName,
    String url, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final target = await _target(messageId, fileName);
    await target.parent.create(recursive: true);
    final part = '${target.path}.part';
    await _dio.download(
      url,
      part,
      onReceiveProgress: onProgress,
      cancelToken: cancelToken,
    );
    if (await target.exists()) await target.delete();
    await File(part).rename(target.path);
    return target;
  }

  Future<File> _target(String messageId, String fileName) async {
    final dir = await getTemporaryDirectory();
    final safeMsg = _sanitize(messageId);
    final safeName = fileName.isEmpty ? 'document' : _sanitize(fileName);
    return File('${dir.path}/skillora_docs/$safeMsg/$safeName');
  }

  // Strip path separators / reserved characters so a filename can never escape the
  // per-message cache directory or break on Windows.
  String _sanitize(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

final documentDownloaderProvider =
    Provider<DocumentDownloader>((ref) => DocumentDownloader());
