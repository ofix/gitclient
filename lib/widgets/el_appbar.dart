import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget> actions;

  const ElAppBar({super.key, required this.title, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      backgroundColor: Colors.white,
      foregroundColor: ElTheme.textPrimary,
      elevation: 0.5,
      actions: actions,
      surfaceTintColor: Colors.transparent, // 关键：去掉 Material 3 的默认叠色
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
