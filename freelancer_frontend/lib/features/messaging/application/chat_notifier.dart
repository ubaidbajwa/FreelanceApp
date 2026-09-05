import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/error_mapper.dart';
import '../../../core/realtime/realtime_client.dart';
import '../../../core/realtime/realtime_notifier.dart';
import '../data/messaging_repository.dart';
import '../data/models/messaging_models.dart';
import '../messaging_strings.dart';
import 'active_conversation_provider.dart';
import 'message_actions.dart';
import 'conversation_requests_notifier.dart';
import 'conversations_notifier.dart';

// Ek optimistic-with-pending message ka delivery status (Part 3):
// - confirmed: server ne id + createdAt ke sath wapas kiya
// - pending:   bheja hai, jawab abhi nahi aaya (greyed + clock)
// - failed:    send fail — retry affordance, text kabhi zaya nahi hota
enum ChatSendStatus { confirmed, pending, failed }

// List item ka view-model — server Message ya ek optimistic (pending/failed) entry.
class ChatMessage {
  final String id; // server id, ya optimistic entry ke liye clientId
  final String senderId; // server senderId; optimistic-mine ke liye khali
  final String body;
  final MessageType type;
  final DateTime createdAt; // UTC — render pe .toLocal()
  final ChatSendStatus status;
  final bool isMine;
  final String?
  clientId; // optimistic entries pe set (confirm/retry match ke liye)

  // M2 — delete-for-everyone tombstone (body blanked, not selectable) + pin state.
  final bool isDeleted;
  final bool isPinned;

  // F-M5 — quoted message snapshot; null jab yeh reply nahi.
  // Optimistic entries pe client-side se banaya jata hai, server response pe replace hota hai.
  final MessageReply? replyTo;

  // F-M6 — forward/edit metadata (server-supplied; never set on optimistic entries).
  final bool isForwarded; // true → "Forwarded" label above body
  final DateTime? editedAt; // non-null → "edited" marker next to timestamp; UTC

  // M3 — system notice (pin/unpin). type == system par set; sentence client
  // banata hai (systemMessageText). pinExpiresAt sirf carry hota hai (remaining-
  // time UI out of scope — dekho docs/TODO.md); null = never expires (legacy).
  final SystemEventType? systemEventType;
  final DateTime? pinExpiresAt; // UTC

  // F-M7 — aggregated reaction buckets (emoji + count + reactedByMe display flag).
  // `myReactionEmoji` is the caller's OWN reaction, tracked separately as the
  // source of truth: ReactionChanged events strip reactedByMe, so we re-derive the
  // display flag from this rather than trusting the event (dekho mergeReactionCounts).
  final List<MessageReaction> reactions;
  final String? myReactionEmoji;

  // F-M5 — media (image/video). Server-supplied fields drive the confirmed bubble;
  // mediaWidth/Height reserve space BEFORE the thumbnail loads (no layout jump).
  final String? mediaUrl; // full asset — full-screen viewer only
  final String? mediaThumbnailUrl; // bubble thumbnail
  final int? mediaWidth;
  final int? mediaHeight;
  final int? mediaDurationMs; // video/voice length; null for images
  final String? mediaMimeType;
  // F-M11 voice — comma-separated 0–100 amplitude samples (≤64), or null (flat bar).
  // Set on the optimistic voice bubble from the locally captured samples too.
  final String? mediaWaveform;
  // Local picked/recorded-file path — set on the optimistic bubble and KEPT on a
  // failed one so retry re-sends the SAME file without re-picking/re-recording.
  final String? mediaLocalPath;
  // Real upload progress 0.0–1.0 for a pending media send (dio onSendProgress).
  // Null for non-media or once confirmed.
  final double? uploadProgress;

  // F-M11 M7 — played receipts (voice notes). Caller-relative: playedByMe = I have
  // listened to this INCOMING note; playedByOther = the other person listened to my
  // OWN note. Both default false. The badge reads exactly one of them per direction
  // (resolvePlayedBadge); crossing them is the bug the whole feature must avoid.
  final bool playedByMe;
  final bool playedByOther;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.status,
    required this.isMine,
    this.clientId,
    this.isDeleted = false,
    this.isPinned = false,
    this.replyTo,
    this.isForwarded = false,
    this.editedAt,
    this.systemEventType,
    this.pinExpiresAt,
    this.reactions = const [],
    this.myReactionEmoji,
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaDurationMs,
    this.mediaMimeType,
    this.mediaWaveform,
    this.mediaLocalPath,
    this.uploadProgress,
    this.playedByMe = false,
    this.playedByOther = false,
  });

  ChatMessage copyWith({
    ChatSendStatus? status,
    String? body,
    bool? isDeleted,
    bool? isPinned,
    DateTime? editedAt,
    DateTime? pinExpiresAt,
    List<MessageReaction>? reactions,
    String? myReactionEmoji,
    bool clearMyReaction = false,
    double? uploadProgress,
    bool? playedByMe,
    bool? playedByOther,
  }) => ChatMessage(
    id: id,
    senderId: senderId,
    body: body ?? this.body,
    type: type,
    createdAt: createdAt,
    status: status ?? this.status,
    isMine: isMine,
    clientId: clientId,
    isDeleted: isDeleted ?? this.isDeleted,
    isPinned: isPinned ?? this.isPinned,
    replyTo: replyTo,
    isForwarded: isForwarded,
    editedAt: editedAt ?? this.editedAt,
    systemEventType: systemEventType,
    pinExpiresAt: pinExpiresAt ?? this.pinExpiresAt,
    reactions: reactions ?? this.reactions,
    myReactionEmoji: clearMyReaction
        ? null
        : (myReactionEmoji ?? this.myReactionEmoji),
    // Media fields never change after creation; a tombstone (isDeleted) has its
    // URLs blanked server-side and arrives that way, so nothing to clear here.
    mediaUrl: mediaUrl,
    mediaThumbnailUrl: mediaThumbnailUrl,
    mediaWidth: mediaWidth,
    mediaHeight: mediaHeight,
    mediaDurationMs: mediaDurationMs,
    mediaMimeType: mediaMimeType,
    mediaWaveform: mediaWaveform,
    mediaLocalPath: mediaLocalPath,
    uploadProgress: uploadProgress ?? this.uploadProgress,
    playedByMe: playedByMe ?? this.playedByMe,
    playedByOther: playedByOther ?? this.playedByOther,
  );
}

class ChatState {
  // NEWEST-FIRST list. (UI ListView(reverse: true) isay invert karta hai —
  // dekho chat_screen.dart ka comment.)
  final List<ChatMessage> messages;
  final bool isLoading; // initial load
  final bool isLoadingOlder; // older page append
  final bool hasMore; // aur purane messages bache hain
  final DateTime? nextCursor; // UTC — agli older page ka `before`
  final String? error; // initial load fail
  final bool
  loadOlderFailed; // older page fail (chup-chaap; user dobara scroll kar sakta)

  // Conversation state (Part 1) — summary se seed hoti hai; accept/403 pe badalti.
  final ConversationStatus?
  status; // null = unknown (summary ke bagair cold open)
  final bool isRequest; // pending + kisi aur ne shuru ki (State C ka signal)
  final String? otherUserId; // own-vs-other bubble ke liye (1:1)
  final ConversationUser? otherUser; // cold open / bg-refetch ka resolved user
  final bool actionBusy; // accept/decline in-flight (State C)

  // 403/404 from getConversation — read-only infoStrip footer. Transport errors use `error` instead.
  final String? accessError;

  // 403 on sendMessage: restored to composer if refetched state is still State A.
  // Screen clears this after restoring via clearTextRestore().
  final String? textToRestore;

  // F-M5 — a media send failed for a reason the user must SEE once (e.g. the
  // server's 400 "video too long"). The failed bubble already offers retry; this
  // carries the specific message for a one-shot snackbar. Screen clears it after
  // showing via clearSendError(). Text sends don't use this (retry bubble suffices).
  final String? sendError;

  // Fan-out signal: true when a new message arrived via hub. Screen scrolls to
  // bottom if user is near it, then calls clearScrollSignal().
  final bool scrollToLatest;

