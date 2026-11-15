import 'package:material_ui/material_ui.dart';

import '../models/local_repo.dart';
import '../services/local_archive_service.dart';
import 'file_tree_page.dart';
import 'search_page.dart';

class LocalReposPage extends StatefulWidget {
  const LocalReposPage({super.key});

  @override
  State<LocalReposPage> createState() => _LocalReposPageState();
}

class _LocalReposPageState extends State<LocalReposPage> {
  List<LocalRepo> repos = [];

  Future<void> refreshList() async {
    final list = await LocalArchiveService.instance.loadIndex();
    setState(() => repos = list);
  }

  @override
  void initState() {
    super.initState();
    refreshList();
  }

  Future<void> deleteRepo(LocalRepo r) async {
    await LocalArchiveService.instance.removeRepo(r);
    await refreshList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地仓库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage()));
            },
          ),
        ],
      ),
      body: repos.isEmpty
          ? const Center(child: Text('暂无本地仓库，点右上角搜索去下载'))
          : ListView.builder(
              itemCount: repos.length,
              itemBuilder: (ctx, idx) {
                final r = repos[idx];
                return ListTile(
                  title: Text(r.displayName),
                  subtitle: Text('分支：${r.ref} | 下载：${r.downloadedAt}'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FileTreePage(localRepo: r)),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('确认删除'),
                          content: Text('删除 ${r.displayName}？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await deleteRepo(r);
                    },
                  ),
                );
              },
            ),
    );
  }
}
