import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';

import '../utils/date_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import '../widgets/notification_bell.dart';
import '../utils/snackbar_utils.dart';
import '../utils/delete_dialog.dart';
import '../utils/premium_gate.dart';
import '../services/preferences_service.dart';
import '../utils/rate_us_helper.dart';
import '../utils/guest_restriction.dart';

String _eds(dynamic value) {
  if (value == null) return '';
  final date = AppDateUtils.dateFromValue(value);
  if (date == null) return value.toString();
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

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
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _expensesDocs = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Month';
  StreamSubscription? _expensesSub;
  StreamSubscription? _profileSub;
  StreamSubscription? _payrollSub;
  final Map<String, double> _payrollAmountsByKey = {};
  late AuthService _authService;
  late FirestoreService _firestore;
  String _currencyCode = CurrencyUtils.defaultCode;
  bool _initialized = false;

  @override
  void dispose() {
    _expensesSub?.cancel();
    _profileSub?.cancel();
    _payrollSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _expensesDocs = [];
    _isLoading = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _profileSub = _firestore.userProfileStream.listen((profile) {
        if (!mounted) return;
        final currency = CurrencyUtils.normalize(profile?['currency']);
        if (currency == _currencyCode) return;
        setState(() => _currencyCode = currency);
      });
      _payrollSub = _firestore.payrollStream.listen((snapshot) {
        if (!mounted) return;
        final amounts = <String, double>{};
        for (final document in snapshot.docs) {
          final data = document.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().trim().toLowerCase();
          if (status == 'cancelled') continue;
          final payrollKey = (data['payrollKey'] ?? '').toString().trim();
          if (payrollKey.isEmpty) continue;
          final numericAmount = data['netSalaryAmount'];
          final amount = numericAmount is num
              ? numericAmount.toDouble()
              : PayrollService.extractSalary(
                  (data['netSalaryFormatted'] ?? data['netSalary'] ?? '')
                      .toString(),
                );
          if (amount.isFinite && amount > 0) {
            amounts[payrollKey] = amount;
          }
        }
        setState(() {
          _payrollAmountsByKey
            ..clear()
            ..addAll(amounts);
        });
      });
      _expensesSub = _firestore.expensesStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              final sortedList = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              sortedList.sort((a, b) {
                final aTime =
                    AppDateUtils.dateFromValue(a['createdAt']) ??
                    AppDateUtils.dateFromValue(a['date']);
                final bTime =
                    AppDateUtils.dateFromValue(b['createdAt']) ??
                    AppDateUtils.dateFromValue(b['date']);
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                return bTime.compareTo(aTime);
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
      for (final payroll in DummyData.payroll) {
        final payrollKey = (payroll['payrollKey'] ?? '').toString();
        if (payrollKey.isEmpty) continue;
        final numericAmount = payroll['netSalaryAmount'];
        final amount = numericAmount is num
            ? numericAmount.toDouble()
            : PayrollService.extractSalary(
                (payroll['netSalaryFormatted'] ?? payroll['netSalary'] ?? '')
                    .toString(),
              );
        if (amount > 0) _payrollAmountsByKey[payrollKey] = amount;
      }
      _isLoading = false;
      _adjustDummyDatesForPeriod(_selectedPeriod);
    }
  }

  double get _totalExpenseSum {
    return _expensesDocs.fold(0.0, (sum, doc) {
      return sum + _expenseAmount(doc);
    });
  }

  double get _selectedPeriodExpenseSum {
    return _expensesDocs.fold(0.0, (sum, doc) {
      final dateStr = _eds(doc['date']);
      if (_isDateWithinPeriod(dateStr, _selectedPeriod)) {
        return sum + _expenseAmount(doc);
      }
      return sum;
    });
  }

  String get _selectedPeriodExpenseTitle {
    switch (_selectedPeriod) {
      case 'Today':
        return 'today_expense'.tr();
      case 'Week':
        return 'this_week_expense'.tr();
      case '6 Month':
        return 'last_6_months_expense'.tr();
      case 'Yearly':
        return 'this_year_expense'.tr();
      default:
        return 'this_month_expense'.tr();
    }
  }

  double _expenseAmount(Map<String, dynamic> expense) {
    final isSalary =
        (expense['category'] ?? '').toString().trim().toLowerCase() == 'salary';
    final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
    if (isSalary && payrollKey.isNotEmpty) {
      return _payrollAmountsByKey[payrollKey] ?? 0.0;
    }

    final rawAmount = expense['amount'];
    if (rawAmount is num) return rawAmount.toDouble();
    return PayrollService.extractSalary((rawAmount ?? '').toString());
  }

  bool _isPayrollExpense(Map<String, dynamic> expense) {
    final category = (expense['category'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
    return category == 'salary' && payrollKey.isNotEmpty;
  }

  String _formatCurrency(double amount) {
    final symbol = '${CurrencyUtils.symbolFor(_currencyCode)} ';
    if (amount.abs() >= 1e12) {
      return '$symbol${(amount / 1e12).toStringAsFixed(1)}T';
    } else if (amount.abs() >= 1e9) {
      return '$symbol${(amount / 1e9).toStringAsFixed(1)}B';
    } else if (amount.abs() >= 1e6) {
      return '$symbol${(amount / 1e6).toStringAsFixed(1)}M';
    } else if (amount.abs() >= 1e3) {
      return '$symbol${(amount / 1e3).toStringAsFixed(1)}K';
    }
    try {
      return NumberFormat.currency(
        locale: context.locale.toString(),
        symbol: symbol,
        decimalDigits: 2,
      ).format(amount);
    } catch (_) {
      return NumberFormat.currency(
        locale: 'en_US',
        symbol: symbol,
        decimalDigits: 2,
      ).format(amount);
    }
  }

  String _formatFullCurrency(double amount) {
    final symbol = '${CurrencyUtils.symbolFor(_currencyCode)} ';
    try {
      return NumberFormat.currency(
        locale: context.locale.toString(),
        symbol: symbol,
        decimalDigits: 0,
      ).format(amount);
    } catch (_) {
      return NumberFormat.currency(
        locale: 'en_US',
        symbol: symbol,
        decimalDigits: 0,
      ).format(amount);
    }
  }

  bool _isDateWithinPeriod(String dateStr, String period) {
    return AppDateUtils.isDateWithinPeriod(dateStr, period);
  }

  void _adjustDummyDatesForPeriod(String period) {
    final dummyList = DummyData.expenses;
    if (dummyList.isEmpty) return;

    final now = DateTime.now();
    int maxDays = 7;
    if (period == 'Today')
      maxDays = 1;
    else if (period == 'Week')
      maxDays = 7;
    else if (period == 'Month')
      maxDays = 30;
    else if (period == '6 Month')
      maxDays = 180;
    else if (period == 'Yearly')
      maxDays = 365;

    for (int i = 0; i < dummyList.length; i++) {
      int daysAgo = (i * maxDays / dummyList.length).floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      final dayStr = newDate.day.toString().padLeft(2, '0');
      final monthStr = newDate.month.toString().padLeft(2, '0');
      final yearStr = newDate.year.toString();
      dummyList[i]['date'] = '$dayStr/$monthStr/$yearStr';
    }
    _expensesDocs = dummyList.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    return _expensesDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final category = (doc['category'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final dateStr = _eds(doc['date']);

      final matchesSearch = name.contains(query) || category.contains(query);
      final matchesPeriod = _isDateWithinPeriod(dateStr, _selectedPeriod);
      return matchesSearch && matchesPeriod;
    }).toList();
  }

  Future<void> _deleteExpense(Map<String, dynamic> doc) async {
    final docId = (doc['id'] ?? '').toString().trim();
    final isGuest = _authService.currentUser?.isAnonymous ?? false || PreferencesService.cachedIsGuest;
    if (docId.isEmpty) return;

    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_expense'.tr(),
      content: 'delete_expense_desc'.tr(),
    );
    if (!confirmed) return;

    try {
      if (isGuest) {
        setState(() {
          _expensesDocs.removeWhere((e) => e['id'] == docId);
        });
        DummyData.expenses.removeWhere((e) => e['id'] == docId);
        await DummyData.saveToPrefs();
      } else {
        await _firestore.deleteExpense(docId);
      }
    } catch (e) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'failed_to_delete_record'.tr(
          namedArgs: {'error': e.toString()},
        ),
        isError: true,
      );
    }
  }

  Future<void> _editExpense(Map<String, dynamic> doc) async {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final categoryController = TextEditingController(
      text: doc['category']?.toString() ?? '',
    );
    final amountController = TextEditingController(
      text: _expenseAmount(doc).toString(),
    );
    final descriptionController = TextEditingController(
      text: doc['name']?.toString() ?? doc['description']?.toString() ?? '',
    );
    final docId = (doc['id'] ?? '').toString().trim();
    final parsedDate =
        AppDateUtils.dateFromValue(doc['date']) ?? DateTime.now();
    int selectedDay = parsedDate.day;
    DateTime calendarDate = DateTime(parsedDate.year, parsedDate.month, 1);

    var isSaving = false;
    await showDialog(
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
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  final category = categoryController.text
                                      .trim();
                                  final amountText = amountController.text
                                      .trim();
                                  final description = descriptionController.text
                                      .trim();

                                  if (category.isEmpty &&
                                      amountText.isEmpty &&
                                      description.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_fill_all_fields'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (category.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_category'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final double? amt = double.tryParse(
                                    amountText,
                                  );
                                  if (amt == null ||
                                      !amt.isFinite ||
                                      amt <= 0) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_valid_amount'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  if (description.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_expense_title'
                                          .tr(),
                                      isError: true,
                                    );
                                    return;
                                  }
                                   final date = DateTime(
                                    calendarDate.year,
                                    calendarDate.month,
                                    selectedDay,
                                  );
                                  final bool wasPayrollExpense = _isPayrollExpense(doc);
                                  final String payrollKey = wasPayrollExpense
                                      ? (doc['payrollKey'] ?? '').toString().trim()
                                      : '';
                                  final updatedMap = {
                                    'date': date,
                                    'category': categoryController.text.trim(),
                                    'amount': amt,
                                    'name': descriptionController.text.trim(),
                                    'description': descriptionController.text
                                        .trim(),
                                  };
                                  try {
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
                                      });
                                      final dummyIdx = DummyData.expenses
                                          .indexWhere((e) => e['id'] == docId);
                                      if (dummyIdx != -1)
                                        DummyData.expenses[dummyIdx] = {
                                          ...updatedMap,
                                          'id': docId,
                                        };
                                      await DummyData.saveToPrefs();
                                    } else {
                                      await _firestore.updateExpense(
                                        docId,
                                        updatedMap,
                                      );
                                      if (wasPayrollExpense && payrollKey.isNotEmpty) {
                                        await _firestore.updatePayrollByPayrollKey(
                                          payrollKey,
                                          {'netSalaryAmount': amt},
                                        );
                                      }
                                    }
                                  } catch (e) {
                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    FlashySnackBar.show(
                                      context,
                                      message: 'failed_to_update_expense'.tr(
                                        namedArgs: {'error': e.toString()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  if (!mounted) return;
                                  FlashySnackBar.show(
                                    this.context,
                                    message: 'expense_updated'.tr(),
                                  );
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
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
                            hintText: 'please_enter_category'.tr(),
                            maxLength: 50,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalTextField(
                            'amount_header'.tr(),
                            amountController,
                            hintText: 'hint_amount'.tr(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            isAmount: true,
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
                                  maxLength: 150,
                                  decoration: InputDecoration(
                                    hintText: 'please_enter_expense_title'.tr(),
                                    counterText: '',
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
    categoryController.dispose();
    amountController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showAddExpenseModal(BuildContext parentContext) async {
    final categoryController = TextEditingController();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int selectedDay = DateTime.now().day;
    DateTime calendarDate = DateTime.now();

    var isSaving = false;
    await showDialog(
      context: parentContext,
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
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  final category = categoryController.text
                                      .trim();
                                  final amountText = amountController.text
                                      .trim();
                                  final description = descriptionController.text
                                      .trim();

                                  if (category.isEmpty &&
                                      amountText.isEmpty &&
                                      description.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_fill_all_fields'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (category.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_category'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final double? amt = double.tryParse(
                                    amountText,
                                  );
                                  if (amt == null ||
                                      !amt.isFinite ||
                                      amt <= 0) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_valid_amount'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  try {
                                    final policies = await _firestore.getPolicies();
                                    final expPolicyList = policies.where((p) => p['typeId'] == 'Expense Policy').toList();
                                    if (expPolicyList.isNotEmpty) {
                                      final expPolicy = expPolicyList.first;
                                      final double maxLimit = double.tryParse(expPolicy['maxExpenseLimitPerClaim']?.toString() ?? '500.0') ?? 500.0;
                                      if (amt > maxLimit) {
                                        setModalState(() => isSaving = false);
                                        FlashySnackBar.show(
                                          context,
                                          message: 'expense_claim_exceeds_limit'.tr(
                                            namedArgs: {
                                              'maxLimit': formatMoney(
                                                maxLimit,
                                                CurrencyUtils.symbolFor(_currencyCode),
                                              ),
                                            },
                                          ),
                                          isError: true,
                                        );
                                        return;
                                      }
                                    }
                                  } catch (_) {}
                                  if (description.isEmpty) {
                                    setModalState(() => isSaving = false);
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_enter_expense_title'
                                          .tr(),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  final date = DateTime(
                                    calendarDate.year,
                                    calendarDate.month,
                                    selectedDay,
                                  );
                                  final isGuest =
                                      _authService.currentUser?.isAnonymous ??
                                      false;
                                  final expenseMap = {
                                    'date': date,
                                    'category': categoryController.text.trim(),
                                    'amount': amt,
                                    'name': descriptionController.text.trim(),
                                    'description': descriptionController.text
                                        .trim(),
                                  };
                                  try {
                                    if (isGuest) {
                                      final newId =
                                          'dummy_e${DateTime.now().millisecondsSinceEpoch}';
                                      setState(() {
                                        _expensesDocs.insert(0, {
                                          ...expenseMap,
                                          'id': newId,
                                        });
                                      });
                                      DummyData.expenses.insert(0, {
                                        ...expenseMap,
                                        'id': newId,
                                      });
                                      await DummyData.saveToPrefs();
                                    } else {
                                      await _firestore.addExpense(expenseMap);
                                    }
                                  } catch (e) {
                                    setModalState(() => isSaving = false);
                                    if (!context.mounted) return;
                                    FlashySnackBar.show(
                                      context,
                                      message: 'failed_to_add_expense'.tr(
                                        namedArgs: {'error': e.toString()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }
                                  Navigator.of(context).pop();
                                  FlashySnackBar.show(
                                    parentContext,
                                    message: 'successfully_added_expense'.tr(
                                      namedArgs: {
                                        'name': categoryController.text,
                                      },
                                    ),
                                  );
                                  if (parentContext.mounted) {
                                    tryShowFirstMilestoneRateUs('expense');
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
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
                            hintText: 'please_enter_category'.tr(),
                            maxLength: 50,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalTextField(
                            'amount_header'.tr(),
                            amountController,
                            hintText: 'hint_amount'.tr(),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            isAmount: true,
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
                                  maxLength: 150,
                                  decoration: InputDecoration(
                                    hintText: 'please_enter_expense_title'.tr(),
                                    counterText: '',
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
    categoryController.dispose();
    amountController.dispose();
    descriptionController.dispose();
  }

  Widget _buildModalTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    String hintText = '',
    int? maxLength,
    bool isAmount = false,
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
            maxLength: maxLength,
            inputFormatters: isAmount
                ? [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d{0,18}(?:\.\d{0,2})?$'),
                    ),
                    LengthLimitingTextInputFormatter(21),
                  ]
                : maxLength != null
                ? [LengthLimitingTextInputFormatter(maxLength)]
                : const <TextInputFormatter>[],
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Colors.grey),
              border: InputBorder.none,
              counterText: '',
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
          rowChildren.add(
            Expanded(child: _buildDayCell('', false, null, null)),
          );
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          final cellDate = DateTime(calendarDate.year, calendarDate.month, day);
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$day',
                day == selectedDay,
                () => onDaySelected(day),
                cellDate,
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(
            Expanded(child: _buildDayCell('', false, null, null)),
          );
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 4));
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth) break;
      if (i < 5) rows.add(const SizedBox(height: 4));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(
    String day,
    bool isSelected,
    VoidCallback? onTap,
    DateTime? date,
  ) {
    if (day.isEmpty) return const SizedBox();
    final selectedBg = const Color(0xFF0247C4);
    return AspectRatio(
      aspectRatio: 1.1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? selectedBg : Colors.transparent,
            border: Border.all(
              color: isSelected ? selectedBg : Colors.grey.shade300,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            day,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 13,
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
                      : (filtered.isEmpty
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
          NotificationBell(onTap: widget.onNotificationTap),
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
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
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
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
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
        const SizedBox(width: 10),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () async {
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (isGuest) {
                if (!mounted) return;
                showGuestRestrictionDialog(context);
                return;
              }
              final isPremium = await PreferencesService.isPremium();
              if (!mounted) return;
              if (!PremiumGate.canAddEntry(
                currentEntryCount: _expensesDocs.length,
                isPremium: isPremium,
                isGuest: isGuest,
              )) {
                if (!mounted) return;
                final upgraded = await PremiumGate.shouldShowUpgradeDialog(
                  context,
                );
                if (upgraded == true && mounted) {
                  _showAddExpenseModal(context);
                }
                return;
              }
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
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildCard(
            title: _selectedPeriodExpenseTitle,
            titleColor: const Color(0xFF0247C4),
            amount: _formatCurrency(_selectedPeriodExpenseSum),
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
                    overflow: TextOverflow.ellipsis,
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
          final isGuest = _authService.currentUser?.isAnonymous ?? false;
          if (isGuest) {
            _adjustDummyDatesForPeriod(value);
          }
        });
      },
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> expenses) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('expense_title'.tr()),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 40.0, right: 16.0),
                    child: _tableHeader('expense_category'.tr()),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader(
                      'date_header'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _tableHeader(
                    'amount_header'.tr(),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),

          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: expenses.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildDataRow(expenses[index], index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String title, {TextAlign? textAlign}) {
    return Text(
      title,
      textAlign: textAlign,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDataRow(Map<String, dynamic> doc, int index) {
    final name = (doc['name'] ?? '').toString();
    final date = _eds(doc['date']);
    final category = (doc['category'] ?? '').toString();
    final amount = _expenseAmount(doc);

    final isGuest = _authService.currentUser?.isAnonymous ?? false;

    return GestureDetector(
      onTap: () {
        if (isGuest) {
          showGuestRestrictionDialog(context);
          return;
        }

        _editExpense(doc);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(left: 40.0, right: 16.0),
                child: Text(
                  category,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  date,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF000000),
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _isPayrollExpense(doc)
                    ? _formatFullCurrency(amount)
                    : _formatCurrency(amount),
                textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildActionMenu(Map<String, dynamic> doc) {
    return SizedBox(
      width: 48,
      child: PopupMenuButton<String>(
        tooltip: '',
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
            final isGuest = _authService.currentUser?.isAnonymous ?? false;
            if (isGuest) {
              showGuestRestrictionDialog(context);
              return;
            }
            _editExpense(doc);
          } else if (value == 'delete') {
            final isGuest = _authService.currentUser?.isAnonymous ?? false;
            if (isGuest) {
              showGuestRestrictionDialog(context);
              return;
            }
            _deleteExpense(doc);
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

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/placeholder_workers.svg',
                width: 120,
                height: 100,
                colorFilter: const ColorFilter.mode(
                  Color(0xFFCBCBCB),
                  BlendMode.srcIn,
                ),
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
