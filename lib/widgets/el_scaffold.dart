import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Color backgroundColor;

  const ElScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.backgroundColor = ElTheme.bgPage,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: backgroundColor, appBar: appBar, body: body);
  }
}
