import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:github/github.dart';

import '../services/github_service.dart';
import '../services/local_archive_service.dart';
import '../services/secure_storage_service.dart';
import 'file_tree_page.dart';

class RepoDetailPage extends StatefulWidget {
  final String owner;
  final String repoName;
  const RepoDetailPage({super.key, required this.owner, required this.repoName});

  @override
  State<RepoDetailPage> createState() => _RepoDetailPageState();
}

class _RepoDetailPageState extends State<RepoDetailPage> {
  Repository? repo;
  List<Branch> branches = [];
  String? selectedRef;
  bool loading = true;
  bool downloading = false;
  int downloadRecv = 0;
  int downloadTotal = 0;
  String readme = '';

  late final RepositorySlug _slug;
  Timer? _progressThrottle;

  /// 格式化字节
  String formatBytes(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  @override
  void initState() {
    super.initState();
    _slug = RepositorySlug(widget.owner, widget.repoName);
    loadRepo();
  }

  @override
  void dispose() {
    _progressThrottle?.cancel();
    super.dispose();
  }

  Future<void> loadRepo() async {
    try {
      final r = await GithubService.instance.getRepo(_slug);
      final brs = await GithubService.instance.listBranches(_slug);

      setState(() {
        repo = r;
        branches = brs;
        selectedRef = r.defaultBranch;
      });
      // 加载默认分支 readme
      await loadReadme();
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载仓库失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadReadme() async {
    if (selectedRef == null) return;
    try {
      final readmeItem = await GithubService.instance.getReadme(_slug, ref: selectedRef);
      if (readmeItem.content != null) {
        setState(() {
          readme = utf8.decode(base64.decode(readmeItem.content!));
        });
      } else {
        setState(() => readme = '');
      }
    } catch (e) {
      setState(() => readme = '');
    }
  }

  Future<void> doDownload() async {
    if (selectedRef == null || selectedRef!.isEmpty) return;

    setState(() {
      downloading = true;
      downloadRecv = 0;
      downloadTotal = 0;
    });
    try {
      final token = await SecureStorageService.getAccessToken();
      print("read token result: $token");
      // 👉 删掉：if (token == null) throw Exception('缺少 GitHub Token，请先登录');
      // 现在 token 允许 null，匿名下载公开仓库

      final localRepo = await LocalArchiveService.instance.downloadAndExtract(
        owner: widget.owner,
        repo: widget.repoName,
        ref: selectedRef!,
        token: token ?? "",
        onProgress: (recv, total) {
          // 节流：100ms 刷新一次 UI，防止疯狂 rebuild
          if (_progressThrottle?.isActive ?? false) return;
          _progressThrottle = Timer(const Duration(milliseconds: 100), () {
            if (mounted) {
              setState(() {
                downloadRecv = recv;
                downloadTotal = total;
              });
            }
          });
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 下载解压完成')));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FileTreePage(localRepo: localRepo)),
        );
      }
    } catch (e, st) {
      log('下载归档失败', error: e, stackTrace: st);
      if (mounted) {
        String msg = '$e';
        if (msg.contains("401") || msg.contains("404")) {
          msg = "私有仓库或Token失效，请登录";
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg')));
      }
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.owner}/${widget.repoName}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : repo == null
          ? const Center(child: Text('仓库加载失败'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    repo?.description ?? '',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),

                  // 分支行：Expanded 防止溢出
                  Row(
                    children: [
                      const Text('分支：', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          value: selectedRef,
                          isExpanded: true,
                          items: branches
                              .where((b) => b.name != null)
                              .map((b) => DropdownMenuItem(value: b.name, child: Text(b.name!)))
                              .toList(),
                          onChanged: downloading
                              ? null
                              : (v) {
                                  setState(() {
                                    selectedRef = v;
                                    // 切换分支清空下载进度
                                    downloadRecv = 0;
                                    downloadTotal = 0;
                                  });
                                  loadReadme();
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 下载卡片
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (downloading) ...[
                            LinearProgressIndicator(
                              value: downloadTotal > 0 ? downloadRecv / downloadTotal : null,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              downloadTotal > 0
                                  ? "${formatBytes(downloadRecv)} / ${formatBytes(downloadTotal)}"
                                  : "已下载：${formatBytes(downloadRecv)}（流式传输，无总大小）",
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          ElevatedButton(
                            onPressed: downloading ? null : doDownload,
                            child: const Text('下载归档到本地'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // README 卡片
                  const Text('README', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: readme.isNotEmpty
                          ? MarkdownBody(data: readme)
                          : const Text('无 README', style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
