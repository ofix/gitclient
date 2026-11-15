import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:io';

class SecureStorageService {
  static final _storage = Platform.isMacOS
      ? const FlutterSecureStorage(
          mOptions: MacOsOptions(
            usesDataProtectionKeychain: false, // ✅ 切 legacy login keychain
          ),
        )
      : const FlutterSecureStorage();
  static const String _kAccessToken = "gh_access_token";
  static const String _kRefreshToken = "gh_refresh_token";
  static const String _kExpiresAt = "gh_expires_at";
  static Future<String?> getAccessToken() async {
    return await _storage.read(key: _kAccessToken);
  }

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _kAccessToken, value: token);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _kAccessToken);
  }

  /// 读取，外部传入 key
  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  /// 写入
  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  /// 删除
  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
