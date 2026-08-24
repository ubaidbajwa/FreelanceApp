import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paged_result.dart';
import '../../../core/network/dio_client.dart';
import 'models/person_model.dart';

// GET /api/users — people directory (search + pagination). Backend har row ke
// sath connectionStatus deta hai, is liye button state ke liye alag call nahi
// chahiye. Send request ka kaam ConnectionsRepository ka hai (yahan nahi).
class PeopleRepository {
  final Dio _dio;
  PeopleRepository(this._dio);

  Future<PagedResult<PersonModel>> getPeople({
    String? search,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _dio.get(
      '/api/users',
      queryParameters: {
        // khali search bilkul mat bhejo — backend null hi treat karta hai
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
        'page': page,
        'pageSize': pageSize,
      },
    );
    return PagedResult.fromJson(response.data, PersonModel.fromJson);
  }
}

// Provider — wahi DI chain: dioProvider → repository (profile/connections pattern)
final peopleRepositoryProvider = Provider<PeopleRepository>((ref) {
  return PeopleRepository(ref.watch(dioProvider));
});
