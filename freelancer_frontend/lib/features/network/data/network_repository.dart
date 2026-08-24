import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paged_result.dart';
import '../../../core/network/dio_client.dart';
import 'models/network_models.dart';

// Network feature ke SAARE endpoints ek jagah.
class NetworkRepository {
  final Dio _dio;
  NetworkRepository(this._dio);

  Future<NetworkOverview> getOverview() async {
    final response = await _dio.get('/api/network/overview');
    return NetworkOverview.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PagedResult<Suggestion>> getSuggestions({
    int page = 1,
    int pageSize = 10,
  }) async {
    final response = await _dio.get(
      '/api/network/suggestions',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      Suggestion.fromJson,
    );
  }

  // 204 NoContent — kuch parse nahi karna
  Future<void> dismissSuggestion(String userId) async {
    await _dio.post('/api/network/suggestions/$userId/dismiss');
  }

  // Undo dismiss — DELETE makes it idempotent; same endpoint, different verb
  Future<void> unDismissSuggestion(String userId) async {
    await _dio.delete('/api/network/suggestions/$userId/dismiss');
  }

  Future<PagedResult<FollowSuggestion>> getFollowSuggestions({
    int page = 1,
    int pageSize = 10,
  }) async {
    final response = await _dio.get(
      '/api/network/follow-suggestions',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      FollowSuggestion.fromJson,
    );
  }

  Future<void> dismissFollowSuggestion(String userId) async {
    await _dio.post('/api/network/follow-suggestions/$userId/dismiss');
  }

  // Undo dismiss — DELETE makes it idempotent; same endpoint pattern as connect dismiss
  Future<void> unDismissFollowSuggestion(String userId) async {
    await _dio.delete('/api/network/follow-suggestions/$userId/dismiss');
  }

  // Follow / unfollow — wired to UI in a later slice
  Future<void> follow(String userId) async {
    await _dio.post('/api/network/follow/$userId');
  }

  Future<void> unfollow(String userId) async {
    await _dio.delete('/api/network/follow/$userId');
  }

  Future<PagedResult<FollowUser>> getFollowers({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/network/followers',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      FollowUser.fromJson,
    );
  }

  Future<PagedResult<FollowUser>> getFollowing({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/network/following',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      FollowUser.fromJson,
    );
  }

  Future<FollowStatus> getFollowStatus(String userId) async {
    final response = await _dio.get('/api/network/follow/$userId/status');
    return FollowStatus.fromJson(response.data as Map<String, dynamic>);
  }
}

final networkRepositoryProvider = Provider<NetworkRepository>((ref) {
  return NetworkRepository(ref.watch(dioProvider));
});
