import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GithubAuthService {
  static final GithubAuthService instance = GithubAuthService._internal();
  GithubAuthService._internal();

  final FlutterAppAuth _appAuth = const FlutterAppAuth();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String clientId = "Ov23li4mggd6g5ibDJZR";
  // ⚠️ 填入你在 GitHub OAuth App 后台拿到的 Client Secret
  static const String clientSecret = "8d5ee4ae95d33585b4caebabf3fda9ef43f6d346";
  static const String redirectUri = "gitclient://tinybits";
  static const String authorizationEndpoint = "https://github.com/login/oauth/authorize";
  static const String tokenEndpoint = "https://github.com/login/oauth/access_token";
  static const List<String> scopes = ["repo:contents", "user"];

  static const String _kAccessToken = "gh_access_token";
  static const String _kRefreshToken = "gh_refresh_token";
  static const String _kExpiresAt = "gh_expires_at";

  String? _cachedAccessToken;
  DateTime? _cachedExpiresAt;

  bool _isRefreshing = false;
  Completer<String?>? _pendingRefreshCompleter;

  Future<void> login() async {
    try {
      final authReq = AuthorizationRequest(
        clientId,
        redirectUri,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: authorizationEndpoint,
          tokenEndpoint: tokenEndpoint,
        ),
        scopes: scopes,
      );
      final authResult = await _appAuth.authorize(authReq);
      final code = authResult.authorizationCode;
      // ✅ 重点：取出 AppAuth 自动生成的 codeVerifier
      final codeVerifier = authResult.codeVerifier;

      if (code == null) {
        throw Exception("未能获取授权 code");
      }
      if (codeVerifier == null) {
        throw Exception("缺少 PKCE codeVerifier");
      }

      final resp = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: {
          "client_id": clientId,
          "client_secret": clientSecret,
          "code": code,
          "redirect_uri": redirectUri,
          // ✅ 加上这一行！
          "code_verifier": codeVerifier,
        },
      );

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json["error"] != null) {
        throw Exception("GitHub 返回错误：${json["error"]}, ${json["error_description"] ?? ""}");
      }

      final accessToken = json["access_token"];
      if (accessToken is! String) {
        throw Exception("响应中没有 access_token");
      }

      final int? expiresIn = json["expires_in"] is int ? json["expires_in"] : null;
      final String? refreshToken = json["refresh_token"] is String ? json["refresh_token"] : null;

      DateTime? expiresAt;
      if (expiresIn != null) {
        expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      }

      await _saveTokens(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresAt);
    } on FlutterAppAuthUserCancelledException {
      throw AuthCancelledException("用户取消授权");
    }
  }

  Future<String?> getValidAccessToken() async {
    if (_cachedAccessToken != null && _cachedExpiresAt != null) {
      if (_cachedExpiresAt!.isAfter(DateTime.now().add(const Duration(seconds: 300)))) {
        return _cachedAccessToken;
      }
    }

    final access = await _storage.read(key: _kAccessToken);
    final refresh = await _storage.read(key: _kRefreshToken);
    final expRaw = await _storage.read(key: _kExpiresAt);

    // GitHub 传统 OAuth token 默认永不过期，没有过期时间就直接返回
    if (expRaw == null) {
      _cachedAccessToken = access;
      return access;
    }

    final expiresAt = DateTime.parse(expRaw);
    if (expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 300)))) {
      _cachedAccessToken = access;
      _cachedExpiresAt = expiresAt;
      return access;
    }

    if (refresh == null) {
      await logout();
      return null;
    }

    if (_isRefreshing) {
      return _pendingRefreshCompleter!.future;
    }
    _isRefreshing = true;
    _pendingRefreshCompleter = Completer<String?>();

    try {
      final resp = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: {
          "client_id": clientId,
          "client_secret": clientSecret,
          "grant_type": "refresh_token",
          "refresh_token": refresh,
        },
      );
      if (resp.statusCode != 200) {
        throw AuthRefreshFailedException("刷新 token 失败：${resp.body}");
      }
      final json = jsonDecode(resp.body);
      final newAccess = json["access_token"];
      if (newAccess is! String) {
        throw AuthRefreshFailedException("刷新后没有拿到 access_token");
      }
      final newRefresh = json["refresh_token"] is String ? json["refresh_token"] : null;
      final int? exp = json["expires_in"] is int ? json["expires_in"] : null;

      final newExp = exp == null ? null : DateTime.now().add(Duration(seconds: exp));

      await _saveTokens(accessToken: newAccess, refreshToken: newRefresh, expiresIn: newExp);
      _pendingRefreshCompleter?.complete(newAccess);
      return newAccess;
    } catch (e) {
      await logout();
      final err = AuthRefreshFailedException("refresh token 失效，请重新登录");
      _pendingRefreshCompleter?.completeError(err);
      rethrow;
    } finally {
      _isRefreshing = false;
      _pendingRefreshCompleter = null;
    }
  }

  Future<void> _saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresIn,
  }) async {
    _cachedAccessToken = accessToken;
    _cachedExpiresAt = expiresIn;
    await _storage.write(key: _kAccessToken, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kRefreshToken, value: refreshToken);
    }
    if (expiresIn != null) {
      await _storage.write(key: _kExpiresAt, value: expiresIn.toIso8601String());
    } else {
      await _storage.delete(key: _kExpiresAt);
    }
  }

  Future<void> logout() async {
    _cachedAccessToken = null;
    _cachedExpiresAt = null;
    _isRefreshing = false;
    _pendingRefreshCompleter?.complete(null);
    _pendingRefreshCompleter = null;

    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kRefreshToken);
    await _storage.delete(key: _kExpiresAt);
  }

  Future<bool> hasCredential() async {
    final a = await _storage.read(key: _kAccessToken);
    return a != null;
  }
}

class AuthCancelledException implements Exception {
  final String message;
  AuthCancelledException(this.message);
  @override
  String toString() => message;
}

class AuthRefreshFailedException implements Exception {
  final String message;
  AuthRefreshFailedException(this.message);
  @override
  String toString() => message;
}
