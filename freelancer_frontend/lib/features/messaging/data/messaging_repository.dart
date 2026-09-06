import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/models/paged_result.dart';
import '../../../core/network/dio_client.dart';
import 'models/messaging_models.dart';

// ConversationsController ke SAARE 8 endpoints ek jagah — is slice ki screen
// sirf getConversations/getRequests/accept/decline use karti hai, lekin F-M2
// (chat) + F-M3 (real-time) baqi methods reuse karenge. Aadha repository
// divergence ko dawat deta hai, is liye pura ab wire kar rahe hain.
// Base URL + auth header dioProvider (interceptor) se aate hain — wahi ConnectionsRepository pattern.
class MessagingRepository {
  final Dio _dio;
  MessagingRepository(this._dio);

  // 1. Get-or-create 1:1 thread — backend 200 (na ke 201) deta hai kyunki
  //    aksar pehle se maujood thread wapis aati hai.
  Future<ConversationSummary> startOrGetConversation(String recipientId) async {
    final response = await _dio.post(
      '/api/conversations',
      data: {'recipientId': recipientId},
    );
    return ConversationSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // 2. Accepted conversations list — offset pagination (PagedResult envelope)
  Future<PagedResult<ConversationSummary>> getConversations({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/conversations',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      ConversationSummary.fromJson,
    );
  }

  // 3. Incoming pending requests — same envelope
  Future<PagedResult<ConversationSummary>> getRequests({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/conversations/requests',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      ConversationSummary.fromJson,
    );
  }

  // 4. Ek thread ke messages — CURSOR pagination (MessagePage, PagedResult nahi).
  //    `before` UTC ISO-8601 string ban kar query mein jata hai.
  Future<MessagePage> getMessages(
    String conversationId, {
    DateTime? before,
    int limit = 30,
  }) async {
    final response = await _dio.get(
      '/api/conversations/$conversationId/messages',
      queryParameters: {
        if (before != null) 'before': before.toUtc().toIso8601String(),
        'limit': limit,
      },
    );
    return MessagePage.fromJson(response.data as Map<String, dynamic>);
  }

  // 5. Message bhejo — backend 201 ke sath bana hua message wapis deta hai.
  //    replyToMessageId optional hai; null hone pe payload mein include nahi hota.
  Future<Message> sendMessage(
    String conversationId,
    String body, {
    String? replyToMessageId,
  }) async {
    final response = await _dio.post(
      '/api/conversations/$conversationId/messages',
      data: {
        'body': body,
        'replyToMessageId': ?replyToMessageId,
      },
    );
    return Message.fromJson(response.data as Map<String, dynamic>);
  }

  // 5b. Media message bhejo (F-M5) — multipart, EK request mein Cloudinary upload +
  //     message create (backend 201 ke sath bana message wapas). Form field naam
  //     backend SendMediaMessageApiRequest se exactly match karte hain: File /
  //     Caption / ReplyToMessageId (ASP.NET FromForm case-insensitive, magar exact
  //     PascalCase safe rehta hai).
  //
  //     onSendProgress dio se aata hai — asli byte-level progress (50 MB upload pe
  //     ek fake spinner bekaar hai). CancelToken caller retry/dispose pe abort ke
  //     liye. contentType client set karta hai (dio default octet-stream deta,
  //     backend sirf image/*|video/* leta — magar server magic-bytes se bhi verify
  //     karta, is liye yeh sirf sahi header ke liye hai).
  Future<Message> sendMediaMessage(
    String conversationId,
    String filePath, {
    String? caption,
    String? replyToMessageId,
    String? waveform, // F-M11 voice — comma-separated 0–100 samples (≤64) ya null
    String? fileName, // F-M8 document — original filename (backend FileName field)
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'File': await MultipartFile.fromFile(
        filePath,
        contentType: _mediaContentType(fileName ?? filePath),
      ),
      // Khali/null caption include nahi — backend Caption ko optional maanta hai.
      if (caption != null && caption.isNotEmpty) 'Caption': caption,
      'ReplyToMessageId': ?replyToMessageId,
      // Waveform null ho to bhejte hi nahi — server null ko valid maanta (flat bar).
      'Waveform': ?waveform,
      // F-M8 — document ka asli filename. Sirf File-type par set; server ise store
      // karta aur MessageDto.mediaFileName mein wapas bhejta. Image/video pe null.
      'FileName': ?fileName,
    });
    final response = await _dio.post(
      '/api/conversations/$conversationId/messages/media',
      data: formData,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return Message.fromJson(response.data as Map<String, dynamic>);
  }

  // File extension → MIME. Server-side list (ChatService): images jpeg/png/webp/gif,
  // videos mp4/webm/quicktime, voice m4a/aac (audio/mp4|aac), opus/ogg (audio/ogg).
  // Unknown → octet-stream (server saaf 400 dega). Note: .webm yahan video maana
  // jata hai (picked video ke liye) — voice recording hamesha .m4a produce karti.
  MediaType _mediaContentType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      'gif' => MediaType('image', 'gif'),
      'mp4' => MediaType('video', 'mp4'),
      'webm' => MediaType('video', 'webm'),
      'mov' || 'qt' => MediaType('video', 'quicktime'),
      'm4a' => MediaType('audio', 'mp4'), // F-M11 aacLc recording
      'aac' => MediaType('audio', 'aac'),
      'opus' || 'ogg' => MediaType('audio', 'ogg'),
      // F-M8 documents — declared type only; server still verifies by magic bytes.
      'pdf' => MediaType('application', 'pdf'),
      'doc' => MediaType('application', 'msword'),
      'docx' => MediaType('application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document'),
      'xls' => MediaType('application', 'vnd.ms-excel'),
      'xlsx' => MediaType('application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      'ppt' => MediaType('application', 'vnd.ms-powerpoint'),
      'pptx' => MediaType('application',
          'vnd.openxmlformats-officedocument.presentationml.presentation'),
      'txt' => MediaType('text', 'plain'),
      'csv' => MediaType('text', 'csv'),
      _ => MediaType('application', 'octet-stream'),
    };
  }

