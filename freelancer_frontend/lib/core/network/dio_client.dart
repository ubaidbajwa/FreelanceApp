import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import 'auth_interceptor.dart';

// Dio ka configured instance — poori app ek hi client use karegi
// Backend analogy: jaise HttpClient ko DI mein singleton register karte hain
final dioProvider = Provider<Dio>((ref) {
  final options = BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    // 10s tight tha — register jaise endpoints DB + (best-effort) email
    // karte hain, aur cold backend pe pehli call slow ho sakti hai. Headroom.
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Content-Type': 'application/json'},
  );

  final dio = Dio(options);

  // Bare client jo AuthInterceptor refresh + retry ke liye use karta hai —
  // is par khud AuthInterceptor NAHI hai, warna refresh call/retry dobara 401
  // handling se guzarti (recursion). Same base config.
  final refreshDio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Content-Type': 'application/json'},
  ));

  // Auth interceptor — access token attach + single-flight refresh-on-401 +
  // session tear-down. Backend analogy: HttpClient ka DelegatingHandler.
  dio.interceptors.add(AuthInterceptor(ref, refreshDio));

  // Interceptor = client-side middleware — har request/response console pe log
  dio.interceptors.add(
    LogInterceptor(
      requestBody: true,
      responseBody: true,
      error: true,
    ),
  );

  return dio;
});