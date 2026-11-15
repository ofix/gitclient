import 'dart:async';
import 'dart:convert';

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

  @override
  void initState() {
    super.initState();
    _slug = RepositorySlug(widget.owner, widget.repoName);
    loadRepo();
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

      try {
        final readmeItem = await GithubService.instance.getReadme(_slug, ref: selectedRef);
        if (readmeItem.content != null) {
          readme = utf8.decode(base64.decode(readmeItem.content!));
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载仓库失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
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
    try {
      final token = await SecureStorageService.getToken();
      if (token == null) throw Exception('无 token');

      final localRepo = await LocalArchiveService.instance.downloadAndExtract(
        owner: widget.owner,
        repo: widget.repoName,
        ref: selectedRef!,
        token: token,
        onProgress: (recv, total) {
          setState(() {
            downloadRecv = recv;
            downloadTotal = total;
          });
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载解压完成')));
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FileTreePage(localRepo: localRepo)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('下载失败：$e')));
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
                  Text(repo!.description, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('分支：'),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: selectedRef,
                        items: branches
                            .where((b) => b.name != null)
                            .map((b) => DropdownMenuItem(value: b.name, child: Text(b.name!)))
                            .toList(),
                        onChanged: (v) => setState(() => selectedRef = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (downloading)
                    Column(
                      children: [
                        LinearProgressIndicator(
                          value: downloadTotal > 0 ? downloadRecv / downloadTotal : null,
                        ),
                        const SizedBox(height: 4),
                        Text('$downloadRecv / $downloadTotal bytes'),
                      ],
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: downloading ? null : doDownload,
                    child: const Text('下载归档到本地'),
                  ),
                  const SizedBox(height: 20),
                  const Text('README', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (readme.isNotEmpty) MarkdownBody(data: readme) else const Text('无 README'),
                ],
              ),
            ),
    );
  }
}
