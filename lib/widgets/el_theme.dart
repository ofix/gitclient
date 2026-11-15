import 'package:material_ui/material_ui.dart';

class ElTheme {
  static const Color primary = Color(0xFF409EFF);
  static const Color success = Color(0xFF67C23A);
  static const Color warning = Color(0xFFE6A23C);
  static const Color danger = Color(0xFFF56C6C);
  static const Color info = Color(0xFF909399);

  static const Color textPrimary = Color(0xFF303133);
  static const Color textRegular = Color(0xFF606266);
  static const Color textPlaceholder = Color(0xFFC0C4CC);

  static const Color border = Color(0xFFDCDFE6);
  static const Color bgPage = Color(0xFFF5F7FA);
  static const Color bgCard = Colors.white;

  static const Radius radius = Radius.circular(6);
  static const double radiusVal = 6;
  static const BoxShadow cardShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.08),
    offset: Offset(0, 2),
    blurRadius: 12,
  );

  static const double controlHeight = 36;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

Color getLangColor(String? lang) {
  switch (lang?.toLowerCase()) {
    case 'dart':
      return const Color(0xFF00B4AB);
    case 'javascript':
      return const Color(0xFFF1E05A);
    case 'typescript':
      return const Color(0xFF3178C6);
    case 'python':
      return const Color(0xFF3572A5);
    case 'java':
      return const Color(0xFFB07219);
    case 'c++':
      return const Color(0xFFF34B7D);
    case 'c':
      return const Color(0xFF555555);
    case 'go':
      return const Color(0xFF00ADD8);
    case 'rust':
      return const Color(0xFFDEA584);
    default:
      return ElTheme.textPlaceholder;
  }
}

String formatUpdate(DateTime? time) {
  if (time == null) return '-';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inDays < 1) return '今天';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} 月前';
  return '${(diff.inDays / 365).floor()} 年前';
}

String makeRepoId(String owner, String repo, String branch) {
  final safe = branch.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return '${owner}_${repo}_$safe';
}