  // Selection mode (F-M4). Empty = not selecting. autoDispose provider means this
  // never survives leaving the screen — a fresh notifier starts with an empty set.
  final Set<String> selectedMessageIds;
  // F-M7 — reaction bar visibility is explicit because pin cap (409) must keep
  // selection for the replace retry while hiding the floating bar.
  final bool reactionBarVisible;

  // F-M5 — reply draft: set when user swipes or taps reply in toolbar; cleared
  // on send (or X button). Composer preview reads this; optimistic bubble uses it.
  final MessageReply? draftReply;

  // F-M6 — pinned banner: loaded from getPinnedMessages on open(); updated
  // in-place when MessagePinChanged arrives (spec: same event, not a refetch).
  final List<ChatMessage> pinnedMessages;
  // Which pin the banner currently shows (cycles on tap).
  final int pinnedIndex;
  // Edit mode: non-null when the user has tapped "Edit" on a message.
  final EditDraft? draftEdit;

  // M4 — the OTHER participant's read watermark (UTC), held ONCE per conversation
  // (mirrors the backend, which sends one timestamp not a per-message flag). Every
  // own bubble derives its tick from this single value via resolveTickState. null =
  // they've never read. Seeded from the summary; advanced by the ConversationRead
  // event (monotonically — never moved backwards, see _mergeReadWatermark).
  final DateTime? otherLastReadAt;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isLoadingOlder = false,
    this.hasMore = false,
    this.nextCursor,
    this.error,
    this.loadOlderFailed = false,
    this.status,
    this.isRequest = false,
    this.otherUserId,
    this.otherUser,
    this.actionBusy = false,
    this.accessError,
    this.textToRestore,
    this.sendError,
    this.scrollToLatest = false,
    this.selectedMessageIds = const {},
    this.reactionBarVisible = false,
    this.draftReply,
    this.pinnedMessages = const [],
    this.pinnedIndex = 0,
    this.draftEdit,
    this.otherLastReadAt,
  });

  bool get isSelecting => selectedMessageIds.isNotEmpty;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isLoadingOlder,
    bool? hasMore,
    DateTime? nextCursor,
    String? error,
    bool clearError = false,
    bool? loadOlderFailed,
    ConversationStatus? status,
    bool? isRequest,
    String? otherUserId,
    ConversationUser? otherUser,
    bool? actionBusy,
    String? accessError,
    String? textToRestore,
    bool clearTextRestore = false,
    String? sendError,
    bool clearSendError = false,
    bool? scrollToLatest,
    bool clearScrollToLatest = false,
    Set<String>? selectedMessageIds,
    bool? reactionBarVisible,
    MessageReply? draftReply,
    bool clearDraftReply = false,
    List<ChatMessage>? pinnedMessages,
    int? pinnedIndex,
    EditDraft? draftEdit,
    bool clearDraftEdit = false,
    DateTime? otherLastReadAt,
  }) => ChatState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
    hasMore: hasMore ?? this.hasMore,
    nextCursor: nextCursor ?? this.nextCursor,
    error: clearError ? null : (error ?? this.error),
    loadOlderFailed: loadOlderFailed ?? this.loadOlderFailed,
    status: status ?? this.status,
    isRequest: isRequest ?? this.isRequest,
    otherUserId: otherUserId ?? this.otherUserId,
    otherUser: otherUser ?? this.otherUser,
    actionBusy: actionBusy ?? this.actionBusy,
    accessError: accessError ?? this.accessError,
    textToRestore: clearTextRestore
        ? null
        : (textToRestore ?? this.textToRestore),
    sendError: clearSendError ? null : (sendError ?? this.sendError),
    scrollToLatest: clearScrollToLatest
        ? false
        : (scrollToLatest ?? this.scrollToLatest),
    selectedMessageIds: selectedMessageIds ?? this.selectedMessageIds,
    reactionBarVisible: reactionBarVisible ?? this.reactionBarVisible,
    draftReply: clearDraftReply ? null : (draftReply ?? this.draftReply),
    pinnedMessages: pinnedMessages ?? this.pinnedMessages,
    pinnedIndex: pinnedIndex ?? this.pinnedIndex,
    draftEdit: clearDraftEdit ? null : (draftEdit ?? this.draftEdit),
    otherLastReadAt: otherLastReadAt ?? this.otherLastReadAt,
  );
}

// Result of a (possibly multi-message) delete. Partial success is reported, not
// swallowed: the caller removes/tombstones successes and surfaces the failures.
class DeleteOutcome {
  final int succeeded;
  final int failed;
  final Object? firstError; // for appErrorMessage on total failure

  const DeleteOutcome({
    required this.succeeded,
    required this.failed,
    this.firstError,
  });
}

// Result of a pin attempt. The 409-at-cap case is a FIRST-CLASS outcome, not a
// generic failure: the screen branches on `capReached` to show the replace-oldest
// dialog and then retries with replaceOldest:true (spec Part 3). `failed` carries
// a user-facing message; `success`/`capReached` carry none.
enum PinOutcomeKind { success, capReached, failed }

class PinOutcome {
  final PinOutcomeKind kind;
  final String? message; // only set for failed
  const PinOutcome(this.kind, {this.message});

  static const success = PinOutcome(PinOutcomeKind.success);
  static const capReached = PinOutcome(PinOutcomeKind.capReached);
}

// Edit mode ka draft — messageId + original body (trim'd) for unchanged-body no-op detection.
class EditDraft {
  final String messageId;
  final String originalBody;
  const EditDraft({required this.messageId, required this.originalBody});
}

