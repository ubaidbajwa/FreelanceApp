// MessagingRepository tests for the M2 message-action endpoints.
//
// No http_mock_adapter dependency — we drive the repo through Dio's own
// HttpClientAdapter seam: a fake adapter records the outgoing RequestOptions
// (method, path, query, body) and returns a canned JSON body. This verifies the
// REAL request the repo builds (verb + URL + query + parsing), not a mock of
// the repo itself.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer_frontend/features/messaging/data/messaging_repository.dart';
import 'package:freelancer_frontend/features/messaging/data/models/messaging_models.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? last;
  final String responseBody;
  final int statusCode;

  _RecordingAdapter({this.responseBody = '{}', this.statusCode = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local'));
  dio.httpClientAdapter = adapter;
  return dio;
}

String _messageJson(String id, {bool isPinned = false}) => jsonEncode({
      'id': id,
      'conversationId': 'c1',
      'senderId': 'u1',
      'body': 'hi',
      'type': 0,
      'createdAt': '2026-01-01T10:00:00Z',
      'isPinned': isPinned,
    });

void main() {
  test('deleteMessage sends DELETE with required scope in the query', () async {
    final adapter = _RecordingAdapter(statusCode: 204);
    final repo = MessagingRepository(_dioWith(adapter));

    await repo.deleteMessage('c1', 'm1', scope: 'everyone');

    expect(adapter.last!.method, 'DELETE');
    expect(adapter.last!.path, '/api/conversations/c1/messages/m1');
    expect(adapter.last!.queryParameters['scope'], 'everyone');
  });

  test('pinMessage POSTs the pin sub-resource with duration + replaceOldest',
      () async {
    final adapter = _RecordingAdapter(statusCode: 204);
    final repo = MessagingRepository(_dioWith(adapter));

    await repo.pinMessage('c1', 'm1', duration: PinDuration.sevenDays);

    expect(adapter.last!.method, 'POST');
    expect(adapter.last!.path, '/api/conversations/c1/messages/m1/pin');
    final body = adapter.last!.data as Map;
    expect(body['duration'], 1, reason: '7 days maps to apiValue 1');
    expect(body['replaceOldest'], false, reason: 'defaults to false');
  });

  test('pinMessage forwards replaceOldest when set', () async {
    final adapter = _RecordingAdapter(statusCode: 204);
    final repo = MessagingRepository(_dioWith(adapter));

    await repo.pinMessage('c1', 'm1',
        duration: PinDuration.thirtyDays, replaceOldest: true);

    final body = adapter.last!.data as Map;
    expect(body['duration'], 2);
    expect(body['replaceOldest'], true);
  });

  test('unpinMessage DELETEs the pin sub-resource', () async {
    final adapter = _RecordingAdapter(statusCode: 204);
    final repo = MessagingRepository(_dioWith(adapter));

    await repo.unpinMessage('c1', 'm1');

    expect(adapter.last!.method, 'DELETE');
    expect(adapter.last!.path, '/api/conversations/c1/messages/m1/pin');
  });

  test('getPinnedMessages GETs /pinned and parses a Message list', () async {
    final adapter = _RecordingAdapter(
      responseBody: '[${_messageJson('m1', isPinned: true)},'
          '${_messageJson('m2', isPinned: true)}]',
    );
    final repo = MessagingRepository(_dioWith(adapter));

    final pinned = await repo.getPinnedMessages('c1');

    expect(adapter.last!.method, 'GET');
    expect(adapter.last!.path, '/api/conversations/c1/pinned');
    expect(pinned, hasLength(2));
    expect(pinned.first.id, 'm1');
    expect(pinned.first.isPinned, isTrue);
  });

  test('editMessage PUTs the new body and returns the updated message',
      () async {
    final adapter = _RecordingAdapter(responseBody: _messageJson('m1'));
    final repo = MessagingRepository(_dioWith(adapter));

    final updated = await repo.editMessage('c1', 'm1', 'new body');

    expect(adapter.last!.method, 'PUT');
    expect(adapter.last!.path, '/api/conversations/c1/messages/m1');
    expect((adapter.last!.data as Map)['body'], 'new body');
    expect(updated.id, 'm1');
  });

  test('forwardMessages POSTs target + ordered ids and parses the result',
      () async {
    final adapter = _RecordingAdapter(responseBody: '[${_messageJson('m9')}]');
    final repo = MessagingRepository(_dioWith(adapter));

    final created = await repo.forwardMessages(
      'c1',
      targetConversationId: 'c2',
      messageIds: ['m1', 'm2'],
    );

    expect(adapter.last!.method, 'POST');
    expect(adapter.last!.path, '/api/conversations/c1/messages/forward');
    final body = adapter.last!.data as Map;
    expect(body['targetConversationId'], 'c2');
    expect(body['messageIds'], ['m1', 'm2']);
    expect(created, hasLength(1));
  });

  test('reactToMessage PUTs the emoji and parses the aggregate', () async {
    final adapter = _RecordingAdapter(
      responseBody: jsonEncode([
        {'emoji': '👍', 'count': 3, 'reactedByMe': true},
      ]),
    );
    final repo = MessagingRepository(_dioWith(adapter));

    final reactions = await repo.reactToMessage('c1', 'm1', '👍');

    expect(adapter.last!.method, 'PUT');
    expect(adapter.last!.path, '/api/conversations/c1/messages/m1/reaction');
    expect((adapter.last!.data as Map)['emoji'], '👍');
    expect(reactions.single.emoji, '👍');
    expect(reactions.single.count, 3);
  });
}