  // 6. Request accept karo — 204 NoContent
  Future<void> acceptConversation(String conversationId) async {
    await _dio.post('/api/conversations/$conversationId/accept');
  }

  // 7. Request decline karo — 204 NoContent
  Future<void> declineConversation(String conversationId) async {
    await _dio.post('/api/conversations/$conversationId/decline');
  }

  // 8. Read watermark set karo — 204. Is slice mein koi call NAHI karta;
  //    F-M2 chat screen use karega (method contract ke liye ab bana rahe hain).
  Future<void> markRead(String conversationId) async {
    await _dio.post('/api/conversations/$conversationId/read');
  }

  // 8b. Voice note played receipt (F-M11 M7) — 204, idempotent. Sirf caller ke
  //     INCOMING voice note pe call hoti hai (own/non-voice/tombstone server 400
  //     deta — client pehle hi guard karta, dekho shouldMarkPlayed). Server sirf us
  //     call pe MessagePlayed event fire karta jo record actually insert kare, is
  //     liye repeat calls chup rehti hain.
  Future<void> markPlayed(String conversationId, String messageId) async {
    await _dio.post(
      '/api/conversations/$conversationId/messages/$messageId/played',
    );
  }

  // 9. Single conversation — cold deep-link / push-notification tap / 403 reconciliation.
  //    200 → participant; 403 → outsider (DioException.response.statusCode == 403);
  //    404 → unknown id. Callers check statusCode to distinguish from transport failures.
  Future<ConversationSummary> getConversation(String conversationId) async {
    final response = await _dio.get('/api/conversations/$conversationId');
    return ConversationSummary.fromJson(response.data as Map<String, dynamic>);
  }

