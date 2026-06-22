import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';

import '../widgets/custom_timeframe_dropdown.dart';
import '../utils/snackbar_utils.dart';
import '../utils/delete_dialog.dart';
import '../utils/premium_gate.dart';
import '../services/preferences_service.dart';
import '../widgets/amount_text.dart';

class ExpensesScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const ExpensesScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool isDataEmpty = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> _expensesDocs = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Week';
  int _currentPage = 1;
  static const int _itemsPerPage = 8;
  StreamSubscription? _expensesSub;

  @override
  void dispose() {
    _expensesSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _expensesDocs = [];
    _isLoading = true;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _expensesSub = FirestoreService().expensesStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              final sortedList = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              sortedList.sort((a, b) {
                final aTime = a['createdAt'];
                final bTime = b['createdAt'];
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return -1;
                if (bTime == null) return 1;
                if (aTime is Timestamp && bTime is Timestamp) {
                  return bTime.compareTo(aTime);
                }
                return 0;
              });
              _expensesDocs = sortedList;
              _isLoading = false;
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        },
      );
    } else {
      _expensesDocs = DummyData.expenses
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _isLoading = false;
      _adjustDummyDatesForPeriod(_selectedPeriod);
    }
  }

  double get _totalExpenseSum {
    if (isDataEmpty) return 0.0;
    return _filteredExpenses.fold(0.0, (sum, doc) {
      return sum + ((doc['amount'] ?? 0).toDouble());
    });
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(symbol: '\$ ', decimalDigits: 2);
    return format.format(amount);
  }

  bool _isDateWithinPeriod(String dateStr, String period) {
    try {
      final parts = dateStr.split('/');
      if (parts.length != 3) return true;
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final date = DateTime(year, month, day);

      final now = DateTime.now();
      // Cap at June 10, 2026 if today is earlier, to ensure dummy data shows up correctly
      final refDate = now.isBefore(DateTime(2026, 6, 10))
          ? DateTime(2026, 6, 10)
          : now;

      final diff = refDate.difference(date).inDays;
      if (diff < 0) {
        // Future/newly added date, keep visible
        return true;
      }

      if (period == 'Week') {
        return diff <= 7;
      } else if (period == 'Month') {
        return diff <= 30;
      } else if (period == '3 Month') {
        return diff <= 90;
      } else if (period == '6 Month') {
        return diff <= 180;
      } else if (period == 'Yearly') {
        return diff <= 365;
      }
    } catch (_) {}
    return true;
  }

  void _adjustDummyDatesForPeriod(String period) {
    if (_expensesDocs.isEmpty) return;

    final now = DateTime.now();
    int maxDays = 7;
    if (period == 'Week')
      maxDays = 7;
    else if (period == 'Month')
      maxDays = 30;
    else if (period == '3 Month')
      maxDays = 90;
    else if (period == '6 Month')
      maxDays = 180;
    else if (period == 'Yearly')
      maxDays = 365;

    for (int i = 0; i < _expensesDocs.length; i++) {
      int daysAgo = (i * maxDays / _expensesDocs.length).floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      final dayStr = newDate.day.toString().padLeft(2, '0');
      final monthStr = newDate.month.toString().padLeft(2, '0');
      final yearStr = newDate.year.toString();
      _expensesDocs[i]['date'] = '$dayStr/$monthStr/$yearStr';
    }
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    return _expensesDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final category = (doc['category'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final dateStr = (doc['date'] ?? '').toString();

      final matchesSearch = name.contains(query) || category.contains(query);
      final matchesPeriod = _isDateWithinPeriod(dateStr, _selectedPeriod);
      return matchesSearch && matchesPeriod;
    }).toList();
  }

  Future<void> _deleteExpense(String docId) async {
    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_expense'.tr(),
      content: 'delete_expense_desc'.tr(),
    );
    if (!confirmed) return;

    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      setState(() {
        _expensesDocs.removeWhere((e) => e['id'] == docId);
        DummyData.expenses.removeWhere((e) => e['id'] == docId);
      });
    } else {
      await FirestoreService().deleteExpense(docId);
    }
  }

  void _editExpense(Map<String, dynamic> doc) {
    final categoryController = TextEditingController(
      text: doc['category']?.toString() ?? '',
    );
    final amountController = TextEditingController(
      text: doc['amount']?.toString() ?? '0.00',
    );
    final descriptionController = TextEditingController(
      text: doc['description']?.toString() ?? '',
    );
    final docId = doc['id'] as String;

    final dateParts = (doc['date']?.toString() ?? '').split('/');
    int selectedDay = dateParts.isNotEmpty
        ? int.tryParse(dateParts[0]) ?? DateTime.now().day
        : DateTime.now().day;
    DateTime calendarDate = DateTime.now();

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          'edit_expense'.tr(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () async {
                            if (categoryController.text.trim().isEmpty) {
                              FlashySnackBar.show(
                                context,
                                message: 'please_enter_category'.tr(),
                                isError: true,
                              );
                              return;
                            }
                            final double? amt = double.tryParse(
                              amountController.text.trim(),
                            );
                            if (amt == null) {
                              FlashySnackBar.show(
                                context,
                                message: 'please_enter_valid_amount'.tr(),
                                isError: true,
                              );
                              return;
                            }
                            final dateStr =
                                '${selectedDay.toString().padLeft(2, '0')}/${calendarDate.month.toString().padLeft(2, '0')}/${calendarDate.year}';
                            final updatedMap = {
                              'name': doc['name'],
                              'date': dateStr,
                              'category': categoryController.text,
                              'amount': amt,
                              'description': descriptionController.text,
                            };
                            final isGuest =
                                AuthService().currentUser?.isAnonymous ?? false;
                            if (isGuest) {
                              setState(() {
                                final idx = _expensesDocs.indexWhere(
                                  (e) => e['id'] == docId,
                                );
                                if (idx != -1)
                                  _expensesDocs[idx] = {
                                    ...updatedMap,
                                    'id': docId,
                                  };
                                final dummyIdx = DummyData.expenses.indexWhere(
                                  (e) => e['id'] == docId,
                                );
                                if (dummyIdx != -1)
                                  DummyData.expenses[dummyIdx] = {
                                    ...updatedMap,
                                    'id': docId,
                                  };
                              });
                            } else {
                              await FirestoreService().updateExpense(
                                docId,
                                updatedMap,
                              );
                            }
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            FlashySnackBar.show(
                              context,
                              message: 'expense_updated'.tr(),
                            );
                          },
                          child: Text(
                            'save'.tr(),
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildModalTextField(
                            'expense_category'.tr(),
                            categoryController,
                            hintText: 'expense_category_hint'.tr(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalTextField(
                            'amount_dollar'.tr(),
                            amountController,
                            hintText: '0.00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'expense_title'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF000000),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 215,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: TextField(
                                  controller: descriptionController,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    hintText: 'expense_title_hint'.tr(),
                                    contentPadding: const EdgeInsets.only(
                                      top: 1,
                                    ),
                                    hintStyle: const TextStyle(
                                      color: Colors.grey,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalCalendar(
                            calendarDate,
                            selectedDay,
                            (day) {
                              setModalState(() {
                                selectedDay = day;
                              });
                            },
                            (newDate) {
                              setModalState(() {
                                calendarDate = newDate;
                                int daysInNewMonth = DateTime(
                                  newDate.year,
                                  newDate.month + 1,
                                  0,
                                ).day;
                                if (selectedDay > daysInNewMonth) {
                                  selectedDay = daysInNewMonth;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddExpenseModal(BuildContext context) {
    final categoryController = TextEditingController();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int selectedDay = DateTime.now().day;
    DateTime calendarDate = DateTime.now();

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === Modal Header ===
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          'add_expense'.tr(),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () {
                            if (categoryController.text.trim().isEmpty) {
                              FlashySnackBar.show(
                                context,
                                message: 'please_enter_category'.tr(),
                                isError: true,
                              );
                              return;
                            }
                            final double? amt = double.tryParse(
                              amountController.text.trim(),
                            );
                            if (amt == null) {
                              FlashySnackBar.show(
                                context,
                                message: 'please_enter_valid_amount'.tr(),
                                isError: true,
                              );
                              return;
                            }
                            final dateStr =
                                '${selectedDay.toString().padLeft(2, '0')}/${calendarDate.month.toString().padLeft(2, '0')}/${calendarDate.year}';
                            final isGuest =
                                AuthService().currentUser?.isAnonymous ?? false;
                            final expenseMap = {
                              'name':
                                  AuthService().currentUser?.displayName ??
                                  'Expense',
                              'date': dateStr,
                              'category': categoryController.text,
                              'amount': amt,
                              'description': descriptionController.text,
                            };
                            if (isGuest) {
                              final newId =
                                  'dummy_e${DateTime.now().millisecondsSinceEpoch}';
                              setState(() {
                                _expensesDocs.insert(0, {
                                  ...expenseMap,
                                  'id': newId,
                                });
                                DummyData.expenses.insert(0, {
                                  ...expenseMap,
                                  'id': newId,
                                });
                              });
                            } else {
                              FirestoreService().addExpense(expenseMap);
                            }
                            Navigator.of(context).pop();
                            FlashySnackBar.show(
                              context,
                              message: 'successfully_added_expense'.tr(
                                namedArgs: {'name': categoryController.text},
                              ),
                            );
                          },
                          child: Text(
                            'save'.tr(),
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // === Modal Form Rows ===
                    Row(
                      children: [
                        Expanded(
                          child: _buildModalTextField(
                            'expense_category'.tr(),
                            categoryController,
                            hintText: 'expense_category_hint'.tr(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalTextField(
                            'amount_dollar'.tr(),
                            amountController,
                            hintText: '0.00',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'expense_title'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF000000),
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 215,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: TextField(
                                  controller: descriptionController,
                                  maxLines: null,
                                  decoration: InputDecoration(
                                    hintText: 'expense_title_hint'.tr(),
                                    contentPadding: const EdgeInsets.only(
                                      top: 1,
                                    ),
                                    hintStyle: const TextStyle(
                                      color: Colors.grey,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalCalendar(
                            calendarDate,
                            selectedDay,
                            (day) {
                              setModalState(() {
                                selectedDay = day;
                              });
                            },
                            (newDate) {
                              setModalState(() {
                                calendarDate = newDate;
                                int daysInNewMonth = DateTime(
                                  newDate.year,
                                  newDate.month + 1,
                                  0,
                                ).day;
                                if (selectedDay > daysInNewMonth) {
                                  selectedDay = daysInNewMonth;
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalTextField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    String hintText = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters:
                (keyboardType ==
                        const TextInputType.numberWithOptions(decimal: true) ||
                    keyboardType == TextInputType.number ||
                    label.toLowerCase().contains('amount'))
                ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))]
                : null,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModalCalendar(
    DateTime calendarDate,
    int selectedDay,
    ValueChanged<int> onDaySelected,
    ValueChanged<DateTime> onMonthChanged,
  ) {
    [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    String monthYearStr =
        '${DateFormat('MMMM', context.locale.toString()).format(calendarDate).toUpperCase()} ${calendarDate.year}';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  onMonthChanged(
                    DateTime(calendarDate.year, calendarDate.month - 1, 1),
                  );
                },
                child: const Icon(
                  Icons.chevron_left,
                  size: 16,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                monthYearStr,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () {
                  onMonthChanged(
                    DateTime(calendarDate.year, calendarDate.month + 1, 1),
                  );
                },
                child: const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildWeekday('weekday_sun'.tr(), Colors.red)),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_mon'.tr(),
                  const Color(0xFF0247C4),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_tue'.tr(),
                  const Color(0xFF0247C4),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_wed'.tr(),
                  const Color(0xFF0247C4),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_thu'.tr(),
                  const Color(0xFF0247C4),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_fri'.tr(),
                  const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildWeekday(
                  'weekday_sat'.tr(),
                  const Color(0xFF0247C4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDaysGrid(calendarDate, selectedDay, onDaySelected),
        ],
      ),
    );
  }

  Widget _buildWeekday(String day, Color color) {
    return Container(
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        day,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.w700,
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _buildDaysGrid(
    DateTime calendarDate,
    int selectedDay,
    ValueChanged<int> onDaySelected,
  ) {
    List<Widget> rows = [];
    int daysInMonth = DateTime(
      calendarDate.year,
      calendarDate.month + 1,
      0,
    ).day;
    int firstWeekday = DateTime(
      calendarDate.year,
      calendarDate.month,
      1,
    ).weekday;
    int startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        int index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$day',
                day == selectedDay,
                () => onDaySelected(day),
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 4));
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth) break;
      if (i < 5) rows.add(const SizedBox(height: 4));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(String day, bool isSelected, VoidCallback? onTap) {
    if (day.isEmpty) return const SizedBox();
    return AspectRatio(
      aspectRatio: 1.1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.red : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.red : Colors.grey.shade300,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            day,
            style: TextStyle(
              color: isSelected ? Color(0xFFFFFFFF) : Colors.black,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredExpenses;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopActionRow(context),
                  const SizedBox(height: 24),
                  _buildSummaryCards(),
                  const SizedBox(height: 32),
                  _buildListHeader(),
                  const SizedBox(height: 16),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (isDataEmpty || filtered.isEmpty
                            ? _buildEmptyState()
                            : _buildDataTable(filtered)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'expenses'.tr(),
                style: TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onNotificationTap,
            child: SvgPicture.asset(
              'assets/notification_icon.svg',
              width: 22,
              height: 26,
              colorFilter: const ColorFilter.mode(
                Color(0xFF000000),
                BlendMode.srcIn,
              ),
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/search icon.svg',
                  width: 20,
                  height: 20,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFBDBDBD),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _currentPage = 1;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'search_expenses_hint'.tr(),
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _searchQuery = '';
                        _currentPage = 1;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final isPremium = await PreferencesService.isPremium();
            final isGuest = AuthService().currentUser?.isAnonymous ?? false;
            if (!PremiumGate.canAddEntry(
              currentEntryCount: _expensesDocs.length,
              isPremium: isPremium,
              isGuest: isGuest,
            )) {
              await PremiumGate.shouldShowUpgradeDialog(context);
              return;
            }
            if (!mounted) return;
            _showAddExpenseModal(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            minimumSize: const Size(150, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/add_expense.svg',
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(
              Color(0xFFFFFFFF),
              BlendMode.srcIn,
            ),
          ),
          label: Text(
            'add_expenses'.tr(),
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildCard(
            title: 'this_month_expense'.tr(),
            titleColor: const Color(0xFF0247C4),
            amount: _formatCurrency(_totalExpenseSum),
            iconWidget: SvgPicture.asset(
              'assets/expense_month.svg',
              width: 44,
              height: 44,
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _buildCard(
            title: 'total_expense'.tr(),
            titleColor: Colors.red,
            amount: _formatCurrency(_totalExpenseSum),
            iconWidget: SvgPicture.asset(
              'assets/total_expense.svg',
              width: 44,
              height: 44,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required Color titleColor,
    required String amount,
    required Widget iconWidget,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          iconWidget,
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'expenses_list'.tr(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        _buildTodayDropdown(),
      ],
    );
  }

  Widget _buildTodayDropdown() {
    return CustomTimeframeDropdown(
      selectedPeriod: _selectedPeriod,
      onChanged: (value) {
        setState(() {
          _selectedPeriod = value;
          _currentPage = 1;
          final isGuest = AuthService().currentUser?.isAnonymous ?? false;
          if (isGuest) {
            _adjustDummyDatesForPeriod(value);
          }
        });
      },
    );
  }

  // ================= FILLED STATE (LIST) =================

  Widget _buildDataTable(List<Map<String, dynamic>> expenses) {
    final totalPages = (expenses.isEmpty)
        ? 1
        : (expenses.length / _itemsPerPage).ceil();
    final safeStartIndex = (_currentPage - 1) * _itemsPerPage >= expenses.length
        ? 0
        : (_currentPage - 1) * _itemsPerPage;
    final paginatedExpenses = expenses.isEmpty
        ? <Map<String, dynamic>>[]
        : expenses.sublist(
            safeStartIndex,
            (safeStartIndex + _itemsPerPage) > expenses.length
                ? expenses.length
                : (safeStartIndex + _itemsPerPage),
          );

    final double tableHeight = (MediaQuery.of(context).size.height - 409).clamp(
      495.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Table Headers
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _tableHeader('worker_name_header'.tr()),
                ),
                Expanded(flex: 3, child: _tableHeader('date_header'.tr())),
                Expanded(flex: 3, child: _tableHeader('expense_category'.tr())),
                Expanded(flex: 2, child: _tableHeader('amount_header'.tr())),
                const SizedBox(width: 48), // Spacer to match action menu width
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          // Table Rows
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: paginatedExpenses.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildDataRow(paginatedExpenses[index], index);
              },
            ),
          ),
          // Pagination
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_left,
                    color: _currentPage > 1
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_currentPage',
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_right,
                    color: _currentPage < totalPages
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
    );
  }

  Widget _buildDataRow(Map<String, dynamic> doc, int index) {
    final name = (doc['name'] ?? '').toString();
    final date = (doc['date'] ?? '').toString();
    final category = (doc['category'] ?? '').toString();
    final amount = (doc['amount'] ?? 0).toDouble();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: AssetImage(
                    index % 2 == 0
                        ? 'assets/profileimage.png'
                        : 'assets/boy.png',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              date,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              category,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF000000),
                fontFamily: 'SF Pro Display',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: AmountText(
              _formatCurrency(amount),
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF0247C4),
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          _buildActionMenu(doc),
        ],
      ),
    );
  }

  Widget _buildActionMenu(Map<String, dynamic> doc) {
    final docId = doc['id'] as String;
    return SizedBox(
      width: 48,
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.black),
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFFCBCBCB)),
        ),
        color: const Color(0xFFFBFBFC),
        elevation: 4,
        onSelected: (value) {
          if (value == 'edit') {
            _editExpense(doc);
          } else if (value == 'delete') {
            _deleteExpense(docId);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/edit_icon.svg',
                  width: 16,
                  height: 16,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFF0247C4),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'edit_expense'.tr(),
                  style: TextStyle(
                    color: Color(0xFF0247C4),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            height: 36,
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/delete_icon.svg',
                  width: 16,
                  height: 16,
                  colorFilter: const ColorFilter.mode(
                    Colors.red,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'delete'.tr(),
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= EMPTY STATE =================

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/placeholdemptystate.png',
                width: 120,
                height: 100,
                color: const Color(0xFFCBCBCB),
              ),
              const SizedBox(height: 16),
              Text(
                'add_expenses'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0247C4),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExpenseItem {
  final String name;
  final String date;
  final String category;
  final double amount;

  ExpenseItem(this.name, this.date, this.category, this.amount);
}