// autoDispose provider (neeche): screen pop pe fresh — har open naya notifier
// (koi stale flash nahi). Base `Notifier` hi rehta hai; autoDispose provider-level modifier hai.
class ChatNotifier extends Notifier<ChatState> {
  static const _pageSize = 30;

  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);

  // Set by open(); empty string before first open() so fan-out events from other
  // conversations are dropped safely (no LateInitializationError).
  String _conversationId = '';
  int _seq = 0; // stale-token guard (People/conversations wala pattern)
  int _clientCounter = 0;
  // F-M7 — message ids with a reaction call in flight. A second tap on the same
  // message while its call is pending is dropped, so a double-tap can never spawn
  // two competing in-flight requests (Part 4).
  final Set<String> _reactionInFlight = {};
  Timer? _markReadTimer;
  Timer? _reconnectDebounce;
  // True once the first open() completes its load (success OR error).
  // _reconnectRefetch blocks on this so it never races the initial load —
  // there is no baseline to top up until the baseline exists.
  bool _initialLoadDone = false;
  // connectCount at the moment THIS notifier was built. The global counter is
  // monotonic — `> 1` is permanently true after the app's first reconnect, so
  // every chat open was scheduling a reconnect refetch. A gap is only possible
  // when a connect lands AFTER this screen opened, i.e. count rises above this.
  int _baselineConnectCount = 0;

  // Debug-only diagnostics. A silent stale-discard made this bug expensive
  // twice — every discard, isLoading flip, and refetch decision must be visible.
  void _log(String msg) {
    if (kDebugMode) debugPrint('[Chat] $msg');
  }

  @override
  ChatState build() {
    final client = ref.read(realtimeClientProvider);

    final msgSub = client.events
        .where((e) => e.name == 'MessageReceived')
        .listen(_onMessageReceived);

    final acceptedSub = client.events
        .where((e) => e.name == 'ConversationAccepted')
        .listen(_onConversationAccepted);

    // M2 message-action fan-out. Delete-for-me deliberately fires NO event (it is
    // private to one user), so there is nothing to handle for it.
    final deletedSub = client.events
        .where((e) => e.name == 'MessageDeleted')
        .listen(_onMessageDeleted);
    final pinSub = client.events
        .where((e) => e.name == 'MessagePinChanged')
        .listen(_onMessagePinChanged);
    final editedSub = client.events
        .where((e) => e.name == 'MessageEdited')
        .listen(_onMessageEdited);
    final reactionSub = client.events
        .where((e) => e.name == 'ReactionChanged')
        .listen(_onReactionChanged);

    // M4 read receipts: the other side read the conversation → advance the
    // watermark so every own bubble re-evaluates its tick from one value.
    final readSub = client.events
        .where((e) => e.name == 'ConversationRead')
        .listen(_onConversationRead);

    // M7 played receipts: fires to the SENDER only, on the play that actually
    // inserted the record → it always means "they played MINE". Set playedByOther.
    final playedSub = client.events
        .where((e) => e.name == 'MessagePlayed')
        .listen(_onMessagePlayed);

    // Reconnect gap: if socket reconnects while chat is open, fetch missed messages.
    // Fan-out events are not replayed — without this, the chat and tile disagree.
    //
    // The trigger is RELATIVE to this notifier's lifetime, not absolute.
    // `connectCount > 1` was the bug: the counter is global and monotonic, so
    // after the app's first reconnect it is permanently true and every chat
    // open scheduled a refetch. Only a count ABOVE the baseline captured here
    // means a reconnect happened after this screen opened — the only case
    // where a gap is possible. `count > 1` is kept so a notifier built before
    // the app's very first connect doesn't refetch on that connect (no gap).
    _baselineConnectCount = ref
        .read(realtimeNotifierProvider.notifier)
        .connectCount;
    ref.listen<RealtimeConnectionState>(realtimeNotifierProvider, (_, next) {
      final count = ref.read(realtimeNotifierProvider.notifier).connectCount;
      if (next == RealtimeConnectionState.connected &&
          count > _baselineConnectCount &&
          count > 1) {
        _log(
          'reconnect refetch scheduled '
          '(baseline=$_baselineConnectCount, count=$count)',
        );
        _scheduleReconnectRefresh();
      }
    });

    // activeConversationProvider is cleared in ChatScreen.dispose() — not here.
    // Riverpod 3 forbids modifying other providers inside onDispose lifecycle callbacks.
    ref.onDispose(() {
      msgSub.cancel();
      acceptedSub.cancel();
      deletedSub.cancel();
      pinSub.cancel();
      editedSub.cancel();
      reactionSub.cancel();
      readSub.cancel();
      playedSub.cancel();
      _markReadTimer?.cancel();
      _reconnectDebounce?.cancel();
    });

    return const ChatState(isLoading: true);
  }

  // Screen open pe ek baar — summary se state seed, messages load, markRead.
  // Cold open (summary == null): getConversation pehle → status/user milta hai → messages.
  // Hot open (summary != null): messages foran (summary already seeded) → bg reconciliation.
  Future<void> open({
    required String conversationId,
    ConversationSummary? summary,
  }) async {
    _conversationId = conversationId;
    ref.read(activeConversationProvider.notifier).setActive(conversationId);

    final mySeq = ++_seq;
    _initialLoadDone = false; // reset for this load cycle
    _log(
      'open($conversationId) seq=$mySeq '
      'cold=${summary == null} — isLoading → true',
    );

    state = ChatState(
      isLoading: true,
      status: summary?.status,
      isRequest: summary?.isRequest ?? false,
      otherUserId: summary?.otherUser.userId,
      otherUser: summary?.otherUser,
      // Seed the read watermark from the summary (hot open). Cold open has no
      // summary — _openCold picks it up from the getConversation fetch.
      otherLastReadAt: summary?.otherLastReadAt,
    );

    // Hot open: unreadCount summary mein hai, foran markRead.
    // Cold open: summary null hai, unreadCount _openCold ke baad maloom hoga.
    if ((summary?.unreadCount ?? 0) > 0) {
      _markReadSafe();
    }

    try {
      if (summary == null) {
        await _openCold(conversationId, mySeq);
      } else {
        await _openHot(conversationId, summary, mySeq);
      }
    } finally {
      // Structural guarantee: isLoading CANNOT survive open() for the current
      // sequence. Two cases:
      //   mySeq == _seq → we are the latest open(); clear any leftover isLoading.
      //   mySeq != _seq → a newer open() is in flight; it owns isLoading and will
      //                   clear it via its own finally. We must not touch it.
      // _initialLoadDone is only promoted when we are the latest load so that
      // _reconnectRefetch never fires against a baseline that doesn't exist yet.
      if (mySeq == _seq) {
        _initialLoadDone = true;
        if (state.isLoading) {
          _log('open finally: seq=$mySeq — isLoading → false (leftover clear)');
          state = state.copyWith(isLoading: false);
        } else {
          _log('open finally: seq=$mySeq — isLoading already false');
        }
      } else {
        _log(
          'open finally: seq=$mySeq superseded by seq=$_seq — '
          'newer open owns isLoading',
        );
      }
    }
  }

  Future<void> _openCold(String conversationId, int mySeq) async {
    try {
      _log('getConversation start (seq=$mySeq)');
      final summary = await _repo.getConversation(conversationId);
      _log('getConversation done (seq=$mySeq)');
      if (mySeq != _seq) {
        _log('STALE DISCARD in _openCold: mySeq=$mySeq, _seq=$_seq');
        return;
      }
      state = state.copyWith(
        status: summary.status,
        isRequest: summary.isRequest,
        otherUser: summary.otherUser,
        otherUserId: summary.otherUser.userId,
        // A background reconcile must never regress a fresher watermark that a
        // ConversationRead event already delivered — merge, don't overwrite.
        otherLastReadAt: _mergeReadWatermark(
          state.otherLastReadAt,
          summary.otherLastReadAt,
        ),
      );
      if (summary.unreadCount > 0) _markReadSafe();
      await _loadMessages(conversationId, mySeq);
    } on DioException catch (e) {
      if (mySeq != _seq) {
        _log(
          'STALE DISCARD in _openCold error path: mySeq=$mySeq, _seq=$_seq'
          ' — open finally will clear isLoading',
        );
        return;
      }
      _log(
        '_openCold DioException status=${e.response?.statusCode} '
        '(seq=$mySeq) — isLoading → false',
      );
      if (e.response?.statusCode == 403) {
        state = state.copyWith(
          isLoading: false,
          accessError: MessagingStrings.chat403NotParticipant,
        );
      } else if (e.response?.statusCode == 404) {
        state = state.copyWith(
          isLoading: false,
          accessError: MessagingStrings.chat404NotFound,
        );
      } else {
        state = state.copyWith(isLoading: false, error: _messageOf(e));
      }
    } catch (e) {
      if (mySeq != _seq) {
        _log(
          'STALE DISCARD in _openCold catch: mySeq=$mySeq, _seq=$_seq'
          ' — open finally will clear isLoading',
        );
        return;
      }
      _log('_openCold error $e (seq=$mySeq) — isLoading → false');
      state = state.copyWith(isLoading: false, error: _messageOf(e));
    }
  }

  Future<void> _openHot(
    String conversationId,
    ConversationSummary summary,
    int mySeq,
  ) async {
    await _loadMessages(conversationId, mySeq);
    // Fire-and-forget background reconciliation — only if open() wasn't interrupted.
    if (mySeq == _seq) _refetchAndReconcile(conversationId, mySeq);
  }

  Future<void> _loadMessages(String conversationId, int mySeq) async {
    try {
      _log('getMessages start (seq=$mySeq)');
      final page = await _repo.getMessages(conversationId, limit: _pageSize);
      _log('getMessages done: ${page.items.length} items (seq=$mySeq)');
      if (mySeq != _seq) {
        // Skip assigning the stale data — but isLoading is NOT leaked here:
        // the newer open() that bumped _seq clears it in its own finally.
        _log(
          'STALE DISCARD in _loadMessages: mySeq=$mySeq, _seq=$_seq'
          ' — data dropped, newer open finally owns isLoading',
        );
        return;
      }
      _log('_loadMessages success (seq=$mySeq) — isLoading → false');
      state = state.copyWith(
        messages: page.items.map(_fromServer).toList(),
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoading: false,
        clearError: true,
      );
      // Fire-and-forget: populate the pin banner after messages are loaded.
      // Failures are silent — the banner simply won't appear.
      _loadPinnedMessages();
    } catch (e) {
      if (mySeq != _seq) {
        _log(
          'STALE DISCARD in _loadMessages catch: mySeq=$mySeq, _seq=$_seq'
          ' — newer open finally owns isLoading',
        );
        return;
      }
      _log('_loadMessages error $e (seq=$mySeq) — isLoading → false');
      state = state.copyWith(isLoading: false, error: _messageOf(e));
    }
  }

  // Background reconciliation: if server disagrees with seeded summary, update state.
  // Transport failures silently ignored — screen already rendered; one missed reconcile is fine.
  Future<void> _refetchAndReconcile(String conversationId, int mySeq) async {
    try {
      final summary = await _repo.getConversation(conversationId);
      if (mySeq != _seq) return;
      state = state.copyWith(
        status: summary.status,
        isRequest: summary.isRequest,
        otherUser: summary.otherUser,
        otherUserId: summary.otherUser.userId,
        // A background reconcile must never regress a fresher watermark that a
        // ConversationRead event already delivered — merge, don't overwrite.
        otherLastReadAt: _mergeReadWatermark(
          state.otherLastReadAt,
          summary.otherLastReadAt,
        ),
      );
    } on DioException catch (e) {
      if (mySeq != _seq) return;
      if (e.response?.statusCode == 403) {
        state = state.copyWith(
          accessError: MessagingStrings.chat403NotParticipant,
        );
      } else if (e.response?.statusCode == 404) {
        state = state.copyWith(accessError: MessagingStrings.chat404NotFound);
      }
      // transport error — keep seeded state; don't degrade an already-rendered screen
    } catch (_) {
      if (mySeq != _seq) return;
    }
  }

  ChatMessage _fromServer(Message m) => ChatMessage(
    id: m.id,
    senderId: m.senderId,
    body: m.body,
    type: m.type,
    createdAt: m.createdAt,
    status: ChatSendStatus.confirmed,
    // 1:1 — jo other nahi, wo main. otherUserId null (unknown) ho to
    // safe default: other (unknown state read-only hoti hai).
    isMine: state.otherUserId != null && m.senderId != state.otherUserId,
    isDeleted: m.isDeleted,
    isPinned: m.isPinned,
    replyTo: m.replyTo,
    isForwarded: m.isForwarded,
    editedAt: m.editedAt,
    systemEventType: m.systemEventType,
    pinExpiresAt: m.pinExpiresAt,
    // F-M7 — carry the server buckets and seed the caller's own emoji from the
    // reactedByMe flag (authoritative on the initial fetch, unlike the event).
    reactions: m.reactions,
    myReactionEmoji: _myEmojiOf(m.reactions),
    // F-M5 — media fields (null for text). A confirmed server entry never has a
    // local path / progress; those live only on optimistic bubbles.
    mediaUrl: m.mediaUrl,
    mediaThumbnailUrl: m.mediaThumbnailUrl,
    mediaWidth: m.mediaWidth,
    mediaHeight: m.mediaHeight,
    mediaDurationMs: m.mediaDurationMs,
    mediaMimeType: m.mediaMimeType,
    mediaWaveform: m.mediaWaveform,
    // F-M11 M7 — played receipts arrive on the server entry (caller-relative).
    playedByMe: m.playedByMe,
    playedByOther: m.playedByOther,
  );

  // The caller's own reaction emoji (at most one per user), or null. Used only when
  // seeding from a server payload where reactedByMe is trustworthy (fetch/PUT).
  static String? _myEmojiOf(List<MessageReaction> reactions) {
    for (final r in reactions) {
      if (r.reactedByMe) return r.emoji;
    }
    return null;
  }

  // Older page — user list ke TOP (purane) tak scroll kare to. Scratch se kabhi
  // re-request nahi. Duplicate in-flight guard + stale-token guard.
  Future<void> loadOlder() async {
    if (state.isLoadingOlder || !state.hasMore || state.nextCursor == null) {
      return;
    }
    final mySeq =
        _seq; // snapshot only — increment NAHI (open() jeetega agar concurrent)
    state = state.copyWith(isLoadingOlder: true, loadOlderFailed: false);
    try {
      final page = await _repo.getMessages(
        _conversationId,
        before: state.nextCursor,
        limit: _pageSize,
      );
      if (mySeq != _seq) return;
      // List newest-first hai → purane messages END pe append hote hain.
      state = state.copyWith(
        messages: [...state.messages, ...page.items.map(_fromServer)],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingOlder: false,
      );
    } catch (_) {
      if (mySeq != _seq) return;
      state = state.copyWith(isLoadingOlder: false, loadOlderFailed: true);
    }
  }

  // Part 3 — optimistic-with-pending. Pessimistic NAHI: bubble foran dikhe
  // (pending), input clear ho; server jawab pe confirm/fail.
  // F-M5: draftReply snapshot le kar optimistic bubble mein set karta hai,
  // phir draft clear karta hai (composer preview hatne ke liye).
  Future<void> send(String rawBody) async {
    final body = rawBody.trim();
    if (body.isEmpty) return;

    final draft = state.draftReply; // snapshot before clearing
    final clientId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_clientCounter++}';
    final optimistic = ChatMessage(
      id: clientId,
      senderId: '',
      body: body,
      type: MessageType.text,
      createdAt: DateTime.now().toUtc(),
      status: ChatSendStatus.pending,
      isMine: true,
      clientId: clientId,
      replyTo: draft,
    );
    // Newest-first list → naya message FRONT pe.
    // draftReply isi state update mein clear — composer preview usi lamhe gayab.
    state = state.copyWith(
      messages: [optimistic, ...state.messages],
      clearDraftReply: true,
    );

    await _dispatchSend(clientId, body, replyToMessageId: draft?.messageId);
  }

  // Failed bubble retry — wahi payload dobara, pehle pending.
  // replyTo failed bubble pe preserved hai — retry bhi wahi link bhejta hai.
  // F-M5: media failure pe mediaLocalPath bubble pe saved rehta hai, is liye retry
  // WAHI file dobara upload karta hai (re-pick ki zaroorat nahi) — progress 0 se.
  Future<void> retry(String clientId) async {
    final msg = state.messages
        .where((m) => m.clientId == clientId)
        .cast<ChatMessage?>()
        .firstWhere((m) => m != null, orElse: () => null);
    if (msg == null || msg.status == ChatSendStatus.pending) return;
    final localPath = msg.mediaLocalPath;
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.clientId == clientId
                ? m.copyWith(
                    status: ChatSendStatus.pending,
                    uploadProgress: localPath != null ? 0.0 : null,
                  )
                : m,
          )
          .toList(),
    );
    if (localPath != null) {
      await _dispatchSendMedia(
        clientId,
        localPath,
        caption: msg.body.isEmpty ? null : msg.body,
        replyToMessageId: msg.replyTo?.messageId,
        // Voice: the locally captured waveform is preserved on the failed bubble,
        // so retry re-sends it (never re-recorded). Null for image/video.
        waveform: msg.mediaWaveform,
      );
    } else {
      await _dispatchSend(
        clientId,
        msg.body,
        replyToMessageId: msg.replyTo?.messageId,
      );
    }
  }

  // Part 4 — media send: optimistic bubble showing the LOCAL file with a progress
  // overlay, then dio onSendProgress drives real progress; on success the server
  // entry (carrying the Cloudinary URLs) replaces it. `kind` decides the optimistic
  // type so the bubble renders as an image or a video immediately. draftReply is
  // carried through exactly like text and cleared in the same state write.
  Future<void> sendMedia({
    required String path,
    required PickedMediaKind kind,
    String? caption,
  }) async {
    final trimmedCaption = caption?.trim() ?? '';
    final draft = state.draftReply; // snapshot before clearing
    final clientId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_clientCounter++}';
    final optimistic = ChatMessage(
      id: clientId,
      senderId: '',
      body: trimmedCaption,
      type: kind == PickedMediaKind.image
          ? MessageType.image
          : MessageType.video,
      createdAt: DateTime.now().toUtc(),
      status: ChatSendStatus.pending,
      isMine: true,
      clientId: clientId,
      replyTo: draft,
      mediaLocalPath: path,
      uploadProgress: 0.0,
    );
    state = state.copyWith(
      messages: [optimistic, ...state.messages],
      clearDraftReply: true,
    );
    await _dispatchSendMedia(
      clientId,
      path,
      caption: trimmedCaption.isEmpty ? null : trimmedCaption,
      replyToMessageId: draft?.messageId,
    );
  }

  // Part 6 — voice send. Reuses the media path (same optimistic bubble, progress,
  // clientId reconciliation, retry-keeps-file). The optimistic bubble shows the
  // locally captured waveform + duration immediately (no caption — voice has none).
  // A reply in progress is carried through to the note, exactly like media.
  Future<void> sendVoice({
    required String path,
    required int durationMs,
    String? waveform,
  }) async {
    final draft = state.draftReply; // snapshot before clearing
    final clientId =
        'local-${DateTime.now().microsecondsSinceEpoch}-${_clientCounter++}';
    final optimistic = ChatMessage(
      id: clientId,
      senderId: '',
      body: '',
      type: MessageType.voice,
      createdAt: DateTime.now().toUtc(),
      status: ChatSendStatus.pending,
      isMine: true,
      clientId: clientId,
      replyTo: draft,
      mediaLocalPath: path,
      mediaDurationMs: durationMs,
      mediaWaveform: waveform,
      uploadProgress: 0.0,
    );
    state = state.copyWith(
      messages: [optimistic, ...state.messages],
      clearDraftReply: true,
    );
    await _dispatchSendMedia(
      clientId,
      path,
      replyToMessageId: draft?.messageId,
      waveform: waveform,
    );
  }

  Future<void> _dispatchSendMedia(
    String clientId,
    String path, {
    String? caption,
    String? replyToMessageId,
    String? waveform,
  }) async {
    try {
      final saved = await _repo.sendMediaMessage(
        _conversationId,
        path,
        caption: caption,
        replyToMessageId: replyToMessageId,
        waveform: waveform,
        onSendProgress: (sent, total) =>
            _updateUploadProgress(clientId, sent, total),
      );
      // Dedupe with fan-out — same race the text path already solves: a
      // MessageReceived may arrive before the HTTP response and already append the
      // confirmed entry. If the server id is present, drop the pending bubble.
      if (state.messages.any((m) => m.id == saved.id)) {
        state = state.copyWith(
          messages: state.messages
              .where((m) => m.clientId != clientId)
              .toList(),
        );
      } else {
        state = state.copyWith(
          messages: state.messages
              .map((m) => m.clientId == clientId ? _fromServer(saved) : m)
              .toList(),
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        // Same as text: the server rejected for a state reason — remove the
        // optimistic bubble and refetch the real state rather than guessing. No
        // caption is restored (there is no composer text for media).
        state = state.copyWith(
          messages: state.messages
              .where((m) => m.clientId != clientId)
              .toList(),
        );
        _refetchAndReconcile(_conversationId, _seq);
      } else {
        // Any other failure (incl. a 400 for an over-long video) → mark failed,
        // KEEPING the local path so retry re-uploads without re-picking, and surface
        // the server's specific message once via sendError (the screen snackbars it).
        _markFailed(clientId);
        state = state.copyWith(sendError: _messageOf(e));
      }
    } catch (e) {
      _markFailed(clientId);
      state = state.copyWith(sendError: _messageOf(e));
    }
  }

  // Screen calls this after showing the one-shot media send error snackbar.
  void clearSendError() {
    if (state.sendError == null) return;
    state = state.copyWith(clearSendError: true);
  }

  // Drive the pending media bubble's progress bar from dio's byte counts.
  void _updateUploadProgress(String clientId, int sent, int total) {
    if (total <= 0) return;
    final p = (sent / total).clamp(0.0, 1.0);
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.clientId == clientId ? m.copyWith(uploadProgress: p) : m,
          )
          .toList(),
    );
  }

  Future<void> _dispatchSend(
    String clientId,
    String body, {
    String? replyToMessageId,
  }) async {
    try {
      final saved = await _repo.sendMessage(
        _conversationId,
        body,
        replyToMessageId: replyToMessageId,
      );
      // Dedupe: fan-out may have arrived before the REST response and already
      // appended the confirmed entry. If the server id is already in the list,
      // remove the pending bubble — the confirmed entry is already there.
      if (state.messages.any((m) => m.id == saved.id)) {
        state = state.copyWith(
          messages: state.messages
              .where((m) => m.clientId != clientId)
              .toList(),
        );
      } else {
        // Normal path: replace pending bubble with confirmed server entry.
        state = state.copyWith(
          messages: state.messages
              .map((m) => m.clientId == clientId ? _fromServer(saved) : m)
              .toList(),
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        // 403 means server rejected for a known reason (status may have changed).
        // Rather than hardcoding a cause, refetch and render whatever state comes
        // back — the server is the single source of truth. A future reader should
        // not "improve" this into an error taxonomy per-status-reason; refetching
        // asks one question instead: what is the actual state now?
        state = state.copyWith(
          messages: state.messages
              .where((m) => m.clientId != clientId)
              .toList(),
        );
        _refetchAfterSend403(body); // fire-and-forget; updates state when done
      } else {
        _markFailed(clientId);
      }
    } catch (_) {
      _markFailed(clientId);
    }
  }

  // Called after a 403 on sendMessage. Refetches conversation state and reconciles.
  // Restores typed text to composer ONLY if refetched state is still State A (accepted).
  Future<void> _refetchAfterSend403(String body) async {
    try {
      final summary = await _repo.getConversation(_conversationId);
      state = state.copyWith(
        status: summary.status,
        isRequest: summary.isRequest,
        otherUser: summary.otherUser,
        otherUserId: summary.otherUser.userId,
        otherLastReadAt: _mergeReadWatermark(
          state.otherLastReadAt,
          summary.otherLastReadAt,
        ),
        textToRestore: summary.status == ConversationStatus.accepted
            ? body
            : null,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        state = state.copyWith(
          accessError: MessagingStrings.chat403NotParticipant,
        );
      } else if (e.response?.statusCode == 404) {
        state = state.copyWith(accessError: MessagingStrings.chat404NotFound);
      }
      // other / transport errors: keep existing state, optimistic bubble already removed
    } catch (_) {
      // transport error — same
    }
  }

  // Screen calls this after reading textToRestore to clear it from state.
  void clearTextRestore() {
    state = state.copyWith(clearTextRestore: true);
  }

  // Screen calls this after acting on the autoscroll signal.
  void clearScrollSignal() {
    state = state.copyWith(clearScrollToLatest: true);
  }

  void _markFailed(String clientId) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.clientId == clientId
                ? m.copyWith(status: ChatSendStatus.failed)
                : m,
          )
          .toList(),
    );
  }

  // ── Hub event handlers ────────────────────────────────────────────────────

  void _onMessageReceived(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;

    final id = e.payload['id'] as String?;
    if (id == null) return;

    // Dedupe: if REST response already confirmed this message it's in the list
    // with this server id. Pending optimistic bubbles use a clientId (local-…),
    // so the check doesn't match them.
    if (state.messages.any((m) => m.id == id)) return;

    try {
      final msg = _fromServer(Message.fromJson(e.payload));
      state = state.copyWith(
        messages: [msg, ...state.messages],
        scrollToLatest: true,
      );
      // Only debounce markRead for messages from the other person.
      if (!msg.isMine) _scheduleMarkRead();
    } catch (_) {
      // Malformed payload — skip; message will appear on next manual refresh
    }
  }

  void _onConversationAccepted(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    // State B → State A: the other side accepted the request. Unlock composer.
    state = state.copyWith(
      status: ConversationStatus.accepted,
      isRequest: false,
    );
  }

  // MessageDeleted fires ONLY for delete-for-everyone → tombstone in place. The
  // body is blanked and isDeleted set; a tombstone is not selectable, so it is
  // also dropped from any active selection.
  void _onMessageDeleted(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final id = e.payload['messageId'] as String?;
    if (id == null) return;
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == id ? m.copyWith(isDeleted: true, body: '') : m)
          .toList(),
      selectedMessageIds: {...state.selectedMessageIds}..remove(id),
    );
  }

  void _onMessagePinChanged(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final id = e.payload['messageId'] as String?;
    final isPinned = e.payload['isPinned'] as bool?;
    if (id == null || isPinned == null) return;

    // M3: the event now also carries the pin's expiry (nullable UTC). We carry it
    // onto the message so the banner has it (remaining-time UI is out of scope —
    // see docs/TODO.md — but the data must not be dropped).
    final expiresRaw = e.payload['pinExpiresAt'] as String?;
    final pinExpiresAt = expiresRaw == null
        ? null
        : DateTime.tryParse(expiresRaw);

    // Update message list (bubble indicator) and pinned banner together in one
    // state write — spec: "banner must update from the same event, not a refetch".
    final updatedMessages = state.messages
        .map(
          (m) => m.id == id
              ? m.copyWith(isPinned: isPinned, pinExpiresAt: pinExpiresAt)
              : m,
        )
        .toList();

    List<ChatMessage> updatedPinned;
    int updatedIdx = state.pinnedIndex;

    if (isPinned) {
      // Add to banner if the message is currently loaded (in this page).
      // If not loaded, it will appear on next open() — no silent loss.
      ChatMessage? found;
      for (final m in updatedMessages) {
        if (m.id == id) {
          found = m;
          break;
        }
      }
      if (found != null && !state.pinnedMessages.any((m) => m.id == id)) {
        updatedPinned = [...state.pinnedMessages, found];
      } else {
        updatedPinned = state.pinnedMessages;
      }
    } else {
      updatedPinned = state.pinnedMessages.where((m) => m.id != id).toList();
    }
    // Clamp: a removed pin can leave the index past the end — clamp, never crash.
    updatedIdx = clampPinIndex(updatedIdx, updatedPinned.length);

    state = state.copyWith(
      messages: updatedMessages,
      pinnedMessages: updatedPinned,
      pinnedIndex: updatedIdx,
    );
  }

  void _onMessageEdited(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final id = e.payload['id'] as String?;
    final newBody = e.payload['body'] as String?;
    if (id == null || newBody == null) return;
    final editedAtRaw = e.payload['editedAt'] as String?;
    final editedAt = editedAtRaw == null
        ? null
        : DateTime.tryParse(editedAtRaw);
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == id
                ? m.copyWith(body: newBody, editedAt: editedAt ?? m.editedAt)
                : m,
          )
          .toList(),
    );
  }

  // F-M7 — a reaction aggregate changed for some message in this conversation.
  // The event carries authoritative COUNTS but strips reactedByMe (it fans out to
  // both participants and that flag is caller-relative). We merge counts and
  // RE-DERIVE the caller's highlight from our locally-tracked myReactionEmoji, so
  // an event never wipes the caller's own reaction. An event for a message not in
  // local state is ignored; a just-applied optimistic reaction is not double
  // counted because the merge only re-derives the flag, never adds.
  void _onReactionChanged(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final id = e.payload['messageId'] as String?;
    if (id == null) return;
    final idx = state.messages.indexWhere((m) => m.id == id);
    if (idx < 0) return; // not in local state → ignore

    final raw = e.payload['reactions'] as List?;
    if (raw == null) return;
    final incoming = raw
        .whereType<Map>()
        .map((x) => MessageReaction.fromJson(x.cast<String, dynamic>()))
        .toList();

    final msg = state.messages[idx];
    _setReactions(
      id,
      mergeReactionCounts(incoming, msg.myReactionEmoji),
      msg.myReactionEmoji,
    );
  }

  // ── Reactions (F-M7) ──────────────────────────────────────────────────────

  // Optimistic toggle (Part 4): apply locally FIRST, then call the API, rolling
  // back on failure. Unlike delete/pin/edit (pessimistic), a reaction is a low-
  // risk reversible toggle where instant feedback matters and a failure costs one
  // tap. One backend PUT handles add/remove/replace; removal uses DELETE. Returns
  // null on success (or a no-op drop), else a user-facing error to snackbar.
  Future<String?> toggleReaction(String messageId, String emoji) async {
    // Double-tap guard: ignore while a call for this message is in flight.
    if (_reactionInFlight.contains(messageId)) return null;

    final msg = _findById(messageId);
    if (msg == null) return null;
    // Reactions are refused on system messages and tombstones (400) — never call.
    if (msg.isDeleted || msg.type == MessageType.system) return null;

    final prevReactions = msg.reactions;
    final prevMyEmoji = msg.myReactionEmoji;

    // Optimistic local apply.
    final next = applyReactionToggle(prevReactions, prevMyEmoji, emoji);
    _reactionInFlight.add(messageId);
    _setReactions(messageId, next.reactions, next.myEmoji);

    try {
      if (next.myEmoji == null) {
        // Toggled off → explicit removal.
        await _repo.removeReaction(_conversationId, messageId);
      } else {
        // Add / replace → PUT returns the authoritative aggregate. Reconcile the
        // counts against the server (keeps them exact) and keep our own emoji.
        final server = await _repo.reactToMessage(
          _conversationId,
          messageId,
          emoji,
        );
        _setReactions(
          messageId,
          mergeReactionCounts(server, next.myEmoji),
          next.myEmoji,
        );
      }
      return null;
    } catch (e) {
      // Roll back to the previous reaction state.
      _setReactions(messageId, prevReactions, prevMyEmoji);
      return _messageOf(e);
    } finally {
      _reactionInFlight.remove(messageId);
    }
  }

  // Replace one message's reaction buckets + the caller's own emoji in place.
  void _setReactions(
    String id,
    List<MessageReaction> reactions,
    String? myEmoji,
  ) {
    state = state.copyWith(
      messages: state.messages
          .map(
            (m) => m.id == id
                ? m.copyWith(
                    reactions: reactions,
                    myReactionEmoji: myEmoji,
                    clearMyReaction: myEmoji == null,
                  )
                : m,
          )
          .toList(),
    );
  }

  // M4 — the OTHER participant marked THIS conversation read. Fires only to them
  // (never echoed to the reader). We hold ONE watermark; every own bubble derives
  // its tick from it via resolveTickState, so there is no per-message patching.
  //
  // Guard against out-of-order delivery: events can arrive reordered, and a tick
  // that flips ✓✓ → ✓ looks broken. Accept the timestamp ONLY if it is strictly
  // newer than the one held (_mergeReadWatermark enforces monotonicity).
  void _onConversationRead(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final raw = e.payload['lastReadAt'] as String?;
    if (raw == null) return;
    final ts = DateTime.tryParse(raw);
    if (ts == null) return;
    final merged = _mergeReadWatermark(state.otherLastReadAt, ts);
    // No change (stale/duplicate event) → skip the state write entirely.
    if (identical(merged, state.otherLastReadAt) ||
        merged == state.otherLastReadAt) {
      return;
    }
    state = state.copyWith(otherLastReadAt: merged);
  }

  // ── Played receipts (F-M11 M7) ────────────────────────────────────────────

  // The caller started playing an INCOMING note. Optimistically flip the badge —
  // the user pressed play, they know it played; don't wait for the round trip — then
  // fire the receipt. shouldMarkPlayed gates own/non-voice/tombstone/already-played,
  // so a call here is a genuine first play. Resume-after-pause never reaches this:
  // the caller only invokes it on a fresh playback start.
  //
  // On failure: SILENT. A played receipt is invisible and not worth an interruption.
  // Roll the badge back to unplayed so the NEXT play retries naturally, and log.
  Future<void> markPlayed(String messageId) async {
    final msg = _findById(messageId);
    if (msg == null || !shouldMarkPlayed(msg)) return;
    _setPlayedByMe(messageId, true); // optimistic
    try {
      await _repo.markPlayed(_conversationId, messageId);
    } catch (e) {
      _setPlayedByMe(messageId, false); // roll back; next play retries
      debugPrint('markPlayed failed (non-critical): $e');
    }
  }

  void _setPlayedByMe(String id, bool value) {
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == id ? m.copyWith(playedByMe: value) : m)
          .toList(),
    );
  }

  // MessagePlayed reaches the SENDER only, so it always means "they played MINE" —
  // set playedByOther, NEVER playedByMe (crossing them would light my own badge when
  // the other person listens, reading as a bug). An event for a message not in local
  // state is ignored. The server fires it only on the insert, so repeats push nothing.
  void _onMessagePlayed(RealtimeEvent e) {
    final convId = e.payload['conversationId'] as String?;
    if (convId == null || convId != _conversationId) return;
    final id = e.payload['messageId'] as String?;
    if (id == null) return;
    if (!state.messages.any((m) => m.id == id)) return; // not loaded → ignore
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == id ? m.copyWith(playedByOther: true) : m)
          .toList(),
    );
  }

  // Returns the newer of the two watermarks (UTC), never moving backwards. A null
  // candidate leaves the current value; a null current takes the candidate.
  // Comparison is by instant (.toUtc()) — the read tick's UTC rule, see
  // resolveTickState. Equal instants return the current value (no-op signal).
  DateTime? _mergeReadWatermark(DateTime? current, DateTime? candidate) {
    if (candidate == null) return current;
    if (current == null) return candidate.toUtc();
    return candidate.toUtc().isAfter(current.toUtc())
        ? candidate.toUtc()
        : current;
  }

  // ── Selection mode (F-M4) ─────────────────────────────────────────────────

  // Selected messages in CHRONOLOGICAL (oldest-first) order. state.messages is
  // newest-first, so we reverse — copy/forward preserve reading order.
  List<ChatMessage> get selectedMessages =>
      _selectedMessagesFor(state.selectedMessageIds);

  List<ChatMessage> _selectedMessagesFor(Set<String> ids) {
    final sel = state.messages.where((m) => ids.contains(m.id)).toList();
    return sel.reversed.toList();
  }

  ChatMessage? _findById(String id) {
    for (final m in state.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  // Long-press. Tombstones AND system notices are not selectable (no actions
  // apply to them) — the same inert treatment. This guard is why a system
  // message can never reach resolveToolbarActions / resolveDeleteOptions.
  void enterSelection(String messageId) {
    final msg = _findById(messageId);
    if (msg == null || msg.isDeleted || msg.type == MessageType.system) return;
    if (state.selectedMessageIds.contains(messageId)) return;
    _setSelection({...state.selectedMessageIds, messageId});
  }

  // Tap while selecting. Toggling the last one off exits selection mode (empty).
  void toggleSelection(String messageId) {
    final msg = _findById(messageId);
    if (msg == null || msg.isDeleted || msg.type == MessageType.system) return;
    final next = {...state.selectedMessageIds};
    if (!next.remove(messageId)) next.add(messageId);
    _setSelection(next);
  }

  void clearSelection() {
    if (state.selectedMessageIds.isEmpty && !state.reactionBarVisible) return;
    state = state.copyWith(
      selectedMessageIds: const {},
      reactionBarVisible: false,
    );
  }

  void hideReactionBar() {
    if (!state.reactionBarVisible) return;
    state = state.copyWith(reactionBarVisible: false);
  }

  void _setSelection(Set<String> ids) {
    final next = ids.isEmpty ? const <String>{} : Set<String>.unmodifiable(ids);
    state = state.copyWith(
      selectedMessageIds: next,
      reactionBarVisible: shouldShowReactionBar(_selectedMessagesFor(next)),
    );
  }

  // Copy: selected bodies joined by newlines, chronological. Callers gate this on
  // resolveToolbarActions().showCopy (all text, no tombstone).
  String buildCopyText() => selectedMessages.map((m) => m.body).join('\n');

  String copySelectedText() {
    final text = buildCopyText();
    clearSelection();
    return text;
  }

  List<String> forwardSelectedMessageIds() {
    final ids = selectedMessages.map((m) => m.id).toList();
    clearSelection();
    return ids;
  }

  // ── Reply draft (F-M5) ────────────────────────────────────────────────────

  // Swipe or toolbar reply tap pe: ChatMessage se MessageReply banata hai aur draft set karta hai.
  // senderName: mine ke liye khali (widget "You" show karega); other ke liye otherUser.fullName.
  // bodySnippet: body ke pehle 80 chars (server convention match karne ke liye).
  MessageReply _replyFromMessage(ChatMessage m) {
    final snippet = m.body.length > 80 ? m.body.substring(0, 80) : m.body;
    return MessageReply(
      messageId: m.id,
      senderId: m.senderId,
      senderName: m.isMine ? '' : (state.otherUser?.fullName ?? ''),
      bodySnippet: snippet,
      type: m.type,
      isDeleted: m.isDeleted,
    );
  }

  void setDraftReply(ChatMessage m) {
    state = state.copyWith(draftReply: _replyFromMessage(m));
  }

  bool replySelected() {
    final sel = selectedMessages;
    if (sel.length != 1) return false;
    state = state.copyWith(
      draftReply: _replyFromMessage(sel.first),
      selectedMessageIds: const {},
      reactionBarVisible: false,
    );
    return true;
  }

  void clearDraftReply() {
    if (state.draftReply == null) return;
    state = state.copyWith(clearDraftReply: true);
  }

  // ── Pinned banner (F-M6) ─────────────────────────────────────────────────────

  // Non-critical fire-and-forget: called once after _loadMessages succeeds.
  Future<void> _loadPinnedMessages() async {
    if (_conversationId.isEmpty) return;
    try {
      final msgs = await _repo.getPinnedMessages(_conversationId);
      state = state.copyWith(
        pinnedMessages: msgs.map(_fromServer).toList(),
        pinnedIndex: 0,
      );
    } catch (_) {}
  }

  void cyclePin() {
    if (state.pinnedMessages.isEmpty) return;
    state = state.copyWith(
      pinnedIndex: (state.pinnedIndex + 1) % state.pinnedMessages.length,
    );
  }

  Future<String?> unpinFromBanner() async {
    final msgs = state.pinnedMessages;
    if (msgs.isEmpty) return null;
    final idx = state.pinnedIndex.clamp(0, msgs.length - 1);
    final target = msgs[idx];
    try {
      await _repo.unpinMessage(_conversationId, target.id);
      _setPinned(target.id, false);
      final updated = msgs.where((m) => m.id != target.id).toList();
      final newIdx = updated.isEmpty
          ? 0
          : (idx >= updated.length ? updated.length - 1 : idx);
      state = state.copyWith(pinnedMessages: updated, pinnedIndex: newIdx);
      return null;
    } on DioException catch (e) {
      return _messageOf(e);
    } catch (e) {
      return _messageOf(e);
    }
  }

  // ── Edit mode (F-M6) ─────────────────────────────────────────────────────────

  void startEdit(ChatMessage m) {
    state = state.copyWith(
      draftEdit: EditDraft(messageId: m.id, originalBody: m.body.trim()),
    );
  }

  bool startEditSelected() {
    final sel = selectedMessages;
    if (sel.length != 1) return false;
    state = state.copyWith(
      draftEdit: EditDraft(
        messageId: sel.first.id,
        originalBody: sel.first.body.trim(),
      ),
      selectedMessageIds: const {},
      reactionBarVisible: false,
    );
    return true;
  }

  void cancelEdit() {
    if (state.draftEdit == null) return;
    state = state.copyWith(clearDraftEdit: true);
  }

  // Returns null on success, user-facing error on failure.
  // Unchanged body: no-op (draft cleared, null returned, no API call).
  // 403: draft cleared, error returned; screen keeps typed text intact so the
  //      user can copy it or send it as a new message.
  Future<String?> applyEdit(String rawBody) async {
    final body = rawBody.trim();
    final draft = state.draftEdit;
    if (draft == null) return null;
    if (body == draft.originalBody) {
      cancelEdit();
      return null;
    }
    try {
      final updated = await _repo.editMessage(
        _conversationId,
        draft.messageId,
        body,
      );
      state = state.copyWith(
        messages: state.messages
            .map((m) => m.id == draft.messageId ? _fromServer(updated) : m)
            .toList(),
        clearDraftEdit: true,
      );
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        state = state.copyWith(clearDraftEdit: true);
        return MessagingStrings.editWindowExpired;
      }
      return _messageOf(e);
    } catch (e) {
      return _messageOf(e);
    }
  }

  // Pessimistic delete — await the API, THEN update the UI (destructive +
  // irreversible; an optimistic remove that failed would lie to the user).
  // Multiple messages → one call each; successes are applied and failures
  // reported (never silently discarded). Exits selection mode after.
  Future<DeleteOutcome> deleteSelected({required String scope}) async {
    final ids = selectedMessages.map((m) => m.id).toList(); // snapshot
    final succeeded = <String>[];
    var failed = 0;
    Object? firstError;

    for (final id in ids) {
      try {
        await _repo.deleteMessage(_conversationId, id, scope: scope);
        succeeded.add(id);
      } catch (e) {
        failed++;
        firstError ??= e;
      }
    }

    if (succeeded.isNotEmpty) {
      if (scope == 'everyone') {
        // Tombstone in place: row stays, body blanked, isDeleted set.
        state = state.copyWith(
          messages: state.messages
              .map(
                (m) => succeeded.contains(m.id)
                    ? m.copyWith(isDeleted: true, body: '')
                    : m,
              )
              .toList(),
        );
      } else {
        // Delete-for-me: row gone entirely for this user.
        state = state.copyWith(
          messages: state.messages
              .where((m) => !succeeded.contains(m.id))
              .toList(),
        );
      }
    }

    clearSelection();
    return DeleteOutcome(
      succeeded: succeeded.length,
      failed: failed,
      firstError: firstError,
    );
  }

  // Pin a SINGLE selected message (UI only shows pin for single selection).
  // Pessimistic: await the server, then update — pinning changes shared state
  // both participants see, so an optimistic flip that failed would lie.
  // `duration` is required (matches the server, no default). On the cap (409)
  // this returns PinOutcome.capReached WITHOUT clearing the selection, so the
  // screen can show the replace dialog and retry with replaceOldest:true and the
  // SAME duration. The banner itself updates from the MessagePinChanged event.
  Future<PinOutcome> pinSelected({
    required PinDuration duration,
    bool replaceOldest = false,
  }) async {
    final sel = selectedMessages;
    if (sel.length != 1) return PinOutcome.success;
    final m = sel.first;
    try {
      await _repo.pinMessage(
        _conversationId,
        m.id,
        duration: duration,
        replaceOldest: replaceOldest,
      );
      _setPinned(m.id, true);
      clearSelection();
      return PinOutcome.success;
    } on DioException catch (e) {
      // 409 = at the cap with replaceOldest:false. Surface it distinctly.
      // Keep selection for the replace retry, but hide the floating reaction bar.
      if (e.response?.statusCode == 409) {
        hideReactionBar();
        return PinOutcome.capReached;
      }
      return PinOutcome(PinOutcomeKind.failed, message: _messageOf(e));
    } catch (e) {
      return PinOutcome(PinOutcomeKind.failed, message: _messageOf(e));
    }
  }

  // Unpin a SINGLE selected message (toolbar shows unpin when it is pinned).
  // Pessimistic. Returns null on success, else a user-facing message. The banner
  // reflects the removal via the MessagePinChanged event; here we clamp defensively.
  Future<String?> unpinSelected() async {
    final sel = selectedMessages;
    if (sel.length != 1) return null;
    final m = sel.first;
    try {
      await _repo.unpinMessage(_conversationId, m.id);
      _setPinned(m.id, false);
      final updated = state.pinnedMessages.where((p) => p.id != m.id).toList();
      state = state.copyWith(
        pinnedMessages: updated,
        pinnedIndex: clampPinIndex(state.pinnedIndex, updated.length),
      );
      clearSelection();
      return null;
    } on DioException catch (e) {
      return _messageOf(e);
    } catch (e) {
      return _messageOf(e);
    }
  }

  void _setPinned(String id, bool pinned) {
    state = state.copyWith(
      messages: state.messages
          .map((m) => m.id == id ? m.copyWith(isPinned: pinned) : m)
          .toList(),
    );
  }

  // Debounce markRead: a burst of fan-out messages fires one call, not N.
  void _scheduleMarkRead() {
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 1500), _markReadSafe);
  }

  // Debounce reconnect refetch: same 3 s window as ConversationsNotifier.
  void _scheduleReconnectRefresh() {
    _reconnectDebounce?.cancel();
    _reconnectDebounce = Timer(const Duration(seconds: 3), _reconnectRefetch);
  }

  // Fetches page 1 and merges any missed messages into the existing list.
  // Dedupes on server id — page 1 overlaps with messages already displayed.
  // Does NOT set scrollToLatest so the viewport stays where the user left it.
  Future<void> _reconnectRefetch() async {
    // SKIP (not defer) while the initial load is in flight: that load will
    // return current data by definition, so a deferred top-up adds nothing.
    // This is a background top-up — it must NEVER touch isLoading, in any
    // branch. isLoading belongs exclusively to open()'s load cycle.
    if (!_initialLoadDone || _conversationId.isEmpty) {
      _log(
        'reconnect refetch SKIPPED '
        '(initialLoadDone=$_initialLoadDone, conv="$_conversationId")',
      );
      return;
    }
    final mySeq = _seq;
    final cid = _conversationId;
    _log(
      'reconnect refetch RUNNING (baseline=$_baselineConnectCount, '
      'count=${ref.read(realtimeNotifierProvider.notifier).connectCount}, '
      'seq=$mySeq)',
    );

    try {
      final page = await _repo.getMessages(cid, limit: _pageSize);
      if (mySeq != _seq) {
        _log('STALE DISCARD in _reconnectRefetch: mySeq=$mySeq, _seq=$_seq');
        return;
      }

      final existingIds = state.messages.map((m) => m.id).toSet();
      final fresh = page.items
          .map(_fromServer)
          .where((m) => !existingIds.contains(m.id))
          .toList();
      if (fresh.isNotEmpty) {
        // Prepend at front of the newest-first list. ListView(reverse: true)
        // anchors at offset 0 = visual bottom, so prepending here adds items at
        // the bottom without moving the viewport — the user keeps reading where
        // they were.
        state = state.copyWith(messages: [...fresh, ...state.messages]);
        _markReadSafe();
      }

      // State B / C: a ConversationAccepted fan-out could have been lost while
      // disconnected. Reuse the existing reconcile path — it handles 403/404 and
      // is silent on transport failures.
      if (state.status == ConversationStatus.pending) {
        _refetchAndReconcile(cid, mySeq);
      }
    } catch (_) {
      // Best-effort — failure is silent; user can pull to refresh.
    }
  }

  // ── State C actions ───────────────────────────────────────────────────────

  // State C — pessimistic (F-M1 request_tile pattern): API pehle, phir UI.
  // Success pe State A. Return null=success, warna error message.
  Future<String?> accept() async {
    if (state.actionBusy) return null;
    state = state.copyWith(actionBusy: true);
    try {
      await _repo.acceptConversation(_conversationId);
      state = state.copyWith(
        status: ConversationStatus.accepted,
        isRequest: false,
        actionBusy: false,
      );
      // Requests list se nikle, accepted list mein aaye.
      ref.read(conversationRequestsProvider.notifier).refresh();
      ref.read(conversationsProvider.notifier).refresh();
      return null;
    } catch (e) {
      state = state.copyWith(actionBusy: false);
      return _messageOf(e);
    }
  }

  // State C decline — success pe screen khud pop karti hai.
  Future<String?> decline() async {
    if (state.actionBusy) return null;
    state = state.copyWith(actionBusy: true);
    try {
      await _repo.declineConversation(_conversationId);
      ref.read(conversationRequestsProvider.notifier).refresh();
      return null; // caller pops
    } catch (e) {
      state = state.copyWith(actionBusy: false);
      return _messageOf(e);
    }
  }

  // markRead non-critical: fail ho to sirf log — padhne ka amal kabhi na ruke.
  Future<void> _markReadSafe() async {
    try {
      await _repo.markRead(_conversationId);
      // Badge clear ho jab user wapas jaye.
      ref.read(conversationsProvider.notifier).refresh();
    } catch (e) {
      debugPrint('markRead failed (non-critical): $e');
    }
  }

  // Shared mapper — offline / session-expired / server / 4xx-detail alag messages.
  String _messageOf(Object e) => appErrorMessage(e);
}

final chatProvider = NotifierProvider.autoDispose<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
