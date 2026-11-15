import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class FileTreeTile extends StatelessWidget {
  final FileSystemEntity entity;
  final int depth;
  final bool isExpanded;

  /// 点击箭头（仅目录有效）
  final VoidCallback? onToggleExpand;

  /// 点击整行：文件打开；目录可以不处理，交给箭头
  final VoidCallback? onTap;

  const FileTreeTile({
    super.key,
    required this.entity,
    required this.depth,
    this.isExpanded = false,
    this.onToggleExpand,
    this.onTap,
  });

  /// 根据后缀获取文件图标
  IconData _fileIcon(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.dart':
        return Icons.code;
      case '.js':
      case '.ts':
        return Icons.javascript;
      case '.go':
        return Icons.outlined_flag;
      case '.py':
        return Icons.terminal;
      case '.md':
        return Icons.article;
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final indent = depth * 16.0;

    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: ListTile(
        dense: true,
        minLeadingWidth: 24,
        onTap: isDir ? onToggleExpand : onTap,
        leading: isDir
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.arrow_right, size: 16),
                  ),
                  const SizedBox(width: 4),
                  Icon(isExpanded ? Icons.folder_open : Icons.folder, size: 18),
                ],
              )
            : Icon(_fileIcon(name), size: 18),
        title: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
