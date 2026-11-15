import 'package:github/github.dart';

import 'github_auth_service.dart';

class GithubService {
  static GithubService? _instance;
  static GithubService get instance => _instance ??= GithubService._();
  GithubService._();

  GitHub? _gh;
  String? _lastToken;

  Future<GitHub> get client async {
    final token = await GithubAuthService.instance.getValidAccessToken();
    if (token == null) {
      throw AuthRefreshFailedException("未登录或凭证失效");
    }
    if (_lastToken != token) {
      _gh = GitHub(auth: Authentication.withToken(token));
      _lastToken = token;
    }
    return _gh!;
  }

  Future<User> getCurrentUser() async {
    final gh = await client;
    try {
      final user = await gh.users.getCurrentUser();
      return user;
    } on AccessForbidden {
      await _handleAccessForbidden();
      rethrow;
    }
  }

  Future<Stream<Repository>> searchRepos(String q, {int pages = 2}) async {
    final gh = await client;
    Stream<Repository> stream;
    try {
      stream = gh.search.repositories(q, pages: pages);
    } on AccessForbidden {
      await _handleAccessForbidden();
      rethrow;
    }
    return stream;
  }

  Future<Repository> getRepo(RepositorySlug slug) async {
    final gh = await client;
    try {
      final repo = await gh.repositories.getRepository(slug);
      return repo;
    } on AccessForbidden {
      await _handleAccessForbidden();
      rethrow;
    }
  }

  Future<List<Branch>> listBranches(RepositorySlug slug) async {
    final gh = await client;
    try {
      final branches = await gh.repositories.listBranches(slug).toList();
      return branches;
    } on AccessForbidden {
      await _handleAccessForbidden();
      rethrow;
    }
  }

  Future<GitHubFile> getReadme(RepositorySlug slug, {String? ref}) async {
    final gh = await client;
    try {
      final item = await gh.repositories.getReadme(slug, ref: ref);
      return item;
    } on AccessForbidden {
      await _handleAccessForbidden();
      rethrow;
    }
  }

  Future<void> _handleAccessForbidden() async {
    _gh = null;
    _lastToken = null;
    await GithubAuthService.instance.logout();
    throw AuthRefreshFailedException("Token 已失效，请重新登录");
  }
}
