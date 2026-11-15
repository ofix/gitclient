import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_archive/flutter_archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/local_repo.dart';

class LocalArchiveService {
  static LocalArchiveService? _inst;
  static LocalArchiveService get instance => _inst ??= LocalArchiveService._();
  LocalArchiveService._();

  late Directory baseDir;
  late File indexFile;
  final Dio _dio = Dio(
    BaseOptions(
      followRedirects: true,
      maxRedirects: 5,
      connectTimeout: const Duration(seconds: 15),
    ),
  );

  Future<void> init() async {
    final doc = await getApplicationDocumentsDirectory();
    baseDir = Directory(p.join(doc.path, 'gh_archives'));
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    indexFile = File(p.join(baseDir.path, 'index.json'));
    if (!await indexFile.exists()) {
      await indexFile.writeAsString('[]');
    }
  }

  Future<List<LocalRepo>> loadIndex() async {
    final raw = await indexFile.readAsString();
    final List list = jsonDecode(raw);
    return list.map((e) => LocalRepo.fromJson(e)).toList();
  }

  Future<void> saveIndex(List<LocalRepo> repos) async {
    final list = repos.map((e) => e.toJson()).toList();
    await indexFile.writeAsString(jsonEncode(list), flush: true);
  }

  String _sanitizeId(String owner, String repo, String ref) {
    final safeRef = ref.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return '${owner}_${repo}_$safeRef';
  }

  /// 从 github zip 顶层目录名解析 commit sha
  String? _parseShaFromTopDirName(String dirName) {
    final parts = dirName.split('-');
    if (parts.length < 3) return null;
    return parts.last;
  }

  /// 获取远端 ref 最新 sha
  Future<String?> fetchRemoteRefSha(String owner, String repo, String ref, {String? token}) async {
    try {
      final headers = <String, String>{};
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'token $token';
      }
      final resp = await _dio.get(
        'https://api.github.com/repos/$owner/$repo/commits/$ref',
        options: Options(headers: headers),
      );
      return resp.data['sha'] as String;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// 刷新某个仓库全部本地分支远端状态
  Future<void> refreshRepoRemoteStatus(String owner, String repo, {String? token}) async {
    final all = await loadIndex();
    final items = all.where((r) => r.owner == owner && r.name == repo).toList();
    final now = DateTime.now().toIso8601String();
    for (final item in items) {
      final remoteSha = await fetchRemoteRefSha(owner, repo, item.ref, token: token);
      final updated = item.copyWith(remoteLatestSha: remoteSha, lastSyncAt: now);
      all.removeWhere((x) => x.id == item.id);
      all.add(updated);
    }
    await saveIndex(all);
  }

  /// 查询该仓库所有已下载分支
  Future<List<LocalRepo>> findByOwnerRepo(String owner, String repo) async {
    final all = await loadIndex();
    return all.where((r) => r.owner == owner && r.name == repo).toList();
  }

  /// 核心：getRepoPath
  Future<String> getRepoPath(String owner, String repo, String ref) async {
    final doc = await getApplicationDocumentsDirectory();
    baseDir = Directory(p.join(doc.path, 'gh_archives'));
    // 简单做文件名安全过滤，防止路径穿越
    final safeOwner = owner.replaceAll(RegExp(r'[^\w\-]'), '_');
    final safeRepo = repo.replaceAll(RegExp(r'[^\w\-]'), '_');
    final safeRef = ref.replaceAll(RegExp(r'[^\w\-]'), '_');
    return p.join(baseDir.path, safeOwner, safeRepo, safeRef);
  }

  /// 配套：isRepoReady（一并补上，上层可以原样调用）
  Future<bool> isRepoReady(String owner, String repo, String ref) async {
    final dirPath = await getRepoPath(owner, repo, ref);
    final dir = Directory(dirPath);
    return await dir.exists();
  }

  /// 下载 + 解压，自动解析 localCommitSha
  Future<LocalRepo> downloadAndExtract({
    required String owner,
    required String repo,
    required String ref,
    required String refType,
    required String token,
    CancelToken? cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final safeId = _sanitizeId(owner, repo, ref);
    final targetRoot = Directory(p.join(baseDir.path, safeId));
    if (await targetRoot.exists()) {
      await targetRoot.delete(recursive: true);
    }
    await targetRoot.create(recursive: true);

    final zipUrl = 'https://api.github.com/repos/$owner/$repo/zipball/$ref';
    final partFile = File(p.join(baseDir.path, '$safeId.zip.part'));
    final finalZip = File(p.join(baseDir.path, '$safeId.zip'));
    if (await finalZip.exists()) await finalZip.delete();

    int startOffset = 0;
    if (await partFile.exists()) {
      startOffset = await partFile.length();
    }

    final headers = <String, String>{
      if (token.isNotEmpty) 'Authorization': 'token $token',
      'Accept': 'application/vnd.github.raw',
    };
    if (startOffset > 0) {
      headers['Range'] = 'bytes=$startOffset-';
    }

    IOSink ioSink = await partFile.openWrite(
      mode: startOffset > 0 ? FileMode.append : FileMode.write,
    );

    try {
      final response = await _dio.get<ResponseBody>(
        zipUrl,
        options: Options(headers: headers, responseType: ResponseType.stream),
        cancelToken: cancelToken,
      );
      final status = response.statusCode ?? 200;
      if (startOffset > 0 && status != 206) {
        await ioSink.close();
        await partFile.delete();
        ioSink = await partFile.openWrite(mode: FileMode.write);
        startOffset = 0;
      }

      int received = startOffset;
      int total = -1;
      final clStr = response.headers.value('content-length');
      if (clStr != null) {
        final parsed = int.tryParse(clStr);
        if (parsed != null) {
          total = status == 206 ? startOffset + parsed : parsed;
        }
      }

      await for (final chunk in response.data!.stream) {
        // 每次写入前检查是否被取消
        if (cancelToken?.isCancelled == true) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: zipUrl),
            reason: "user cancel",
          );
        }
        ioSink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await ioSink.flush();
    } finally {
      await ioSink.close();
    }

    await partFile.rename(finalZip.path);
    await ZipFile.extractToDirectory(zipFile: finalZip, destinationDir: targetRoot);
    await finalZip.delete();

    final entries = await targetRoot.list().toList();
    final dirEntries = entries.where((e) => e is Directory).cast<Directory>().toList();
    if (dirEntries.isEmpty) {
      throw Exception('zip 解压后没有找到源码目录');
    }
    final subDir = dirEntries.first;
    final localSha = _parseShaFromTopDirName(p.basename(subDir.path));

    final repoItem = LocalRepo(
      id: safeId,
      owner: owner,
      name: repo,
      ref: ref,
      refType: refType,
      localCommitSha: localSha,
      remoteLatestSha: null,
      lastSyncAt: null,
      downloadedAt: DateTime.now().toIso8601String(),
      rootDir: subDir.path,
    );

    final all = await loadIndex();
    all.removeWhere((r) => r.id == repoItem.id);
    all.add(repoItem);
    await saveIndex(all);
    return repoItem;
  }

