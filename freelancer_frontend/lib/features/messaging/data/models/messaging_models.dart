// Backend Messaging DTOs ke Flutter twins — exact same fields.
// (FreelanceApp.Application/Features/Messaging/DTOs/ se mirror kiye gaye)
//
// Enums JSON mein INT aate hain — backend mein JsonStringEnumConverter registered
// nahi (wahi pattern jaisa ConnectionRequestResponse.status ka hai).
//
// Timestamps UTC ISO-8601 hote hain; yahan model mein UTC hi rakhte hain
// (DateTime.parse Z-string se isUtc=true deta hai). `.toLocal()` sirf render pe
// lagta hai (global-audience req #1) — model mein nahi.

// ConversationStatus ka twin (Domain/Enums/ConversationStatus.cs)
enum ConversationStatus {
  pending, // 0 — initiator ne shuru ki, doosre ne respond nahi kiya
  accepted, // 1 — dono taraf messaging khuli
  declined; // 2 — receiver ne thukra di

  static ConversationStatus fromApi(int value) => switch (value) {
        1 => ConversationStatus.accepted,
        2 => ConversationStatus.declined,
        _ => ConversationStatus.pending,
      };
}

// MessageType ka twin (Domain/Enums/MessageType.cs). M1 mein sirf text.
// M3: System (4) — pin/unpin ka centred notice. body hamesha khali; client
// sentence khud banata hai (systemMessageText). Har MessageType switch ko is
// nayi value ko handle karna hoga.
enum MessageType {
  text, // 0
  image, // 1
  file, // 2
  voice, // 3
  system; // 4 — pin/unpin system notice (body empty; client builds the text)

  static MessageType fromApi(int value) => switch (value) {
        1 => MessageType.image,
        2 => MessageType.file,
        3 => MessageType.voice,
        4 => MessageType.system,
        _ => MessageType.text,
      };
}

// SystemEventType ka twin — kaunsa system notice hai. Abhi sirf pin/unpin (M3);
// baaki kinds out of scope. Message par nullable — sirf System-type carry karta.
enum SystemEventType {
  messagePinned, // 0
  messageUnpinned; // 1

  // int? in (missing/unknown → null). System-type ke bagair yeh field null aati.
  static SystemEventType? fromApi(int? value) => switch (value) {
        0 => SystemEventType.messagePinned,
        1 => SystemEventType.messageUnpinned,
        _ => null,
      };
}

// Pin ki lifetime choice — backend PinDuration ke sath 1:1 (required, no default).
// apiValue exactly wahi int bhejta hai jo server expect karta hai (0/1/2).
enum PinDuration {
  twentyFourHours, // 0 — 24 hours
  sevenDays, // 1 — 7 days
  thirtyDays; // 2 — 30 days

  int get apiValue => index;
}

// ConversationUserDto ka twin — 1:1 thread ka "doosra" banda (public fields only)
class ConversationUser {
  final String userId;
  final String fullName;
  final String? headline;
  final String? photoUrl;

  const ConversationUser({
    required this.userId,
    required this.fullName,
    this.headline,
    this.photoUrl,
  });

  factory ConversationUser.fromJson(Map<String, dynamic> json) =>
      ConversationUser(
        userId: json['userId'] as String,
        fullName: json['fullName'] as String? ?? '',
        headline: json['headline'] as String?,
        photoUrl: json['photoUrl'] as String?,
      );
}

// ConversationSummaryDto ka twin — conversation list (accepted) ya requests
// list (pending) ki ek row.
class ConversationSummary {
  final String id;
  final ConversationStatus status;
  final bool isRequest; // incoming pending request hai (backend ne derive kiya)
  final ConversationUser otherUser;
  final String? lastMessagePreview; // ≤120 chars; koi message nahi to null
  final DateTime? lastMessageAt; // UTC; render pe .toLocal()
  final int unreadCount;

  const ConversationSummary({
    required this.id,
    required this.status,
    required this.isRequest,
    required this.otherUser,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        status: ConversationStatus.fromApi(json['status'] as int),
        isRequest: json['isRequest'] as bool? ?? false,
        otherUser:
            ConversationUser.fromJson(json['otherUser'] as Map<String, dynamic>),
        lastMessagePreview: json['lastMessagePreview'] as String?,
        lastMessageAt: json['lastMessageAt'] == null
            ? null
            : DateTime.parse(json['lastMessageAt'] as String),
        unreadCount: json['unreadCount'] as int? ?? 0,
      );
}

// MessageReplyDto ka twin — quoted message ka compact snapshot (reply ke upar).
// Reply UI baad ki slice (F-M5) hai, lekin field ABHI parse karte hain: doosre
// client se bheja message pehle se replyTo carry kar sakta hai, aur chup-chaap
// drop karna baad ki debugging ko confuse karega.
class MessageReply {
  final String messageId;
  final String senderId;
  final String senderName;
  final String bodySnippet; // ~80 char preview; deleted quote pe khali
  final MessageType type;
  final bool isDeleted; // quoted message khud delete-for-everyone hua

  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.bodySnippet,
    required this.type,
    this.isDeleted = false,
  });

  factory MessageReply.fromJson(Map<String, dynamic> json) => MessageReply(
        messageId: json['messageId'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String? ?? '',
        bodySnippet: json['bodySnippet'] as String? ?? '',
        type: MessageType.fromApi(json['type'] as int? ?? 0),
        isDeleted: json['isDeleted'] as bool? ?? false,
      );
}

