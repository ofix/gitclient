import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:github/github.dart';
import 'package:dio/dio.dart';

import '../services/github_service.dart';
import '../services/local_archive_service.dart';
import '../services/secure_storage_service.dart';
import '../models/local_repo.dart';
import 'file_tree_page.dart';

class RepoDetailPage extends StatefulWidget {
  final String owner;
  final String repo;
  final String branch;
  const RepoDetailPage({super.key, required this.owner, required this.repo, required this.branch});

  @override
  State<RepoDetailPage> createState() => _RepoDetailPageState();
}

class _RepoDetailPageState extends State<RepoDetailPage> {
  Repository? repo;
  List<Branch> branches = [];
  String? selectedRef;
  bool loading = true;
  bool downloading = false;
  bool refreshingRemote = false;
  int downloadRecv = 0;
  int downloadTotal = 0;
  String readme = '';

  late final RepositorySlug _slug;
  Timer? _progressThrottle;
  CancelToken? _downloadCancelToken;

  List<LocalRepo> localBranches = [];

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
    _slug = RepositorySlug(widget.owner, widget.repo);
    loadRepo();
    loadLocalBranches();
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

  Future<void> loadLocalBranches() async {
    final list = await LocalArchiveService.instance.findByOwnerRepo(widget.owner, widget.repo);
    if (mounted) {
      setState(() {
        localBranches = list;
      });
    }
  }

  Future<void> refreshRemoteStatus() async {
    setState(() => refreshingRemote = true);
    try {
      final token = await SecureStorageService.getAccessToken();
      await LocalArchiveService.instance.refreshRepoRemoteStatus(
        widget.owner,
        widget.repo,
        token: token,
      );
      await loadLocalBranches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('远端版本检查完成')));
      }
    } catch (e, st) {
      log('refresh remote', error: e, stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('检查更新失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => refreshingRemote = false);
      }
    }
  }

  Future<void> doDownload() async {
    if (selectedRef == null || selectedRef!.isEmpty) return;

    setState(() {
      downloading = true;
      downloadRecv = 0;
      downloadTotal = 0;
    });
    _downloadCancelToken = CancelToken();
    try {
      final token = await SecureStorageService.getAccessToken();
      print("read token result: $token");

      final localRepo = await LocalArchiveService.instance.downloadAndExtract(
        owner: widget.owner,
        repo: widget.repo,
        ref: selectedRef!,
        refType: 'branch',
        token: token ?? "",
        cancelToken: _downloadCancelToken,
        onProgress: (recv, total) {
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

      await loadLocalBranches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ 下载解压完成')));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FileTreePage(
              owner: localRepo.owner,
              repo: localRepo.name,
              ref: localRepo.ref,
              relativePath: '',
            ),
          ),
        );
      }
    } catch (e, st) {
      log('下载归档失败', error: e, stackTrace: st);
      if (mounted) {
        String msg = '$e';
        if (msg.contains("401") || msg.contains("404")) {
          msg = "私有仓库或Token失效，请登录";
        }
        if (e is DioException && CancelToken.isCancel(e)) {
          msg = "下载已取消";
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $msg')));
      }
    } finally {
      if (mounted) {
        setState(() => downloading = false);
      }
      _downloadCancelToken = null;
    }
  }

  Future<void> deleteLocalBranch(LocalRepo item) async {
    await LocalArchiveService.instance.removeRepo(item);
    await loadLocalBranches();
  }

  void enterLocalBranch(LocalRepo item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FileTreePage(owner: item.owner, repo: item.name, ref: item.ref, relativePath: ''),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.owner}/${widget.repo}')),
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

                  // 远端分支下拉
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
                            TextButton(
                              onPressed: () => _downloadCancelToken?.cancel(),
                              child: const Text('取消下载', style: TextStyle(color: Colors.red)),
                            ),
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

                  // 本地已下载分支区域
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '📂 已下载分支',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      ElevatedButton(
                        onPressed: refreshingRemote ? null : refreshRemoteStatus,
                        child: refreshingRemote
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('检查更新'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (localBranches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('暂无本地归档分支'),
                    )
                  else
                    ...localBranches.map((item) {
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.ref,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  if (item.isStale)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '有更新',
                                        style: TextStyle(color: Colors.orange, fontSize: 12),
                                      ),
                                    )
                                  else if (item.remoteLatestSha != null)
                                    const Text(
                                      '已是最新',
                                      style: TextStyle(color: Colors.green, fontSize: 12),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('类型：${item.refType}'),
                              Text(
                                '本地 SHA：${item.localCommitSha ?? "未知"}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '下载时间：${item.downloadedAt}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: () => enterLocalBranch(item),
                                    child: const Text('浏览源码'),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    onPressed: () => deleteLocalBranch(item),
                                    child: const Text('删除', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  // README
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
