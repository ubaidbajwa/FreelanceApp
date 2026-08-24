import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedAccountService {
  static const _storage = FlutterSecureStorage();
  static const _kName = 'saved_account_name';
  static const _kEmail = 'saved_account_email';

  // Login success pe call hoga
  Future<void> save({required String name, required String email}) async {
    await _storage.write(key: _kName, value: name);
    await _storage.write(key: _kEmail, value: email);
  }

  Future<({String name, String email})?> get() async {
    final name = await _storage.read(key: _kName);
    final email = await _storage.read(key: _kEmail);
    if (name == null || email == null) return null;
    return (name: name, email: email);
  }

  // "Remove account" (3-dot menu) pe call hoga
  Future<void> clear() async {
    await _storage.delete(key: _kName);
    await _storage.delete(key: _kEmail);
  }

  // ubaid123@gmail.com → u*****@gmail.com
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    return '${email[0]}*****${email.substring(at)}';
  }
}

final savedAccountServiceProvider =
    Provider<SavedAccountService>((ref) => SavedAccountService());