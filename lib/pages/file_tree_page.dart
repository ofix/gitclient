import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../models/local_repo.dart';
import '../services/local_archive_service.dart';
import '../widgets/file_tree_tile.dart';
import 'code_view_page.dart';

class FileTreePage extends StatefulWidget {
  final LocalRepo localRepo;
  const FileTreePage({super.key, required this.localRepo});

  @override
  State<FileTreePage> createState() => _FileTreePageState();
}

class _FileTreePageState extends State<FileTreePage> {
  // key: entity.path
  final Map<String, bool> expanded = {};

  Widget buildSubTree(String dirPath, int depth) {
    return FutureBuilder<List<FileSystemEntity>>(
      future: LocalArchiveService.instance.listDir(dirPath).toList(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 24,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final entries = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: entries.map((ent) {
            final isDir = ent is Directory;
            final tile = FileTreeTile(
              entity: ent,
              depth: depth,
              isExpanded: expanded[ent.path] ?? false,
              onToggleExpand: () {
                setState(() {
                  expanded[ent.path] = !(expanded[ent.path] ?? false);
                });
              },
              onTap: () {
                if (!isDir) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => CodeViewPage(filePath: ent.path)),
                  );
                }
              },
            );
            if (isDir && (expanded[ent.path] ?? false)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [tile, buildSubTree(ent.path, depth + 1)],
              );
            }
            return tile;
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.localRepo.displayName)),
      body: SingleChildScrollView(child: buildSubTree(widget.localRepo.rootDir, 0)),
    );
  }
}
