import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'error_strings.dart';

// Ek jagah Dio error → user message. Pehle har screen ka apna _messageOf tha jo
// sab kuch ek generic line mein daal deta tha — isi wajah se expired session aur
// server bug bilkul same dikhte the. Yahan kinds alag ho jate hain.
//
// debug builds mein message ke saath status + endpoint bhi lagta hai taake
// screenshot dekhte hi maloom ho ("[401 GET /api/conversations]") — release mein
// nahi.
String appErrorMessage(Object error, {bool debug = kDebugMode}) {
  if (error is! DioException) return ErrorStrings.generic;

  // 1) Transport fail — server tak pahunche hi nahi (offline / down / timeout).
  // NOTE: sendTimeout/receiveTimeout ka matlab strictly "server mila magar
  // itna slow tha ke request/response poori na hui" — connectionError se alag
  // hai (jahan kuch reachable hi nahi). Jaan-boojh ke ek hi bucket mein rakha:
  // user ka agla step dono soorton mein same hai (thodi der baad dobara try).
  // Alag message inhe distinguish nahi karta, sirf shor barhata. Split tab karo
  // jab UI ko genuinely alag action chahiye (jaise auto-retry vs offline banner).
  switch (error.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return _decorate(ErrorStrings.noConnection, error, debug);
    default:
      break;
  }

  final status = error.response?.statusCode;

  final String base;
  if (status == 401) {
    // Ye tabhi kisi screen tak pahunchta hai jab interceptor ka refresh FAIL ho
    // chuka — user pehle hi sign-in pe redirect ho raha hota hai.
    base = ErrorStrings.sessionExpired;
  } else if (status != null && status >= 500) {
    base = ErrorStrings.serverError;
  } else if (status != null && status >= 400) {
    // Baaki 4xx — RFC 7807 ProblemDetails ka `detail` (jaise pehle _messageOf).
    final data = error.response?.data;
    final detail = data is Map ? data['detail'] : null;
    base = (detail is String && detail.isNotEmpty) ? detail : ErrorStrings.generic;
  } else {
    base = ErrorStrings.generic;
  }

  return _decorate(base, error, debug);
}

// Debug-only: status + method + endpoint append. Release mein message as-is.
String _decorate(String message, DioException error, bool debug) {
  if (!debug) return message;
  final status = error.response?.statusCode;
  final code = status != null ? '$status ' : '';
  return '$message  [$code${error.requestOptions.method} ${error.requestOptions.path}]';
}
