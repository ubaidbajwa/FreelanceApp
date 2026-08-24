// Shared error strings — har network-facing screen ka error text yahin se aata
// hai (per-feature *_strings.dart convention, lekin cross-cutting isliye core mein).
// Maqsad: expired session, offline device, aur server bug alag alag padhein —
// sab ek generic line mein collapse na hon.
class ErrorStrings {
  ErrorStrings._();

  // Transport fail — request server tak pahunchi hi nahi.
  static const noConnection =
      "Can't reach the server. Check your connection and try again.";

  // 401 refresh ke baad — session khatam, user ko sign-in pe bheja ja raha hai.
  static const sessionExpired =
      'Your session has expired. Please sign in again.';

  // 5xx — humari side pe kuch toota.
  static const serverError =
      'Something went wrong on our side. Please try again.';

  // Aakhri fallback (4xx bina detail, ya non-Dio error).
  static const generic = 'Something went wrong. Try again.';
}
