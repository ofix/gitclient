import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../services/local_archive_service.dart';
import '../widgets/el_theme.dart';
import '../widgets/el_scaffold.dart';
import '../widgets/el_appbar.dart';
import 'code_view_page.dart';

class FileTreePage extends StatefulWidget {
  final String owner;
  final String repo;
  final String ref;
  final String relativePath;

  const FileTreePage({
    super.key,
    required this.owner,
    required this.repo,
    required this.ref,
    required this.relativePath,
  });

  @override
  State<FileTreePage> createState() => _FileTreePageState();
}

class _FileTreePageState extends State<FileTreePage> {
  List<FileSystemEntity> list = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final items = await LocalArchiveService.instance.listFilesByRef(
      widget.owner,
      widget.repo,
      widget.ref,
      widget.relativePath,
    );
    items.sort((a, b) {
      final aDir = a is Directory;
      final bDir = b is Directory;
      if (aDir && !bDir) return -1;
      if (!aDir && bDir) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });
    if (mounted) {
      setState(() {
        list = items;
        loading = false;
      });
    }
  }

  String _langFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return 'dart';
      case 'js':
        return 'javascript';
      case 'ts':
        return 'typescript';
      case 'py':
        return 'python';
      case 'java':
        return 'java';
      case 'cpp':
      case 'hpp':
        return 'cpp';
      case 'c':
      case 'h':
        return 'c';
      case 'go':
        return 'go';
      case 'rs':
        return 'rust';
      case 'md':
        return 'markdown';
      case 'json':
        return 'json';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'xml':
        return 'xml';
      default:
        return 'plaintext';
    }
  }

  Future<void> _openFile(String absolutePath, String fileName) async {
    if (LocalArchiveService.instance.isBinaryFile(absolutePath)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('二进制文件，无法预览')));
      }
      return;
    }

    // ✅ 不再自己读文件 + Text，直接跳 CodeViewPage
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CodeViewPage(filePath: absolutePath)),
    );
  }

  void _enterDir(String newRelative) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileTreePage(
          owner: widget.owner,
          repo: widget.repo,
          ref: widget.ref,
          relativePath: newRelative,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentDisplayPath = widget.relativePath.isEmpty ? '/' : widget.relativePath;
    return ElScaffold(
      appBar: ElAppBar(title: Text(currentDisplayPath)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, idx) {
                final entity = list[idx];
                final name = p.basename(entity.path);
                final isDir = entity is Directory;
                return ListTile(
                  leading: Icon(
                    isDir ? Icons.folder : Icons.insert_drive_file,
                    color: isDir ? ElTheme.primary : ElTheme.textRegular,
                  ),
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  onTap: () {
                    if (isDir) {
                      final nextRel = p.join(widget.relativePath, name);
                      _enterDir(nextRel);
                    } else {
                      _openFile(entity.path, name);
                    }
                  },
                );
              },
            ),
    );
  }
}
