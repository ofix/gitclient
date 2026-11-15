import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

enum ElButtonType { primary, success, warning, danger, info, defaultType }

class ElButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final ElButtonType type;
  final double? width;
  final double height;

  const ElButton({
    super.key,
    required this.child,
    this.onTap,
    this.type = ElButtonType.defaultType,
    this.width,
    this.height = ElTheme.controlHeight,
  });

  Color _bg() {
    switch (type) {
      case ElButtonType.primary:
        return ElTheme.primary;
      case ElButtonType.success:
        return ElTheme.success;
      case ElButtonType.warning:
        return ElTheme.warning;
      case ElButtonType.danger:
        return ElTheme.danger;
      case ElButtonType.info:
        return ElTheme.info;
      default:
        return Colors.white;
    }
  }

  Color _textColor() {
    if (type == ElButtonType.defaultType) return ElTheme.textPrimary;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _bg(),
          foregroundColor: _textColor(),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(ElTheme.radius)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          elevation: 0,
        ),
        onPressed: onTap,
        child: child,
      ),
    );
  }
}
