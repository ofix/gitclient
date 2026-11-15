import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart'; // 引入侧滑库

import '../models/local_repo.dart';
import '../services/local_archive_service.dart';
import '../widgets/el_appbar.dart';
import 'file_tree_page.dart';

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

  // 弹出确认删除弹窗并执行删除
  Future<void> _confirmAndDelete(BuildContext context, LocalRepo r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除本地仓库 ${r.name} 吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok == true) {
      await LocalArchiveService.instance.removeRepo(r);
      await refreshList();
    }
  }

  String formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('yyyy-MM-dd HH:mm').format(date);
    } catch (e) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7), // 微信经典浅灰背景
      appBar: ElAppBar(
        title: const Text('本地仓库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.pushNamed(context, '/search');
            },
          ),
        ],
      ),
      body: repos.isEmpty
          ? const Center(child: Text('暂无本地仓库，点右上角搜索去下载'))
          : ListView.separated(
              itemCount: repos.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                thickness: 0.5,
                color: Color(0xFFE5E5E5),
                indent: 16, // 分割线左边距小一点，更自然
              ),
              itemBuilder: (ctx, idx) {
                final r = repos[idx];
                return Slidable(
                  key: ValueKey(r.id ?? r.name),
                  // 配置滑出区域
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(), // 抽屉式滑动动画
                    extentRatio: 0.25, // 核心：限制滑出按钮只占右侧约 1/4 的宽度
                    children: [
                      SlidableAction(
                        onPressed: (context) => _confirmAndDelete(context, r),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: '删除',
                        borderRadius: BorderRadius.circular(8), // 稍微给点圆角
                      ),
                    ],
                  ),
                  child: Container(
                    color: Colors.white, // 列表项背景纯白
                    child: ListTile(
                      // 去掉 leading，纯文字排版
                      title: Padding(
                        padding: const EdgeInsets.only(bottom: 4, top: 4),
                        child: Text(
                          r.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '分支：${r.ref} | 下载：${formatDate(r.downloadedAt)}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF888888)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '路径：${r.rootDir}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FileTreePage(
                              owner: r.owner,
                              repo: r.name,
                              ref: r.ref,
                              relativePath: "",
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
