import 'package:intl/intl.dart';

/// UTC timestamp ko locale-aware relative label mein badalta hai (list rows ke liye).
/// F-M2 chat date-separators ke liye isi helper ko reuse karega.
///
/// Global-audience req #1 + #2: input UTC hota hai, yahin `.toLocal()` lagta hai
/// taake caller kabhi raw UTC render na kare; formatting `intl` se (hardcoded
/// pattern nahi) device locale ke sath.
///
/// Rules (device local time):
///  - aaj          → sirf time    (e.g. 3:42 PM / 15:42)  → DateFormat.jm
///  - is hafte     → weekday naam (e.g. Monday)           → DateFormat.EEEE
///  - us se purana → short date   (e.g. 7/23/2026)        → DateFormat.yMd
///
/// [timestamp] nullable hai: null pe khali string wapas ('' — koi label nahi).
/// Ye single guard yahin hai taake call-sites `!` (null-assertion) na lagayein —
/// backend abhi LastMessageAt != null filter karta hai, lekin client us
/// server-side invariant pe depend na kare; query badle to yahan gracefully
/// degrade ho, runtime throw nahi.
///
/// [now] test ke liye inject ho sakta hai; [locale] null ho to default locale.
String formatRelativeTimestamp(
  DateTime? timestamp, {
  DateTime? now,
  String? locale,
}) {
  if (timestamp == null) return '';
  final local = timestamp.toLocal();
  final current = (now ?? DateTime.now()).toLocal();

  // Calendar-day difference (time-of-day ignore) taake "kal 11pm" bhi kal hi rahe.
  final today = DateTime(current.year, current.month, current.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo <= 0) {
    return DateFormat.jm(locale).format(local); // aaj (aur clock-skew se future)
  }
  if (daysAgo < 7) {
    return DateFormat.EEEE(locale).format(local); // is hafte → weekday
  }
  return DateFormat.yMd(locale).format(local); // purana → short numeric date
}

/// Chat bubble ka timestamp — hamesha SIRF waqt (e.g. 1:27 PM / 13:27), kabhi
/// weekday/date nahi. Date ka context already day-separator pill deta hai, is liye
/// bubble mein sirf `DateFormat.jm` (locale-aware) `.toLocal()` ke sath.
///
/// [timestamp] nullable: null pe khali string (call-site `!` na lagaye).
String formatBubbleTime(DateTime? timestamp, {String? locale}) {
  if (timestamp == null) return '';
  return DateFormat.jm(locale).format(timestamp.toLocal());
}

/// Chat day-separator label — day-boundary hamesha LOCAL dates pe compute hoti
/// hai (UTC pe nahi), warna duniya ke zyada tar hisson mein separator ghalat din
/// pe girta hai. "Today"/"Yesterday" labels caller (MessagingStrings) se inject
/// hote hain — ye core helper user-facing literal nahi rakhta.
///
/// Rules (device local time):
///  - aaj    → [todayLabel]
///  - kal    → [yesterdayLabel]
///  - purana → poori locale date (DateFormat.yMMMMd)
String formatDateSeparator(
  DateTime timestamp, {
  required String todayLabel,
  required String yesterdayLabel,
  DateTime? now,
  String? locale,
}) {
  final local = timestamp.toLocal();
  final current = (now ?? DateTime.now()).toLocal();

  final thatDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(current.year, current.month, current.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo == 0) return todayLabel;
  if (daysAgo == 1) return yesterdayLabel;
  return DateFormat.yMMMMd(locale).format(local);
}
