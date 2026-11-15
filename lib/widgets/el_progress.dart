import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElProgress extends StatelessWidget {
  final double? value; // 0~100

  const ElProgress({super.key, this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 6,
      child: LinearProgressIndicator(
        value: value == null ? null : value! / 100,
        backgroundColor: const Color(0xFFEBEEF5),
        valueColor: AlwaysStoppedAnimation<Color>(ElTheme.primary),
        borderRadius: const BorderRadius.all(Radius.circular(3)),
      ),
    );
  }
}
