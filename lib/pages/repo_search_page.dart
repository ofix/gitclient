import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:github/github.dart';

import '../services/secure_storage_service.dart';
import '../widgets/el_theme.dart';
import 'download_task.dart';
import '../widgets/el_button.dart';
import '../widgets/el_card.dart';
import '../widgets/el_search_box.dart';
import '../widgets/el_progress.dart';
import '../widgets/el_scaffold.dart';
import '../widgets/el_appbar.dart';
import '../widgets/el_message.dart';
import '../widgets/el_select.dart';
import '../services/github_service.dart';
import './repo_detail_page.dart';
import '../services/local_archive_service.dart';
import 'login_page.dart';

String makeRepoId(String owner, String repo, String ref) {
  return "$owner/$repo@$ref";
}

String formatBytes(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(1)} KB";
  if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
  return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
}

Color getLangColor(String? lang) {
  const colorMap = <String, Color>{
    "Dart": Color(0xFF00B4AB),
    "C++": Color(0xFF00599C),
    "C": Color.fromARGB(255, 168, 36, 36),
    "Python": Color(0xFF3776AB),
    "JavaScript": Color(0xFFF1E05A),
    "TypeScript": Color(0xFF3178C6),
    "Go": Color(0xFF00ADD8),
    "Rust": Color(0xFFDEA584),
    "Java": Color(0xFFB07219),
  };
  return colorMap[lang] ?? const Color(0xFF888888);
}

