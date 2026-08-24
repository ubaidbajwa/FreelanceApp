import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paged_result.dart';
import '../../../core/network/dio_client.dart';
import 'models/connection_models.dart';

// ConnectionsController ke SAARE endpoints ek jagah — Invitations screen abhi
// kuch hi use karti hai, lekin agla slice (Connect button) yehi repository
// reuse karega. Base URL + auth header dioProvider se aate hain (interceptor).
class ConnectionsRepository {
  final Dio _dio;
  ConnectionsRepository(this._dio);

  // 1. Request bhejo — backend poora request object wapis deta hai (id ke sath)
  Future<ConnectionRequestResponse> sendRequest(String receiverId) async {
    final response = await _dio.post(
      '/api/connections/requests',
      data: {'receiverId': receiverId},
    );
    return ConnectionRequestResponse.fromJson(response.data);
  }

  // 2. Accept — backend 204 NoContent deta hai, kuch parse nahi karna
  Future<void> acceptRequest(String id) async {
    await _dio.post('/api/connections/requests/$id/accept');
  }

  // 3. Reject — 204 NoContent
  Future<void> rejectRequest(String id) async {
    await _dio.post('/api/connections/requests/$id/reject');
  }

  // 4. Withdraw (apni bheji hui request wapas lo) — 204 NoContent
  Future<void> withdrawRequest(String id) async {
    await _dio.delete('/api/connections/requests/$id');
  }

  // 5. Meri saari connections (accepted)
  Future<List<ConnectionUser>> getMyConnections() async {
    final response = await _dio.get('/api/connections');
    return (response.data as List)
        .map((e) => ConnectionUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 6. Incoming pending requests — N5: now returns PagedResult (was bare array)
  Future<PagedResult<PendingRequest>> getIncoming({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/connections/requests/incoming',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      PendingRequest.fromJson,
    );
  }

  // 7. Outgoing pending requests — N5: now returns PagedResult (was bare array)
  Future<PagedResult<PendingRequest>> getOutgoing({
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/connections/requests/outgoing',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    return PagedResult.fromJson(
      response.data as Map<String, dynamic>,
      PendingRequest.fromJson,
    );
  }

  // 8. Doosray user ke sath status — Connect button isi se decide hoga
  Future<ConnectionStatusWith> getStatus(String otherUserId) async {
    final response = await _dio.get('/api/connections/status/$otherUserId');
    return ConnectionStatusWith.fromApi(response.data['status'] as String);
  }
}

// Provider — wahi DI chain: dioProvider → repository (profile wala pattern)
final connectionsRepositoryProvider = Provider<ConnectionsRepository>((ref) {
  return ConnectionsRepository(ref.watch(dioProvider));
});
