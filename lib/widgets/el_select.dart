import 'package:material_ui/material_ui.dart';

import 'el_theme.dart';

class ElSelectOption<T> {
  final String label;
  final T value;
  const ElSelectOption({required this.label, required this.value});
}

class ElSelect<T> extends StatelessWidget {
  final T value;
  final List<ElSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final double height;
  final double? width;

  const ElSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.height = ElTheme.controlHeight,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(6),
        elevation: 4,
        style: const TextStyle(color: Color(0xFF303133), fontSize: 14),
        menuMaxHeight: 200,
        // ✅ 关键：控制【收起框里面显示的文字】，强制单行+截断，根治糊字
        selectedItemBuilder: (ctx) {
          return options.map((opt) {
            return Text(opt.label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis);
          }).toList();
        },
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: ElTheme.border, width: 1.0),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: ElTheme.border, width: 1.0),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            // ✅ 修正：聚焦边框切主题主色
            borderSide: const BorderSide(color: ElTheme.primary, width: 1.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        items: options
            .map(
              (opt) => DropdownMenuItem(
                value: opt.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(opt.label),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