class _SimpleLoading extends StatelessWidget {
  const _SimpleLoading();
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("loading..."));
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final List<Repository> items = [];
  bool loading = false;
  final Map<String, DownloadTaskItem> taskMap = {};

  Future<bool> _checkLocalExists(String owner, String repo, String branch) async {
    try {
      final dirPath = await LocalArchiveService.instance.getRepoPath(owner, repo, branch);
      final dir = Directory(dirPath);
      return await dir.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> runSearch() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      ElMessage.warning(context, '请输入关键词');
      return;
    }
    setState(() {
      items.clear();
      loading = true;
    });
    try {
      final stream = await GithubService.instance.searchRepos(q, pages: 2);
      final batch = <Repository>[];
      await for (final r in stream) {
        if (!mounted) break;
        batch.add(r);
      }
      if (mounted) setState(() => items.addAll(batch));
    } catch (e) {
      if (mounted) ElMessage.error(context, '搜索失败 $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> startDownload(Repository repo, String branch) async {
    final owner = repo.owner?.login ?? '';
    final repoName = repo.name;
    final rid = makeRepoId(owner, repoName, branch);
    if (taskMap[rid]?.status == DownloadStatus.downloading) return;

    final cancel = CancelToken();
    final task = DownloadTaskItem(
      repoId: rid,
      owner: owner,
      repoName: repoName,
      branch: branch,
      status: DownloadStatus.downloading,
      receivedBytes: 0,
      totalBytes: null,
      cancelToken: cancel,
    );
    setState(() => taskMap[rid] = task);

    try {
      final token = await SecureStorageService.getAccessToken();
      await LocalArchiveService.instance.downloadAndExtract(
        owner: owner,
        repo: repoName,
        ref: branch,
        token: token ?? '',
        cancelToken: cancel,
        refType: "branch",
        onProgress: (recv, total) {
          if (!mounted) return;
          setState(() {
            task.receivedBytes = recv;
            if (total != -1) task.totalBytes = total;
          });
        },
      );
      setState(() => task.status = DownloadStatus.done);
      if (mounted) ElMessage.success(context, '下载完成');
    } catch (e) {
      if (cancel.isCancelled) {
        setState(() => task.status = DownloadStatus.idle);
      } else {
        setState(() => task.status = DownloadStatus.failed);
        if (mounted) ElMessage.error(context, '下载失败 $e');
      }
    }
  }

  void cancelDownload(Repository repo, String branch) {
    final owner = repo.owner?.login ?? '';
    final repoName = repo.name;
    final rid = makeRepoId(owner, repoName, branch);
    final t = taskMap[rid];
    t?.cancelToken.cancel('user cancel');
    if (t != null) setState(() => t.status = DownloadStatus.idle);
  }

  @override
  Widget build(BuildContext context) {
    return ElScaffold(
      appBar: ElAppBar(
        title: const Text('Github Zip Reader'),
        actions: [
          ElButton(
            type: ElButtonType.defaultType,
            height: 34,
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(pageBuilder: (_, __, ___) => const LoginPage()),
            ),
            child: const Text('Token'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          /// Element 搜索框，suffix 纯文字按钮、无底纹
          ElSearchBox(controller: _ctrl, onSearch: runSearch),
          Expanded(
            child: loading
                ? const _SimpleLoading()
                : items.isEmpty
                ? const Center(
                    child: Text('输入关键词搜索仓库', style: TextStyle(color: ElTheme.textPlaceholder)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) {
                      final repo = items[idx];
                      final branch = repo.defaultBranch;
                      final owner = repo.owner?.login ?? '';
                      final rid = makeRepoId(owner, repo.name, branch);
                      final task = taskMap[rid];

                      return _buildRepoCard(repo, owner, branch, task);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepoCard(dynamic repo, String owner, String branch, DownloadTaskItem? task) {
    return ElCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          _buildCardHeader(repo, owner, branch, task),
          if (task != null &&
              (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused))
            _buildProgressArea(task),
        ],
      ),
    );
  }

  Widget _buildCardHeader(dynamic repo, String owner, String branch, DownloadTaskItem? task) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildRepoInfo(repo, owner, branch)),
        const SizedBox(width: 12),
        _buildSideControls(repo, branch, task),
      ],
    );
  }

  Widget _buildRepoInfo(dynamic repo, String owner, String branch) {
    return GestureDetector(
      onTap: () async {
        final exists = await _checkLocalExists(owner, repo.name, branch);
        if (!exists) {
          if (mounted) ElMessage.warning(context, '请先下载该仓库');
          return;
        }
        if (mounted) {
          Navigator.pushNamed(
            context,
            '/repo-detail',
            arguments: {'owner': owner, 'repo': repo.name, 'branch': branch},
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(repo.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            repo.description ?? '',
            maxLines: 2,
            style: const TextStyle(color: ElTheme.textRegular),
          ),
          const SizedBox(height: 8),
          _buildMetaRow(repo),
        ],
      ),
    );
  }

  Widget _buildMetaRow(dynamic repo) {
    return Wrap(
      spacing: 12,
      children: [
        if (repo.language != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: getLangColor(repo.language),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 4),
              Text(repo.language!),
            ],
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_border, size: 16),
            const SizedBox(width: 4),
            Text('${repo.stargazersCount}'),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fork_right, size: 16),
            const SizedBox(width: 4),
            Text('${repo.forksCount}'),
          ],
        ),
      ],
    );
  }

  Widget _buildSideControls(dynamic repo, String branch, DownloadTaskItem? task) {
    return Column(
      children: [
        ElSelect<String>(
          value: branch,
          options: [ElSelectOption(label: branch, value: branch)],
          onChanged: (_) {},
          width: 110,
        ),
        const SizedBox(height: 8),
        _buildActionBtn(repo, branch, task),
      ],
    );
  }

  Widget _buildActionBtn(Repository repo, String branch, DownloadTaskItem? task) {
    if (task == null || task.status == DownloadStatus.idle) {
      return ElButton(
        type: ElButtonType.primary,
        width: 110,
        onTap: () => startDownload(repo, branch),
        child: const Text('下载'),
      );
    }
    if (task.status == DownloadStatus.downloading) {
      return ElButton(
        type: ElButtonType.danger,
        width: 110,
        onTap: () => cancelDownload(repo, branch),
        child: const Text('取消'),
      );
    }
    if (task.status == DownloadStatus.done) {
      return const Text('✅ 已下载', style: TextStyle(color: ElTheme.success));
    }
    return ElButton(
      type: ElButtonType.primary,
      width: 110,
      onTap: () => startDownload(repo, branch),
      child: const Text('重试'),
    );
  }

  Widget _buildProgressArea(DownloadTaskItem task) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          ElProgress(
            value: task.totalBytes != null ? task.receivedBytes / task.totalBytes! * 100 : null,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatBytes(task.receivedBytes)} / ${task.totalBytes != null ? formatBytes(task.totalBytes!) : '...'}',
            style: const TextStyle(fontSize: 12, color: ElTheme.textPlaceholder),
          ),
        ],
      ),
    );
  }
}
