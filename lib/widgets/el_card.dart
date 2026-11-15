import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const ElCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: ElTheme.bgCard,
        borderRadius: BorderRadius.all(ElTheme.radius),
        boxShadow: [ElTheme.cardShadow],
      ),
      child: child,
    );
  }
}
