import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../services/preferences_service.dart';

import '../utils/date_time_utils.dart';
import '../utils/currency_utils.dart';
import '../utils/localization_helper.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import '../widgets/notification_bell.dart';
import '../utils/ui_utils.dart';
import '../utils/dialog_utils.dart';

import '../utils/rate_us_helper.dart';
import '../utils/guest_restriction.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
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

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

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

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (!_isGuest) {
      _setupRealTimeSubscriptions();
    } else {
      _loadDummyData();
    }
  }

  void _setupRealTimeSubscriptions() {
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
        if (!PayrollService.isPayrollRecordPaid(data)) continue;
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
            _expensesDocs = _sortExpenses(snapshot.docs);
            _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  void _loadDummyData() {
    _expensesDocs = DummyData.expenses
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final activePayrollRecords = PayrollService.paidPayrollRecordsForActiveWorkers(
      DummyData.workers,
      DummyData.payroll,
    );

    for (final record in activePayrollRecords) {
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (payrollKey.isEmpty) continue;
      final netSalary = (record['netSalary'] is num)
          ? (record['netSalary'] as num).toDouble()
          : 0.0;
      if (netSalary > 0) _payrollAmountsByKey[payrollKey] = netSalary;
    }

    _isLoading = false;
    _adjustDummyDatesForPeriod(_selectedPeriod);
  }

  List<Map<String, dynamic>> _sortExpenses(List docs) {
    final sortedList = docs
        .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
        .toList();
    sortedList.sort((a, b) {
      final aTime = AppDateUtils.dateFromValue(a['createdAt']) ??
          AppDateUtils.dateFromValue(a['date']);
      final bTime = AppDateUtils.dateFromValue(b['createdAt']) ??
          AppDateUtils.dateFromValue(b['date']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return sortedList;
  }

  // ==================== HELPERS ====================

  double get _totalExpenseSum =>
      _expensesDocs.fold(0.0, (sum, doc) => sum + _expenseAmount(doc));

  double get _selectedPeriodExpenseSum => _expensesDocs.fold(0.0, (sum, doc) {
        if (AppDateUtils.isTimestampWithinPeriod(doc['date'], _selectedPeriod)) {
          return sum + _expenseAmount(doc);
        }
        return sum;
      });

  String get _selectedPeriodExpenseTitle {
    switch (_selectedPeriod) {
      case 'Today':
        return 'today_expense'.tr();
      case 'Week':
      case 'This Week':
        return 'this_week_expense'.tr();
      case '6 Month':
      case 'Last 6 Months':
        return 'last_6_months_expense'.tr();
      case 'Yearly':
      case 'This Year':
        return 'this_year_expense'.tr();
      case 'All Time':
        return 'all_time_expense'.tr();
      default:
        return 'this_month_expense'.tr();
    }
  }

  double _expenseAmount(Map<String, dynamic> expense) {
    final isSalary = (expense['category'] ?? '').toString().trim().toLowerCase() == 'salary';
    final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
    if (isSalary && payrollKey.isNotEmpty) {
      return _payrollAmountsByKey[payrollKey] ?? 0.0;
    }
    final rawAmount = expense['amount'];
    if (rawAmount is num) return rawAmount.toDouble();
    return PayrollService.extractSalary((rawAmount ?? '').toString());
  }

  bool _isPayrollExpense(Map<String, dynamic> expense) {
    final payrollKey = (expense['payrollKey'] ?? '').toString().trim();
    final sourceType = (expense['sourceType'] ?? '').toString().trim().toLowerCase();
    return payrollKey.isNotEmpty || sourceType == 'payroll';
  }

  String _expenseDisplayName(Map<String, dynamic> expense) {
    final name = (expense['name'] ?? '').toString().trim();
    final category = (expense['category'] ?? '').toString().trim().toLowerCase();
    if (category != 'salary') return name;
    return name
        .replaceFirst(RegExp(r'^salary\s*[-–—:]\s*', caseSensitive: false), '')
        .trim();
  }

  String _formatCurrency(double amount) {
    final codeSymbol = CurrencyUtils.symbolFor(_currencyCode);
    if (amount.abs() >= 1e3) {
      return CurrencyUtils.formatCompactLocale(
        amount,
        context.locale.toString(),
        symbol: codeSymbol,
      );
    }
    final symbol = '$codeSymbol ';
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

  String _eds(dynamic value) =>
      AppDateUtils.fromValueLocalized(value, locale: context.locale.toString());

  void _adjustDummyDatesForPeriod(String period) {
    final dummyList = DummyData.expenses;
    if (dummyList.isEmpty) return;

    final now = DateTime.now();
    int maxDays = 365;
    if (period == 'Today') {
      maxDays = 0;
    } else if (period == 'Week' || period == 'This Week') {
      maxDays = 7;
    } else if (period == 'Month' || period == 'This Month') {
      maxDays = 30;
    } else if (period == '6 Month' || period == 'Last 6 Months') {
      maxDays = 180;
    }

    for (int i = 0; i < dummyList.length; i++) {
      int daysAgo = (i * (maxDays + 1) / dummyList.length).floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      dummyList[i]['date'] =
          '${newDate.day.toString().padLeft(2, '0')}/${newDate.month.toString().padLeft(2, '0')}/${newDate.year}';
    }
    _expensesDocs = dummyList.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> get _filteredExpenses {
    return _expensesDocs.where((doc) {
      if (_isPayrollExpense(doc)) {
        final payrollKey = (doc['payrollKey'] ?? '').toString().trim();
        if (!_payrollAmountsByKey.containsKey(payrollKey)) return false;
      }
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final category = (doc['category'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || category.contains(query);
      final matchesPeriod =
          AppDateUtils.isTimestampWithinPeriod(doc['date'], _selectedPeriod);
      return matchesSearch && matchesPeriod;
    }).toList();
  }

  // ==================== GUEST OPERATIONS ====================

  void _addExpenseToGuest(Map<String, dynamic> expenseMap) {
    final newId = 'dummy_e${DateTime.now().millisecondsSinceEpoch}';
    setState(() => _expensesDocs.insert(0, {...expenseMap, 'id': newId}));
    DummyData.expenses.insert(0, {...expenseMap, 'id': newId});
    DummyData.saveToPrefs();
  }

  void _updateExpenseInGuest(String docId, Map<String, dynamic> updatedMap,
      {String? payrollKey, double? amt}) {
    setState(() {
      final idx = _expensesDocs.indexWhere((e) => e['id'] == docId);
      if (idx != -1) {
        _expensesDocs[idx] = {..._expensesDocs[idx], ...updatedMap, 'id': docId};
      }
      if (payrollKey != null && amt != null) {
        _payrollAmountsByKey[payrollKey] = amt;
      }
    });

    final dummyIdx = DummyData.expenses.indexWhere((e) => e['id'] == docId);
    if (dummyIdx != -1) {
      DummyData.expenses[dummyIdx] = {...DummyData.expenses[dummyIdx], ...updatedMap, 'id': docId};
    }

    if (payrollKey != null && amt != null) {
      Map<String, dynamic> updateRecord(Map<String, dynamic> record) {
        final baseSalary = PayrollService.extractSalary(
          record['salary'] ?? record['salaryAmount'],
        );

        // Net Pay = Base Salary + Overtime - Absence Deduction - Leave Deduction
        final double overtime;
        final double absenceDeduction;
        if (amt >= baseSalary) {
          overtime = amt - baseSalary;
          absenceDeduction = 0.0;
        } else {
          overtime = 0.0;
          absenceDeduction = baseSalary - amt;
        }

        final formatted = PayrollService.formatAmountInCurrency(
          amt,
          _currencyCode,
        );
        return {
          ...record,
          'netSalaryAmount': amt,
          'netSalary': formatted,
          'netSalaryFormatted': formatted,
          'salaryAfterDeduction': formatted,
          'amount': amt,
          'overtimeAmount': overtime,
          'absentDeduction': absenceDeduction,
          'leaveDeduction': 0.0,
          'status': 'Paid',
          'isPaid': true,
          'paid': true,
          'paymentStatus': 'paid',
          'updatedAt': DateTime.now(),
          'lastModified': DateTime.now(),
        };
      }

      final payrollIndex = DummyData.payroll.indexWhere(
        (record) =>
            (record['payrollKey'] ?? '').toString().trim() == payrollKey,
      );
      if (payrollIndex != -1) {
        DummyData.payroll[payrollIndex] = updateRecord(
          DummyData.payroll[payrollIndex],
        );
      }

      PreferencesService.getGuestPayroll().then((guestPayroll) {
        if (guestPayroll != null) {
          final idx = guestPayroll.indexWhere(
            (p) => (p['payrollKey'] ?? '').toString().trim() == payrollKey,
          );
          if (idx != -1) {
            guestPayroll[idx] = updateRecord(guestPayroll[idx]);
            PreferencesService.setGuestPayroll(guestPayroll);
          }
        }
      });
    }
    DummyData.saveToPrefs();
  }

  void _deleteExpenseFromGuest(String docId, {String? payrollKey}) {
    setState(() {
      _expensesDocs.removeWhere((e) => e['id'] == docId);
      if (payrollKey != null) _payrollAmountsByKey.remove(payrollKey);
    });
    DummyData.expenses.removeWhere((e) => e['id'] == docId);
    if (payrollKey != null) {
      final normalizedKey = payrollKey.trim();
      DummyData.payroll.removeWhere(
        (record) =>
            (record['payrollKey'] ?? '').toString().trim() == normalizedKey,
      );
      PreferencesService.getGuestPayroll().then((guestPayroll) {
        if (guestPayroll != null) {
          guestPayroll.removeWhere(
            (p) => (p['payrollKey'] ?? '').toString().trim() == normalizedKey,
          );
          PreferencesService.setGuestPayroll(guestPayroll);
        }
      });
    }
    DummyData.saveToPrefs();
  }

  // ==================== CRUD OPERATIONS ====================

  Future<void> _deleteExpense(Map<String, dynamic> doc) async {
    final docId = (doc['id'] ?? '').toString().trim();
    if (docId.isEmpty) return;

    final confirmed = await DeleteDialog.show(
      context: context,
      title: 'delete_expense'.tr(),
      content: 'delete_expense_desc'.tr(),
    );
    if (!confirmed) return;

    try {
      final payrollKey = (doc['payrollKey'] ?? '').toString().trim();
      final isPayroll = _isPayrollExpense(doc);

      if (_isGuest) {
        _deleteExpenseFromGuest(docId, payrollKey: isPayroll ? payrollKey : null);
      } else {
        if (isPayroll) {
          await _firestore.deletePayrollLinkedExpense(
            expenseId: docId,
            payrollKey: payrollKey,
          );
        } else {
          await _firestore.deleteExpense(docId);
        }
      }
      if (mounted) {
        FlashySnackBar.show(context, message: 'expense_deleted'.tr());
      }
    } catch (e) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'failed_to_delete_record'.tr(namedArgs: {'error': e.toString()}),
        isError: true,
      );
    }
  }

  // ==================== EXPENSE DIALOG (UNIFIED) ====================

  Future<void> _showExpenseDialog({
    required String title,
    required String buttonText,
    required Map<String, dynamic>? initialData,
    required Future<void> Function(Map<String, dynamic>) onSave,
  }) async {
    final isEdit = initialData != null;
    final categoryController = TextEditingController(
      text: isEdit ? initialData['category']?.toString() ?? '' : '',
    );
    final amountController = TextEditingController(
      text: isEdit
          ? NumberFormat('#,##0.##').format(_expenseAmount(initialData))
          : '',
    );
    final descriptionController = TextEditingController(
      text: isEdit
          ? initialData['name']?.toString() ??
              initialData['description']?.toString() ??
              ''
          : '',
    );

    final parsedDate = isEdit
        ? AppDateUtils.dateFromValue(initialData['date']) ?? DateTime.now()
        : DateTime.now();
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              backgroundColor: Colors.white,
              elevation: 10,
              child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDialogHeader(
                      context,
                      title: title,
                      buttonText: buttonText,
                      isSaving: isSaving,
                      onSave: () async {
                        setModalState(() => isSaving = true);
                        final result = await _validateAndPrepareExpense(
                          categoryController: categoryController,
                          amountController: amountController,
                          descriptionController: descriptionController,
                          calendarDate: calendarDate,
                          selectedDay: selectedDay,
                          initialData: initialData,
                        );
                        if (result == null) {
                          setModalState(() => isSaving = false);
                          return;
                        }
                        await onSave(result);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildDialogFields(
                      categoryController: categoryController,
                      amountController: amountController,
                      descriptionController: descriptionController,
                      calendarDate: calendarDate,
                      selectedDay: selectedDay,
                      onDaySelected: (day) => setModalState(() => selectedDay = day),
                      onMonthChanged: (newDate) {
                        setModalState(() {
                          calendarDate = newDate;
                          final daysInNewMonth =
                              DateTime(newDate.year, newDate.month + 1, 0).day;
                          if (selectedDay > daysInNewMonth) {
                            selectedDay = daysInNewMonth;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      categoryController.dispose();
      amountController.dispose();
      descriptionController.dispose();
    });
  }

  Widget _buildDialogHeader(
    BuildContext context, {
    required String title,
    required String buttonText,
    required bool isSaving,
    required VoidCallback onSave,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.close, color: Colors.black, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: const Size(0, 32),
          ),
          onPressed: isSaving ? null : onSave,
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  buttonText,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDialogFields({
    required TextEditingController categoryController,
    required TextEditingController amountController,
    required TextEditingController descriptionController,
    required DateTime calendarDate,
    required int selectedDay,
    required ValueChanged<int> onDaySelected,
    required ValueChanged<DateTime> onMonthChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                isAmount: true,
                prefixText: '${CurrencyUtils.symbolFor(_currencyCode)} ',
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 215,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: TextField(
                      controller: descriptionController,
                      maxLines: null,
                      maxLength: 150,
                      decoration: InputDecoration(
                        hintText: 'please_enter_expense_title'.tr(),
                        counterText: '',
                        contentPadding: const EdgeInsets.only(top: 1),
                        hintStyle: const TextStyle(color: Colors.grey),
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
                onDaySelected,
                onMonthChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _validateAndPrepareExpense({
    required TextEditingController categoryController,
    required TextEditingController amountController,
    required TextEditingController descriptionController,
    required DateTime calendarDate,
    required int selectedDay,
    Map<String, dynamic>? initialData,
  }) async {
    final category = categoryController.text.trim();
    final amountText = amountController.text.trim();
    final description = descriptionController.text.trim();

    if (category.isEmpty || amountText.isEmpty || description.isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return null;
    }

    final double? amt = double.tryParse(amountText.replaceAll(",", ""));
    if (amt == null || !amt.isFinite || amt <= 0) {
      FlashySnackBar.show(
        context,
        message: 'please_enter_valid_amount'.tr(),
        isError: true,
      );
      return null;
    }

    if (amt > 999999999) {
      FlashySnackBar.show(
        context,
        message: 'amount_cannot_exceed_max'.tr(),
        isError: true,
      );
      return null;
    }

    // Policy check for new expenses only
    if (initialData == null) {
      try {
        final policies = await _firestore.getPolicies();
        final expPolicyList = policies
            .where((p) => p['typeId'] == 'Expense Policy')
            .toList();
        if (expPolicyList.isNotEmpty) {
          final expPolicy = expPolicyList.first;
          final double maxLimit = double.tryParse(
                expPolicy['maxExpenseLimitPerClaim']?.toString() ?? '500.0',
              ) ??
              500.0;
          if (!mounted) return null;
          if (amt > maxLimit) {
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
            return null;
          }
        }
      } catch (_) {}
    }

    final date = DateTime(calendarDate.year, calendarDate.month, selectedDay);

    return {
      'date': date,
      'category': category,
      'amount': amt,
      'name': description,
      'description': description,
    };
  }

  // ==================== ADD EXPENSE ====================

  Future<void> _showAddExpenseModal(BuildContext parentContext) async {
    if (_isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    await _showExpenseDialog(
      title: 'add_expense'.tr(),
      buttonText: 'save'.tr(),
      initialData: null,
      onSave: (expenseMap) async {
        try {
          if (_isGuest) {
            _addExpenseToGuest(expenseMap);
          } else {
            await _firestore.addExpense(expenseMap);
          }
          if (!context.mounted) return;
          FlashySnackBar.show(
            parentContext,
            message: 'successfully_added_expense'.tr(
              namedArgs: {'name': expenseMap['category']},
            ),
          );
          tryShowFirstMilestoneRateUs('expense');
        } catch (e) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'failed_to_add_expense'.tr(namedArgs: {'error': e.toString()}),
              isError: true,
            );
          }
          rethrow;
        }
      },
    );
  }

  // ==================== EDIT EXPENSE ====================

  Future<void> _editExpense(Map<String, dynamic> doc) async {
    if (_isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    await _showExpenseDialog(
      title: 'edit_expense'.tr(),
      buttonText: 'save'.tr(),
      initialData: doc,
      onSave: (updatedMap) async {
        final docId = (doc['id'] ?? '').toString().trim();
        final wasPayroll = _isPayrollExpense(doc);
        final payrollKey = wasPayroll ? (doc['payrollKey'] ?? '').toString().trim() : '';
        final amt = updatedMap['amount'] as double;

        try {
          if (_isGuest) {
            _updateExpenseInGuest(docId, updatedMap,
                payrollKey: wasPayroll ? payrollKey : null, amt: wasPayroll ? amt : null);
          } else {
            if (wasPayroll && payrollKey.isNotEmpty) {
              await _firestore.updatePayrollLinkedExpense(
                expenseId: docId,
                payrollKey: payrollKey,
                expenseData: updatedMap,
                netAmount: amt,
                currency: _currencyCode,
              );
            } else {
              await _firestore.updateExpense(docId, updatedMap);
            }
          }
          if (mounted) {
            FlashySnackBar.show(context, message: 'expense_updated'.tr());
          }
        } on ArgumentError catch (e) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: e.message?.toString() ?? 'failed_to_update_expense'.tr(),
              isError: true,
            );
          }
        } catch (e) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: 'failed_to_update_expense'.tr(namedArgs: {'error': e.toString()}),
              isError: true,
            );
          }
        }
      },
    );
  }

  // ==================== WIDGET BUILDERS ====================

  Widget _buildModalTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    String hintText = '',
    int? maxLength,
    bool isAmount = false,
    String? prefixText,
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
                    FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
                    LengthLimitingTextInputFormatter(18),
                    _ThousandsSeparatorInputFormatter(),
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
              prefixText: prefixText,
              prefixStyle: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
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
    final monthYearStr =
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
                onTap: () => onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month - 1, 1),
                ),
                child: const Icon(Icons.chevron_left, size: 16, color: Colors.black),
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
                onTap: () => onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month + 1, 1),
                ),
                child: const Icon(Icons.chevron_right, size: 16, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildWeekday('weekday_sun'.tr(), Colors.red)),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_mon'.tr(), const Color(0xFF0247C4))),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_tue'.tr(), const Color(0xFF0247C4))),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_wed'.tr(), const Color(0xFF0247C4))),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_thu'.tr(), const Color(0xFF0247C4))),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_fri'.tr(), const Color(0xFF4CAF50))),
              const SizedBox(width: 6),
              Expanded(child: _buildWeekday('weekday_sat'.tr(), const Color(0xFF0247C4))),
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
    final rows = <Widget>[];
    final daysInMonth = DateTime(calendarDate.year, calendarDate.month + 1, 0).day;
    final firstWeekday = DateTime(calendarDate.year, calendarDate.month, 1).weekday;
    final startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    int currentDay = 1;

    for (int i = 0; i < 6; i++) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < 7; j++) {
        final index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null, null)));
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$day',
                day == selectedDay,
                () => onDaySelected(day),
                DateTime(calendarDate.year, calendarDate.month, day),
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null, null)));
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

  // ==================== MAIN BUILD ====================

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
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : _buildDataTable(filtered),
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
                style: const TextStyle(
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
              color: const Color(0xFFFFFFFF),
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
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'search_expenses_hint'.tr(),
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
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
                      setState(() => _searchQuery = '');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
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
            onPressed: () => _showAddExpenseModal(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4),
              minimumSize: const Size(150, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            icon: SvgPicture.asset(
              'assets/add_expense.svg',
              width: 18,
              height: 18,
              colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn),
            ),
            label: Text(
              'add_expenses'.tr(),
              style: const TextStyle(
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
            iconWidget: SvgPicture.asset('assets/expense_month.svg', width: 44, height: 44),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _buildCard(
            title: 'total_expense'.tr(),
            titleColor: Colors.red,
            amount: _formatCurrency(_totalExpenseSum),
            iconWidget: SvgPicture.asset('assets/total_expense.svg', width: 44, height: 44),
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
        color: const Color(0xFFFFFFFF),
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
          style: const TextStyle(
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
      options: const [
        'Today',
        'This Week',
        'This Month',
        'Last 6 Months',
        'This Year',
        'All Time',
      ],
      onChanged: (value) {
        setState(() {
          _selectedPeriod = value;
          if (_isGuest) _adjustDummyDatesForPeriod(value);
        });
      },
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> expenses) {
    final tableHeight = (MediaQuery.of(context).size.height - 409).clamp(495.0, 1200.0);

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: _tableHeader('expense_title'.tr()),
                )),
                Expanded(flex: 3, child: Padding(
                  padding: const EdgeInsets.only(left: 40.0, right: 16.0),
                  child: _tableHeader('expense_category'.tr()),
                )),
                Expanded(flex: 3, child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: _tableHeader('date_header'.tr(), textAlign: TextAlign.center),
                )),
                Expanded(flex: 2, child: _tableHeader('amount_header'.tr(), textAlign: TextAlign.center)),
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
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _buildDataRow(expenses[index], index),
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
    final name = _expenseDisplayName(doc);
    final date = _eds(doc['date']);
    final category = LocalizationHelper.localizeExpenseCategory(
      (doc['category'] ?? '').toString(),
    );
    final amount = _expenseAmount(doc);

    return GestureDetector(
      onTap: () => _editExpense(doc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FA),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Padding(
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
            )),
            Expanded(flex: 3, child: Padding(
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
            )),
            Expanded(flex: 3, child: Padding(
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
            )),
            Expanded(flex: 2, child: Text(
              _isPayrollExpense(doc) ? _formatFullCurrency(amount) : _formatCurrency(amount),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF0247C4),
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            )),
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
            _editExpense(doc);
          } else if (value == 'delete') {
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
                  colorFilter: const ColorFilter.mode(Color(0xFF0247C4), BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  'edit_expense'.tr(),
                  style: const TextStyle(
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
                  colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  'delete'.tr(),
                  style: const TextStyle(
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
    final containerHeight = (MediaQuery.of(context).size.height - 409).clamp(495.0, 1200.0);
    return Container(
      width: double.infinity,
      height: containerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(Color(0xFFCBCBCB), BlendMode.srcIn),
          ),
          const SizedBox(height: 16),
          Text(
            'add_expenses'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0247C4),
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    String cleanText = newValue.text.replaceAll(',', '');
    final parts = cleanText.split('.');
    if (parts.length > 2) return oldValue;
    if (parts.length == 2 && parts[1].length > 2) return oldValue;

    final rawInteger = parts[0];
    if (rawInteger.length > 12) return oldValue;

    String formattedInteger = '';
    if (rawInteger.isNotEmpty) {
      final parsed = int.tryParse(rawInteger);
      if (parsed == null) return oldValue;
      formattedInteger = NumberFormat('#,##0', 'en_US').format(parsed);
    }

    String formatted = formattedInteger;
    if (parts.length > 1) {
      formatted += '.${parts[1]}';
    }

    int charsFromEnd = newValue.text.length - newValue.selection.end;
    int selectionIndex = (formatted.length - charsFromEnd).clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}