import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import 'clickable_gesture_detector.dart';

class CustomTimeframeDropdown extends StatefulWidget {
  final String selectedPeriod;
  final ValueChanged<String> onChanged;
  final List<String>? options;

  const CustomTimeframeDropdown({
    super.key,
    required this.selectedPeriod,
    required this.onChanged,
    this.options,
  });

  static String localizePeriod(String period) {
    switch (period) {
      case 'Today':
        return 'today'.tr();
      case 'Week':
      case 'This Week':
        return 'this_week'.tr();
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return 'this_month'.tr();
      case '3 Month':
      case '3 Months':
        return '3_month'.tr();
      case '6 Month':
      case '6 Months':
      case 'Last 6 Months':
        return 'last_6_months'.tr();
      case 'Yearly':
      case 'This Year':
        return 'this_year'.tr();
      default:
        return period;
    }
  }

  @override
  State<CustomTimeframeDropdown> createState() =>
      _CustomTimeframeDropdownState();
}

class _CustomTimeframeDropdownState extends State<CustomTimeframeDropdown> {
  bool _isOpen = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<String> get _options =>
      widget.options ??
      const ['Today', 'This Week', 'This Month', 'Last 6 Months', 'This Year'];

  /// Maps legacy/aliased raw period values to the canonical option label so
  /// selection matching (bullet/check indicator) works even when the caller
  /// uses e.g. 'Month' while the menu option is 'This Month'.
  static String _canonicalPeriod(String period) {
    switch (period.trim()) {
      case 'Today':
        return 'Today';
      case 'Week':
      case 'This Week':
        return 'This Week';
      case 'Month':
      case 'Monthly':
      case 'This Month':
        return 'This Month';
      case '3 Month':
      case '3 Months':
        return '3 Month';
      case '6 Month':
      case '6 Months':
      case 'Last 6 Months':
        return 'Last 6 Months';
      case 'Yearly':
      case 'This Year':
        return 'This Year';
      default:
        return period;
    }
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _closeDropdown();
    } else {
      _openDropdown();
    }
  }

  void _openDropdown() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final menuWidth = size.width;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _closeDropdown,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Positioned(
            width: menuWidth,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              child: Material(
                elevation: 4,
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFCFC),
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _options.map((option) {
                      final isSelected =
                          _canonicalPeriod(widget.selectedPeriod) ==
                          _canonicalPeriod(option);
                      return GestureDetector(
                        onTap: () {
                          widget.onChanged(option);
                          _closeDropdown();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF0247C4)
                                        : Colors.grey.shade400,
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF0247C4),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  CustomTimeframeDropdown.localizePeriod(
                                    option,
                                  ),
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    color: isSelected
                                        ? const Color(0xFF0247C4)
                                        : Colors.grey.shade400,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isOpen = true;
    });
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      setState(() {
        _isOpen = false;
      });
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: Container(
          constraints: const BoxConstraints(minWidth: 125),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0247C4),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(6),
              topRight: const Radius.circular(6),
              bottomLeft: Radius.circular(_isOpen ? 0 : 6),
              bottomRight: Radius.circular(_isOpen ? 0 : 6),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  CustomTimeframeDropdown.localizePeriod(widget.selectedPeriod),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.w600,
                    fontSize: 17.0,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_drop_down,
                color: Color(0xFFFFFFFF),
                size: 30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
