import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElSearchBox extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final String hintText;

  const ElSearchBox({
    super.key,
    required this.controller,
    required this.onSearch,
    this.hintText = '搜索仓库，例如 flutter',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: controller,
        onSubmitted: (_) => onSearch(),
        style: const TextStyle(color: ElTheme.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: ElTheme.bgCard,
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
          hintText: hintText,
          hintStyle: const TextStyle(color: ElTheme.textPlaceholder),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: TextButton(
            onPressed: onSearch,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(44, 32),
            ),
            child: const Text('搜索', style: TextStyle(color: ElTheme.primary, fontSize: 14)),
          ),
        ),
      ),
    );
  }
}