// MessageReactionSummaryDto ka twin — ek aggregated reaction bucket (GROUP BY
// emoji): emoji + count + kya CALLER ne react kiya. Reactions UI baad ki slice
// (F-M7) hai; abhi sirf parse karte hain (additive).
class MessageReaction {
  final String emoji;
  final int count;
  final bool reactedByMe;

  const MessageReaction({
    required this.emoji,
    required this.count,
    this.reactedByMe = false,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) => MessageReaction(
        emoji: json['emoji'] as String? ?? '',
        count: json['count'] as int? ?? 0,
        reactedByMe: json['reactedByMe'] as bool? ?? false,
      );
}

// MessageDto ka twin — ek single message (F-M2 chat screen use karega).
// M2 fields (replyTo/reactions/editedAt/isPinned/pinnedByUserId/isForwarded)
// sab nullable/defaulted hain — parsing additive rehti hai, purana payload bhi
// bina throw parse hota hai.
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final MessageType type;
  final DateTime createdAt; // UTC; render pe .toLocal()
  final bool isDeleted;

  // ===== Message actions (M2, additive) =====
  final MessageReply? replyTo; // null jab yeh reply nahi
  final List<MessageReaction> reactions; // aggregated buckets ([] jab koi nahi)
  final DateTime? editedAt; // null = kabhi edit nahi
  final bool isPinned; // conversation-scoped pin state
  final String? pinnedByUserId; // null jab pinned nahi
  final bool isForwarded; // forward se bana → "Forwarded" label

  // ===== M3 (additive) =====
  // Pin ki expiry (UTC). null = kabhi expire nahi (sirf legacy rows). Server
  // expired pins ko pinned list / cap / isPinned se pehle hi filter kar deta —
  // client ko filter nahi karna, magar pin ko permanent maan bhi nahi sakta.
  final DateTime? pinExpiresAt;
  // System-type message ka kind (0 pinned / 1 unpinned). Non-system par null.
  final SystemEventType? systemEventType;
  // System message jis pinned/unpinned message ki taraf ishara karti hai.
  // (Tap-to-jump out of scope — sirf carry karte hain; dekho docs/TODO.md.)
  final String? systemTargetMessageId;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.type,
    required this.createdAt,
    this.isDeleted = false,
    this.replyTo,
    this.reactions = const [],
    this.editedAt,
    this.isPinned = false,
    this.pinnedByUserId,
    this.isForwarded = false,
    this.pinExpiresAt,
    this.systemEventType,
    this.systemTargetMessageId,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        senderId: json['senderId'] as String,
        body: json['body'] as String? ?? '',
        type: MessageType.fromApi(json['type'] as int),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isDeleted: json['isDeleted'] as bool? ?? false,
        replyTo: json['replyTo'] == null
            ? null
            : MessageReply.fromJson(json['replyTo'] as Map<String, dynamic>),
        reactions: (json['reactions'] as List?)
                ?.map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        editedAt: json['editedAt'] == null
            ? null
            : DateTime.parse(json['editedAt'] as String),
        isPinned: json['isPinned'] as bool? ?? false,
        pinnedByUserId: json['pinnedByUserId'] as String?,
        isForwarded: json['isForwarded'] as bool? ?? false,
        pinExpiresAt: json['pinExpiresAt'] == null
            ? null
            : DateTime.parse(json['pinExpiresAt'] as String),
        systemEventType:
            SystemEventType.fromApi(json['systemEventType'] as int?),
        systemTargetMessageId: json['systemTargetMessageId'] as String?,
      );
}

// MessagePageDto ka twin — messages CURSOR pagination use karte hain, PagedResult
// nahi. nextCursor = is page ke sab se purane item ka createdAt; use `before`
// bana kar agli (purani) page mangte hain. UTC internally.
class MessagePage {
  final List<Message> items;
  final DateTime? nextCursor; // UTC
  final bool hasMore;

  const MessagePage({
    required this.items,
    this.nextCursor,
    this.hasMore = false,
  });

  factory MessagePage.fromJson(Map<String, dynamic> json) => MessagePage(
        items: (json['items'] as List)
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: json['nextCursor'] == null
            ? null
            : DateTime.parse(json['nextCursor'] as String),
        hasMore: json['hasMore'] as bool? ?? false,
      );
}
