import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import '../../../../core/network/dio_client.dart';
import '../models/experience_model.dart';
import '../models/profile_model.dart';

class ProfileRepository {
  final Dio _dio;
  ProfileRepository(this._dio);

  // 1. Apni profile lao (get-or-create — hamesha profile milegi, 404 kabhi nahi)
  Future<ProfileModel> getMyProfile() async {
    final response = await _dio.get('/api/profile/me');
    return ProfileModel.fromJson(response.data);
  }

  // 2. Profile update (partial — sirf bhare hue fields jayenge)
  Future<ProfileModel> updateProfile(UpdateProfileRequest request) async {
    final response = await _dio.put('/api/profile/me', data: request.toJson());
    // backend updated profile wapis bhejta hai — usi ko parse kar ke return
    return ProfileModel.fromJson(response.data);
  }

  // 3. Photo upload — YE NAYA HAI, dhyan se:
  Future<ProfileModel> uploadPhoto(String filePath) async {
    // JSON text hota hai — photo BINARY file hai, JSON mein nahi ja sakti.
    // FormData ek "parcel" hai jisme file pack ho kar jati hai (multipart).
    final formData = FormData.fromMap({
      // 'photo' — backend ke IFormFile parameter ka naam (ProfileController)
      'photo': await MultipartFile.fromFile(
        filePath,
        // dio default octet-stream bhejta hai — backend sirf image/* leta hai
        contentType: _imageMediaType(filePath),
      ),
    });
    final response = await _dio.post('/api/profile/me/photo', data: formData);
    return ProfileModel.fromJson(response.data);
  }

  // File extension se mime type — backend jpg/png/webp hi allow karta hai
  MediaType _imageMediaType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => MediaType('image', 'jpeg'),
      'png' => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      // unknown extension — backend khud reject kar dega, saaf error ke sath
      _ => MediaType('application', 'octet-stream'),
    };
  }

  // 4. Experience add — backend poora experience object wapis deta hai (id ke saath)
  Future<ExperienceModel> addExperience(AddExperienceRequest request) async {
    final response =
        await _dio.post('/api/profile/me/experiences', data: request.toJson());
    return ExperienceModel.fromJson(response.data);
  }

  // 5. Experience delete — backend 204 NoContent deta hai, kuch parse nahi karna
  Future<void> deleteExperience(String id) async {
    await _dio.delete('/api/profile/me/experiences/$id');
  }

  // 6. Username availability — backend { "available": true/false } deta hai
  Future<bool> isUsernameAvailable(String username) async {
    final response = await _dio.get(
      '/api/profile/username-available',
      queryParameters: {'username': username},
    );
    return response.data['available'] as bool;
  }

  // 7. Username claim
  Future<void> claimUsername(String username) async {
    await _dio.put('/api/profile/username', data: {'username': username});
  }
}

// Provider — wahi DI chain: dioProvider → repository
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(dioProvider));
});