  Future<void> removeRepo(LocalRepo repo) async {
    final dir = Directory(repo.rootDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final all = await loadIndex();
    all.removeWhere((r) => r.id == repo.id);
    await saveIndex(all);
  }

  Stream<FileSystemEntity> listDir(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return const Stream.empty();
    final ignore = {'.git', '.github', 'node_modules', 'build', 'dist'};
    return dir.list().where((e) => !ignore.contains(p.basename(e.path)));
  }

  Future<List<FileSystemEntity>> listFiles(String absPath) async {
    return await listDir(absPath).toList();
  }

  Future<List<FileSystemEntity>> listFilesByRef(
    String owner,
    String repo,
    String ref,
    String relativePath,
  ) async {
    final all = await loadIndex();
    final item = all.where((r) => r.owner == owner && r.name == repo && r.ref == ref).firstOrNull;
    if (item == null) return [];
    final real = p.join(item.rootDir, relativePath);
    return listFiles(real);
  }

  bool isBinaryFile(String path) {
    final ext = p.extension(path).toLowerCase();
    const binary = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.ico',
      '.zip',
      '.tar',
      '.gz',
      '.7z',
      '.pdf',
      '.exe',
      '.so',
      '.dylib',
    };
    return binary.contains(ext);
  }

  Future<String?> readFileContent(String absPath) async {
    final f = File(absPath);
    if (!await f.exists()) return null;
    if (isBinaryFile(absPath)) return null;
    try {
      return await f.readAsString(encoding: utf8);
    } catch (_) {
      return null;
    }
  }

  Future<String?> readFileByRef(
    String owner,
    String repo,
    String ref,
    String relativeFilePath,
  ) async {
    final all = await loadIndex();
    final item = all.where((r) => r.owner == owner && r.name == repo && r.ref == ref).firstOrNull;
    if (item == null) return null;
    final real = p.join(item.rootDir, relativeFilePath);
    return readFileContent(real);
  }
}
