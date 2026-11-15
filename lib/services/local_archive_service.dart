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
  final Dio _dio = Dio(BaseOptions(followRedirects: true, maxRedirects: 5));

  /// 初始化，APP 启动时必须调用一次
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

  /// 下载 + 解压 github zipball
  /// 注意：github zipball 的 range 续传不可靠，增加状态码判断
  Future<LocalRepo> downloadAndExtract({
    required String owner,
    required String repo,
    required String ref,
    required String token,
    required void Function(int received, int total) onProgress,
  }) async {
    // 简单 sanitize，防止非法路径字符
    final safeId = '${owner}_${repo}_${ref.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}';
    final targetRoot = Directory(p.join(baseDir.path, safeId));

    if (await targetRoot.exists()) {
      await targetRoot.delete(recursive: true);
    }
    await targetRoot.create(recursive: true);

    final zipUrl = 'https://api.github.com/repos/$owner/$repo/zipball/$ref';
    final partFile = File(p.join(baseDir.path, '$safeId.zip.part'));
    final finalZip = File(p.join(baseDir.path, '$safeId.zip'));

    if (await finalZip.exists()) {
      await finalZip.delete();
    }

    int startOffset = 0;
    if (await partFile.exists()) {
      startOffset = await partFile.length();
    }

    final headers = <String, String>{
      'Authorization': 'token $token',
      'Accept': 'application/vnd.github.raw',
    };
    if (startOffset > 0) {
      headers['Range'] = 'bytes=$startOffset-';
    }

    // 改为可变变量，不再 final
    IOSink ioSink = await partFile.openWrite(
      mode: startOffset > 0 ? FileMode.append : FileMode.write,
    );

    try {
      final response = await _dio.get<ResponseBody>(
        zipUrl,
        options: Options(headers: headers, responseType: ResponseType.stream),
      );

      final status = response.statusCode ?? 200;
      // 如果不是 206，说明服务端拒绝续传，丢弃之前的 part，从头写
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
          if (status == 206) {
            total = startOffset + parsed;
          } else {
            total = parsed;
          }
        }
      }

      await for (final chunk in response.data!.stream) {
        ioSink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await ioSink.flush();
    } finally {
      await ioSink.close();
    }

    // 下载完成，改名
    await partFile.rename(finalZip.path);

    // 解压
    await ZipFile.extractToDirectory(zipFile: finalZip, destinationDir: targetRoot);
    await finalZip.delete();

    // 找到 github 自动生成的那个顶层目录
    final entries = await targetRoot.list().toList();
    final dirEntries = entries.where((e) => e is Directory).cast<Directory>().toList();
    if (dirEntries.isEmpty) {
      throw Exception('zip 解压后没有找到源码目录');
    }
    final subDir = dirEntries.first;

    final repoItem = LocalRepo(
      id: safeId,
      owner: owner,
      name: repo,
      ref: ref,
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
    if (!Directory(path).existsSync()) {
      return const Stream.empty();
    }
    final ignore = {'.git', '.github', 'node_modules', 'build', 'dist'};
    return Directory(path).list().where((e) => !ignore.contains(p.basename(e.path)));
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
}
