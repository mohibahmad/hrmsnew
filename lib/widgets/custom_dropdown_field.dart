import 'package:flutter/material.dart';

class CustomDropdownField extends StatefulWidget {
  final String label;
  final String selectedValue;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String? Function(String item)? itemLabelBuilder;

  const CustomDropdownField({
    super.key,
    required this.label,
    required this.selectedValue,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.itemLabelBuilder,
  });

  @override
  State<CustomDropdownField> createState() => _CustomDropdownFieldState();
}

class _CustomDropdownFieldState extends State<CustomDropdownField> {
  late String _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.selectedValue;
  }

  @override
  void didUpdateWidget(covariant CustomDropdownField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedValue != oldWidget.selectedValue) {
      _currentValue = widget.selectedValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: Color(0xFF000000),
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        PopupMenuButton<String>(
          tooltip: widget.label,
          onSelected: (val) {
            setState(() {
              _currentValue = val;
            });
            widget.onChanged(val);
          },
          offset: const Offset(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: Colors.grey.shade200, width: 1),
          ),
          color: const Color(0xFFFFFFFF),
          elevation: 4,
          itemBuilder: (context) {
            return widget.items.map((String item) {
              final bool isSelected =
                  item.trim().toLowerCase() ==
                  _currentValue.trim().toLowerCase();
              final displayLabel = widget.itemLabelBuilder?.call(item) ?? item;
              return PopupMenuItem<String>(
                value: item,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMenuRadio(isSelected, displayLabel),
              );
            }).toList();
          },
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _currentValue.isEmpty
                      ? widget.hint
                      : (widget.itemLabelBuilder?.call(_currentValue) ??
                            _currentValue),
                  style: TextStyle(
                    fontSize: 14,
                    color: _currentValue.isEmpty
                        ? Colors.grey.shade400
                        : const Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: Colors.grey.shade400,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuRadio(bool isSelected, String label) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF0247C4)
                  : Colors.grey.shade300,
              width: 2,
            ),
            color: isSelected
                ? const Color(0xFF0247C4)
                : Colors.transparent,
          ),
          child: isSelected
              ? const Icon(
                  Icons.check,
                  size: 12,
                  color: Color(0xFFFFFFFF),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? const Color(0xFF0247C4)
                  : const Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }
}