  // ===== MESSAGE ACTIONS (M2) =====
  // Endpoints mirror ConversationsController's M1.2 section. Is slice sirf
  // delete/pin/unpin use karti hai; baaki (react/removeReaction/edit/forward +
  // getPinnedMessages) ab wire kar rahe hain taake repository poora rahe aur baad
  // ki slices (F-M5 reply, F-M6 forward, F-M7 reactions, edit UI) reuse karein.

  // 10. Delete a message. scope REQUIRED — no default, kyunki backend missing
  //     scope reject karta hai aur client-side default aadha waqt ghalat kaam
  //     chup-chaap kar deta. "everyone" → shared tombstone; "me" → private hide.
  Future<void> deleteMessage(
    String conversationId,
    String messageId, {
    required String scope, // 'everyone' | 'me'
  }) async {
    await _dio.delete(
      '/api/conversations/$conversationId/messages/$messageId',
      queryParameters: {'scope': scope},
    );
  }

  // 11. Pin a message (conversation-scoped, backend cap 4 → 409 beyond). 204.
  //     M3: body ab REQUIRED — duration (0=24h,1=7d,2=30d) + optional replaceOldest.
  //     duration ka koi default NAHI (server ki tarah): caller ko chunna padta hai.
  //     replaceOldest=true → cap par sab se purana active pin hata kar naya add
  //     hota hai (atomic). replaceOldest=false + cap → 409 (caller replace dialog dikhaye).
  Future<void> pinMessage(
    String conversationId,
    String messageId, {
    required PinDuration duration,
    bool replaceOldest = false,
  }) async {
    await _dio.post(
      '/api/conversations/$conversationId/messages/$messageId/pin',
      data: {
        'duration': duration.apiValue,
        'replaceOldest': replaceOldest,
      },
    );
  }

  // 12. Unpin a message (idempotent). 204.
  Future<void> unpinMessage(String conversationId, String messageId) async {
    await _dio
        .delete('/api/conversations/$conversationId/messages/$messageId/pin');
  }

  // 13. Pinned messages of a conversation (bounded). Is slice mein UNEXERCISED —
  //     pinned-messages banner (F-M-follow-up) use karega; abhi contract ke liye.
  Future<List<Message>> getPinnedMessages(String conversationId) async {
    final response = await _dio.get('/api/conversations/$conversationId/pinned');
    return (response.data as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 14. Set/replace the caller's reaction — caller-relative aggregate wapas.
  //     Is slice mein UNEXERCISED (reactions UI F-M7).
  Future<List<MessageReaction>> reactToMessage(
    String conversationId,
    String messageId,
    String emoji,
  ) async {
    final response = await _dio.put(
      '/api/conversations/$conversationId/messages/$messageId/reaction',
      data: {'emoji': emoji},
    );
    return (response.data as List)
        .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 15. Remove the caller's reaction (idempotent). Is slice mein UNEXERCISED.
  Future<void> removeReaction(String conversationId, String messageId) async {
    await _dio.delete(
        '/api/conversations/$conversationId/messages/$messageId/reaction');
  }

  // 16. Edit an own message within the edit window — updated message wapas.
  //     Is slice mein UNEXERCISED (koi edit UI entry-point nahi; endpoint ready).
  Future<Message> editMessage(
    String conversationId,
    String messageId,
    String body,
  ) async {
    final response = await _dio.put(
      '/api/conversations/$conversationId/messages/$messageId',
      data: {'body': body},
    );
    return Message.fromJson(response.data as Map<String, dynamic>);
  }

  // 17. Forward source-conversation messages into a target (order preserved).
  //     Is slice mein UNEXERCISED (F-M6 conversation-picker chahiye).
  Future<List<Message>> forwardMessages(
    String sourceConversationId, {
    required String targetConversationId,
    required List<String> messageIds,
  }) async {
    final response = await _dio.post(
      '/api/conversations/$sourceConversationId/messages/forward',
      data: {
        'targetConversationId': targetConversationId,
        'messageIds': messageIds,
      },
    );
    return (response.data as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// Provider — wahi DI chain: dioProvider → repository (connections/people pattern)
final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return MessagingRepository(ref.watch(dioProvider));
});
