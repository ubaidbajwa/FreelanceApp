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
  system, // 4 — pin/unpin system notice (body empty; client builds the text)
  video; // 5 — F-M5 video message (body carries the optional caption)

  static MessageType fromApi(int value) => switch (value) {
        1 => MessageType.image,
        2 => MessageType.file,
        3 => MessageType.voice,
        4 => MessageType.system,
        5 => MessageType.video,
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
  // F-M5 — last content message ka type (null jab koi message nahi). Uncaptioned
  // media ke liye client localised "Photo"/"Video" render karta hai (server label
  // deliberately nahi bhejta — dekho resolveConversationPreview).
  final MessageType? lastMessageType;
  // F-M8 — agar aakhri message ek document hai to uska filename (backend bheje to).
  // Uncaptioned file preview ke liye resolveConversationPreview isay use karta hai;
  // absent/null ho to localised "Document" label par gir jata hai (additive/defensive).
  final String? lastMessageFileName;
  final DateTime? lastMessageAt; // UTC; render pe .toLocal()
  final int unreadCount;

  // M4 — DOOSRE participant ka read watermark, caller ke perspective se (UTC).
  // null = unhon ne kabhi kuch nahi padha. Sender apne bheje messages pe read tick
  // isi se decide karta hai: message read jab createdAt <= otherLastReadAt (UTC).
  // Ek watermark per conversation — ek saath saare bubbles update hote hain.
  final DateTime? otherLastReadAt;

  const ConversationSummary({
    required this.id,
    required this.status,
    required this.isRequest,
    required this.otherUser,
    this.lastMessagePreview,
    this.lastMessageType,
    this.lastMessageFileName,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.otherLastReadAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) =>
      ConversationSummary(
        id: json['id'] as String,
        status: ConversationStatus.fromApi(json['status'] as int),
        isRequest: json['isRequest'] as bool? ?? false,
        otherUser:
            ConversationUser.fromJson(json['otherUser'] as Map<String, dynamic>),
        lastMessagePreview: json['lastMessagePreview'] as String?,
        // int? in (missing/null → null). fromApi khud int? handle nahi karta, is
        // liye null-check pehle karte hain (koi bhi type=0 ko text mante hain).
        lastMessageType: json['lastMessageType'] == null
            ? null
            : MessageType.fromApi(json['lastMessageType'] as int),
        lastMessageFileName: json['lastMessageFileName'] as String?,
        lastMessageAt: json['lastMessageAt'] == null
            ? null
            : DateTime.parse(json['lastMessageAt'] as String),
        unreadCount: json['unreadCount'] as int? ?? 0,
        otherLastReadAt: json['otherLastReadAt'] == null
            ? null
            : DateTime.parse(json['otherLastReadAt'] as String),
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
  // F-M8 — document ka original filename (sirf File-type quote pe set). Server koi
  // localised "Document" label nahi bhejta (translatable nahi), is liye quoted block
  // yeh filename dikhata hai; null/blank ho to client apna label render karta hai.
  final String? fileName;

  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.bodySnippet,
    required this.type,
    this.isDeleted = false,
    this.fileName,
  });

  factory MessageReply.fromJson(Map<String, dynamic> json) => MessageReply(
        messageId: json['messageId'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String? ?? '',
        bodySnippet: json['bodySnippet'] as String? ?? '',
        type: MessageType.fromApi(json['type'] as int? ?? 0),
        isDeleted: json['isDeleted'] as bool? ?? false,
        fileName: json['fileName'] as String?,
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

  // ===== Media fields (F-M5, additive, nullable) — sirf Image/Video pe set =====
  // Body caption carry karta hai. MediaPublicId server-only deletion handle hai —
  // wire pe kabhi nahi aata. Width/Height se bubble apni jagah image load hone se
  // PEHLE reserve karta hai (koi layout jump nahi). Tombstone (isDeleted) pe server
  // mediaUrl + mediaThumbnailUrl blank kar deta hai (body ki tarah).
  final String? mediaUrl; // full asset — SIRF full-screen viewer mein
  final String? mediaThumbnailUrl; // bubble thumbnail (mediaUrl kabhi bubble mein nahi)
  final int? mediaWidth;
  final int? mediaHeight;
  final int? mediaDurationMs; // video length (m:ss render); image pe null
  final String? mediaMimeType;
  // F-M11 voice — comma-separated amplitude samples (0–100, ≤64), client-computed.
  // null = koi samples nahi → bubble flat bar dikhata hai. Voice pe hi set hota.
  final String? mediaWaveform;
  // F-M8 document (File-type) — original filename + byte size. Documents ke koi
  // thumbnail/width/height/duration/waveform nahi (sab null); size bubble mein
  // human-readable dikhti hai. Tombstone pe server URL + filename dono blank kar deta.
  final String? mediaFileName;
  final int? mediaSizeBytes;

  // ===== F-M11 M7 played receipts (additive, voice only) =====
  // Dono caller-relative booleans, default false → parsing additive rehti hai
  // (purana payload bina in fields ke bhi parse hota). playedByMe = caller ne yeh
  // INCOMING note sun liya; playedByOther = doosre ne caller ki APNI note suni.
  // Asymmetry hi feature hai — dekho resolvePlayedBadge (message_actions.dart).
  final bool playedByMe;
  final bool playedByOther;

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
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaDurationMs,
    this.mediaMimeType,
    this.mediaWaveform,
    this.mediaFileName,
    this.mediaSizeBytes,
    this.playedByMe = false,
    this.playedByOther = false,
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
        mediaUrl: json['mediaUrl'] as String?,
        mediaThumbnailUrl: json['mediaThumbnailUrl'] as String?,
        mediaWidth: json['mediaWidth'] as int?,
        mediaHeight: json['mediaHeight'] as int?,
        mediaDurationMs: json['mediaDurationMs'] as int?,
        mediaMimeType: json['mediaMimeType'] as String?,
        mediaWaveform: json['mediaWaveform'] as String?,
        mediaFileName: json['mediaFileName'] as String?,
        mediaSizeBytes: json['mediaSizeBytes'] as int?,
        playedByMe: json['playedByMe'] as bool? ?? false,
        playedByOther: json['playedByOther'] as bool? ?? false,
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
