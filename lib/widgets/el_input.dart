import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElInput extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onSubmitted;

  const ElInput({super.key, required this.controller, this.hintText = '', this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(fontSize: 14, color: ElTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: ElTheme.textPlaceholder),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(ElTheme.radius),
          borderSide: const BorderSide(color: ElTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(ElTheme.radius),
          borderSide: const BorderSide(color: ElTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(ElTheme.radius),
          borderSide: const BorderSide(color: ElTheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onSubmitted: onSubmitted,
    );
  }
}
