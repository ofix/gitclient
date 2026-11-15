import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElMessage {
  static void show(BuildContext context, String msg, {Color color = ElTheme.primary}) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: MediaQuery.of(ctx).padding.top + 20,
        left: 20,
        right: 20,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.92),
              borderRadius: const BorderRadius.all(Radius.circular(6)),
            ),
            child: Text(msg, style: const TextStyle(color: Colors.white)),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1600), () => entry.remove());
  }

  static void success(BuildContext context, String msg) =>
      show(context, msg, color: ElTheme.success);
  static void warning(BuildContext context, String msg) =>
      show(context, msg, color: ElTheme.warning);
  static void error(BuildContext context, String msg) => show(context, msg, color: ElTheme.danger);
}
