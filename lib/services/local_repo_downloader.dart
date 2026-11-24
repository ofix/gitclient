import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileItem {
  final String name;
  final String path;
  final bool isDir;
  final bool isZip;
  bool isChecked;
  bool isExpanded;
  List<FileItem> children;

  FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    required this.isZip,
    this.isChecked = false,
    this.isExpanded = false,
    this.children = const [],
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      isDir: json['isDir'] ?? false,
      isZip: json['isZip'] ?? false,
    );
  }
}

class LocalRepoDownloader {
  static final LocalRepoDownloader instance = LocalRepoDownloader._internal();
  late Dio _dio;
  static const String _prefKeyBaseUrl = 'server_base_url';

  LocalRepoDownloader._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'http://10.0.2.2:8080', // 默认兜底地址
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  /// 从本地缓存加载 Base URL
  Future<void> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_prefKeyBaseUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _dio.options.baseUrl = savedUrl;
    }
  }

  /// 设置并保存 Base URL
  Future<void> setBaseUrl(String url) async {
    // 简单校验并补全协议头
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    _dio.options.baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBaseUrl, url);
  }

  String get currentBaseUrl => _dio.options.baseUrl;

  Future<List<FileItem>> fetchDirectory(String path) async {
    try {
      final response = await _dio.get('/api/dirlist', queryParameters: {'path': path});
      final List<dynamic> data = response.data;
      return data.map((e) => FileItem.fromJson(e)).toList();
    } catch (e) {
      throw Exception('获取目录失败: $e');
    }
  }

  Future<String> downloadZip(List<String> paths, Function(double) onProgress) async {
    if (paths.isEmpty) throw Exception('未选择任何文件');

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'export_${DateTime.now().millisecondsSinceEpoch}.zip';
      final savePath = '${dir.path}/$fileName';

      await _dio
          .post(
            '/api/download',
            data: {'paths': paths},
            options: Options(responseType: ResponseType.bytes, followRedirects: false),
            onReceiveProgress: (received, total) {
              if (total != -1) onProgress(received / total);
            },
          )
          .then((response) {
            File file = File(savePath);
            file.writeAsBytesSync(response.data);
          });

      return savePath;
    } catch (e) {
      throw Exception('下载失败: $e');
    }
  }
}
