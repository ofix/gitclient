import 'package:material_ui/material_ui.dart';
import 'package:github/github.dart';

import '../services/github_service.dart';
import 'repo_detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final List<Repository> items = [];
  bool loading = false;

  Future<void> runSearch() async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      items.clear();
      loading = true;
    });
    try {
      // 重点：加 await，取出 Stream
      final stream = await GithubService.instance.searchRepos(query, pages: 2);
      final batch = <Repository>[];
      await for (final repo in stream) {
        if (!mounted) break;
        batch.add(repo);
      }
      if (mounted && batch.isNotEmpty) {
        setState(() {
          items.addAll(batch);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('搜索失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索仓库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '搜索仓库，例如 flutter',
                    ),
                    onSubmitted: (_) => runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: runSearch, child: const Text('搜索')),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? loading
                      ? const Center(child: CircularProgressIndicator())
                      : const Center(child: Text('输入关键词搜索'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) {
                      final repo = items[idx];
                      return ListTile(
                        title: Text(repo.fullName),
                        subtitle: Text(
                          repo.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [Text('⭐ ${repo.stargazersCount}'), Text(repo.language)],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RepoDetailPage(
                                owner: repo.owner?.login ?? '',
                                repoName: repo.name,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
