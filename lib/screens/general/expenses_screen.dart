import 'dart:async';
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';
import '../../utils/calendar_widgets.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../providers.dart';
import '../../services/auth_service.dart';
import '../../services/dummy_data.dart';
import '../../services/firestore_service.dart';
import '../../services/payroll_service.dart';
import '../../services/preferences_service.dart';
import '../../utils/utils.dart';
import '../../widgets/clickable_gesture_detector.dart';
import '../../widgets/custom_timeframe_dropdown.dart';
import '../../widgets/notification_bell.dart';

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

  late final AuthService _authService;
  late final FirestoreService _firestore;

  String _currencyCode = CurrencyUtils.defaultCode;
  bool _initialized = false;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

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

    if (_isGuest) {
      _loadDummyData();
    } else {
      _setupRealTimeSubscriptions();
    }
  }

  @override
  void dispose() {
    _expensesSub?.cancel();
    _profileSub?.cancel();
    _payrollSub?.cancel();
    _searchController.dispose();
    super.dispose();
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
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (!PayrollService.isPayrollRecordPaid(data)) continue;

        final payrollKey = (data['payrollKey'] ?? '').toString().trim();
        if (payrollKey.isEmpty) continue;

        final numericAmount = data['netSalaryAmount'];
        final amount = numericAmount is num
            ? numericAmount.toDouble()
            : PayrollService.extractSalary(
                (data['netSalaryFormatted'] ?? data['netSalary'] ?? '').toString(),
              );

        if (amount.isFinite && amount > 0) amounts[payrollKey] = amount;
      }

      setState(() {
        _payrollAmountsByKey
          ..clear()
          ..addAll(amounts);
      });
    });

    _expensesSub = _firestore.expensesStream.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _expensesDocs = _sortExpenses(snapshot.docs);
          _isLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  void _loadDummyData() {
    _expensesDocs = DummyData.expenses.map((e) => Map<String, dynamic>.from(e)).toList();

    final activePayroll = PayrollService.paidPayrollRecordsForActiveWorkers(
      DummyData.workers,
      DummyData.payroll,
    );

    for (final record in activePayroll) {
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (payrollKey.isEmpty) continue;
      final netSalary = record['netSalary'] is num ? (record['netSalary'] as num).toDouble() : 0.0;
      if (netSalary > 0) _payrollAmountsByKey[payrollKey] = netSalary;
    }

    _isLoading = false;
    _adjustDummyDatesForPeriod(_selectedPeriod);
  }

  List<Map<String, dynamic>> _sortExpenses(List docs) {
    final list = docs
        .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
        .toList()
      ..sort((a, b) {
        final aTime = AppDateUtils.dateFromValue(a['createdAt']) ?? AppDateUtils.dateFromValue(a['date']);
        final bTime = AppDateUtils.dateFromValue(b['createdAt']) ?? AppDateUtils.dateFromValue(b['date']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    return list;
  }

  void _adjustDummyDatesForPeriod(String period) {
    final dummyList = DummyData.expenses;
    if (dummyList.isEmpty) return;

    final now = DateTime.now();
    final maxDays = switch (period) {
      'Today' => 0,
      'Week' || 'This Week' => 7,
      'Month' || 'This Month' => 30,
      '6 Month' || 'Last 6 Months' => 180,
      _ => 365,
    };

    for (int i = 0; i < dummyList.length; i++) {
      final daysAgo = (i * (maxDays + 1) / dummyList.length).floor();
      final newDate = now.subtract(Duration(days: daysAgo));
      dummyList[i]['date'] =
          '${newDate.day.toString().padLeft(2, '0')}/${newDate.month.toString().padLeft(2, '0')}/${newDate.year}';
    }

    _expensesDocs = dummyList.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  double get _totalExpenseSum => _expensesDocs.fold(0.0, (sum, doc) => sum + _expenseAmount(doc));

  double get _selectedPeriodExpenseSum => _expensesDocs.fold(0.0, (sum, doc) {
        if (AppDateUtils.isTimestampWithinPeriod(doc['date'], _selectedPeriod)) {
          return sum + _expenseAmount(doc);
        }
        return sum;
      });

  String get _selectedPeriodExpenseTitle => switch (_selectedPeriod) {
        'Today' => 'today_expense'.tr(),
        'Week' || 'This Week' => 'this_week_expense'.tr(),
        '6 Month' || 'Last 6 Months' => 'last_6_months_expense'.tr(),
        'Yearly' || 'This Year' => 'this_year_expense'.tr(),
        'All Time' => 'all_time_expense'.tr(),
        _ => 'this_month_expense'.tr(),
      };

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
    return name.replaceFirst(RegExp(r'^salary\s*[-–—:]\s*', caseSensitive: false), '').trim();
  }

  String _formatCurrency(double amount) {
    final symbol = '${CurrencyUtils.symbolFor(_currencyCode)} ';
    if (amount.abs() >= 1e3) {
      return CurrencyUtils.formatCompactLocale(amount, context.locale.toString(), symbol: symbol.trim());
    }
    try {
      return NumberFormat.currency(locale: context.locale.toString(), symbol: symbol, decimalDigits: 2).format(amount);
    } catch (_) {
      return NumberFormat.currency(locale: 'en_US', symbol: symbol, decimalDigits: 2).format(amount);
    }
  }

  String _formatFullCurrency(double amount) {
    final symbol = '${CurrencyUtils.symbolFor(_currencyCode)} ';
    try {
      return NumberFormat.currency(locale: context.locale.toString(), symbol: symbol, decimalDigits: 0).format(amount);
    } catch (_) {
      return NumberFormat.currency(locale: 'en_US', symbol: symbol, decimalDigits: 0).format(amount);
    }
  }

  String _localizedExpenseDate(dynamic value) => AppDateUtils.fromValueLocalized(value, locale: context.locale.toString());

  List<Map<String, dynamic>> get _filteredExpenses {
    return _expensesDocs.where((doc) {
      if (_isPayrollExpense(doc)) {
        final payrollKey = (doc['payrollKey'] ?? '').toString().trim();
        if (!_payrollAmountsByKey.containsKey(payrollKey)) return false;
      }

      final name = (doc['name'] ?? '').toString().toLowerCase();
      final category = (doc['category'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();

      return (name.contains(query) || category.contains(query)) &&
          AppDateUtils.isTimestampWithinPeriod(doc['date'], _selectedPeriod);
    }).toList();
  }

  void _addExpenseToGuest(Map<String, dynamic> expenseMap) {
    final newId = 'dummy_e${DateTime.now().millisecondsSinceEpoch}';
    final entry = {...expenseMap, 'id': newId};
    setState(() => _expensesDocs.insert(0, entry));
    DummyData.expenses.insert(0, entry);
    DummyData.saveToPrefs();
  }

  void _updateExpenseInGuest(String docId, Map<String, dynamic> updatedMap, {String? payrollKey, double? amt}) {
    setState(() {
      final idx = _expensesDocs.indexWhere((e) => e['id'] == docId);
      if (idx != -1) _expensesDocs[idx] = {..._expensesDocs[idx], ...updatedMap, 'id': docId};
      if (payrollKey != null && amt != null) _payrollAmountsByKey[payrollKey] = amt;
    });

    final dummyIdx = DummyData.expenses.indexWhere((e) => e['id'] == docId);
    if (dummyIdx != -1) {
      DummyData.expenses[dummyIdx] = {...DummyData.expenses[dummyIdx], ...updatedMap, 'id': docId};
    }

    if (payrollKey != null && amt != null) {
      _updatePayrollRecordWithAmount(payrollKey, amt);
    }

    DummyData.saveToPrefs();
  }

  void _updatePayrollRecordWithAmount(String payrollKey, double amt) {
    Map<String, dynamic> buildUpdated(Map<String, dynamic> record) {
      final baseSalary = PayrollService.extractSalary(record['salary'] ?? record['salaryAmount']);
      final overtime = amt >= baseSalary ? amt - baseSalary : 0.0;
      final absenceDeduction = amt < baseSalary ? baseSalary - amt : 0.0;
      final formatted = PayrollService.formatAmountInCurrency(amt, _currencyCode);

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

    final payrollIdx = DummyData.payroll.indexWhere(
      (r) => (r['payrollKey'] ?? '').toString().trim() == payrollKey,
    );
    if (payrollIdx != -1) {
      DummyData.payroll[payrollIdx] = buildUpdated(DummyData.payroll[payrollIdx]);
    }

    PreferencesService.getGuestPayroll().then((guestPayroll) {
      if (guestPayroll == null) return;
      final idx = guestPayroll.indexWhere((p) => (p['payrollKey'] ?? '').toString().trim() == payrollKey);
      if (idx != -1) {
        guestPayroll[idx] = buildUpdated(guestPayroll[idx]);
        PreferencesService.setGuestPayroll(guestPayroll);
      }
    });
  }

  void _deleteExpenseFromGuest(String docId, {String? payrollKey}) {
    setState(() {
      _expensesDocs.removeWhere((e) => e['id'] == docId);
      if (payrollKey != null) _payrollAmountsByKey.remove(payrollKey);
    });

    DummyData.expenses.removeWhere((e) => e['id'] == docId);

    if (payrollKey != null) {
      final normalized = payrollKey.trim();
      DummyData.payroll.removeWhere((r) => (r['payrollKey'] ?? '').toString().trim() == normalized);
      PreferencesService.getGuestPayroll().then((guestPayroll) {
        if (guestPayroll == null) return;
        guestPayroll.removeWhere((p) => (p['payrollKey'] ?? '').toString().trim() == normalized);
        PreferencesService.setGuestPayroll(guestPayroll);
      });
    }

    DummyData.saveToPrefs();
  }

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
          await _firestore.deletePayrollLinkedExpense(expenseId: docId, payrollKey: payrollKey);
        } else {
          await _firestore.deleteExpense(docId);
        }
      }

      if (mounted) FlashySnackBar.show(context, message: 'expense_deleted'.tr());
    } catch (e) {
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'failed_to_delete_record'.tr(namedArgs: {'error': e.toString()}),
        isError: true,
      );
    }
  }

  Future<void> _showExpenseDialog({
    required String title,
    required String buttonText,
    required Map<String, dynamic>? initialData,
    required Future<void> Function(Map<String, dynamic>) onSave,
  }) async {
    final isEdit = initialData != null;
    final categoryController = TextEditingController(text: isEdit ? initialData['category']?.toString() ?? '' : '');
    final amountController = TextEditingController(
      text: isEdit ? NumberFormat('#,##0.##').format(_expenseAmount(initialData)) : '',
    );
    final descriptionController = TextEditingController(
      text: isEdit ? initialData['name']?.toString() ?? initialData['description']?.toString() ?? '' : '',
    );

    final parsedDate = isEdit ? AppDateUtils.dateFromValue(initialData['date']) ?? DateTime.now() : DateTime.now();
    int selectedDay = parsedDate.day;
    DateTime calendarDate = DateTime(parsedDate.year, parsedDate.month, 1);
    var isSaving = false;

    await showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              backgroundColor: Colors.white,
              elevation: 10,
              child: Container(
                width: 730,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDialogHeader(
                      ctx,
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
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      },
                    ),
                    const SizedBox(height: 14),
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
                          final daysInNewMonth = DateTime(newDate.year, newDate.month + 1, 0).day;
                          if (selectedDay > daysInNewMonth) selectedDay = daysInNewMonth;
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
    BuildContext ctx, {
    required String title,
    required String buttonText,
    required bool isSaving,
    required VoidCallback onSave,
  }) {
    const buttonTextStyle = TextStyle(
      color: Color(0xFFFFFFFF),
      fontSize: 14,
      fontWeight: FontWeight.w600,
      fontFamily: 'SF Pro Display',
    );
    // Measure the label so the loading spinner swaps in at the exact same
    // width. Otherwise the button shrinks when saving starts and (being
    // right-aligned) visibly jumps.
    final textWidth = (TextPainter(
      text: TextSpan(text: buttonText, style: buttonTextStyle),
      textDirection: Directionality.of(ctx),
    )..layout())
        .width;

    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.black, size: 20),
              onPressed: () => Navigator.of(ctx).pop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF000000), fontFamily: 'SF Pro Display')),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0247C4),
                disabledBackgroundColor: const Color(0xFF0247C4),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                minimumSize: const Size(80, 32),
              ),
              onPressed: isSaving ? null : onSave,
              child: isSaving
                  ? SizedBox(
                      width: textWidth,
                      height: 20,
                      child: const Center(
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ),
                    )
                  : Text(buttonText, style: buttonTextStyle),
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
            Expanded(child: _buildModalTextField('expense_category'.tr(), categoryController, hintText: 'please_enter_category'.tr(), maxLength: 50)),
            const SizedBox(width: 16),
            Expanded(child: _buildModalTextField(
              'amount_header'.tr(), amountController,
              hintText: 'hint_amount'.tr(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              isAmount: true,
              prefixText: '${CurrencyUtils.symbolFor(_currencyCode)} ',
            )),
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
                  Text('expense_title'.tr(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF000000), fontFamily: 'SF Pro Display')),
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
                      style: const TextStyle(fontSize: 14, color: Colors.black, fontFamily: 'SF Pro Display'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(child: _buildModalCalendar(calendarDate, selectedDay, onDaySelected, onMonthChanged)),
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
      FlashySnackBar.show(context, message: 'please_fill_all_fields'.tr(), isError: true);
      return null;
    }

    final amt = double.tryParse(amountText.replaceAll(',', ''));
    if (amt == null || !amt.isFinite || amt <= 0) {
      FlashySnackBar.show(context, message: 'please_enter_valid_amount'.tr(), isError: true);
      return null;
    }

    if (amt > 999999999) {
      FlashySnackBar.show(context, message: 'amount_cannot_exceed_max'.tr(), isError: true);
      return null;
    }

    if (initialData == null) {
      try {
        final policies = await _firestore.getPolicies();
        final expPolicy = policies.where((p) => p['typeId'] == 'Expense Policy').toList();
        if (expPolicy.isNotEmpty) {
          final maxLimit = double.tryParse(expPolicy.first['maxExpenseLimitPerClaim']?.toString() ?? '500.0') ?? 500.0;
          if (!mounted) return null;
          if (amt > maxLimit) {
            FlashySnackBar.show(
              context,
              message: 'expense_claim_exceeds_limit'.tr(namedArgs: {
                'maxLimit': formatMoney(maxLimit, CurrencyUtils.symbolFor(_currencyCode)),
              }),
              isError: true,
            );
            return null;
          }
        }
      } catch (_) {}
    }

    final date = DateTime(calendarDate.year, calendarDate.month, selectedDay);
    return {'date': date, 'category': category, 'amount': amt, 'name': description, 'description': description};
  }

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
          FlashySnackBar.show(parentContext, message: 'successfully_added_expense'.tr(namedArgs: {'name': expenseMap['category']}));
          tryShowFirstMilestoneRateUs('expense');
        } catch (e) {
          if (mounted) FlashySnackBar.show(context, message: 'failed_to_add_expense'.tr(namedArgs: {'error': e.toString()}), isError: true);
          rethrow;
        }
      },
    );
  }

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
            _updateExpenseInGuest(docId, updatedMap, payrollKey: wasPayroll ? payrollKey : null, amt: wasPayroll ? amt : null);
          } else if (wasPayroll && payrollKey.isNotEmpty) {
            await _firestore.updatePayrollLinkedExpense(
              expenseId: docId, payrollKey: payrollKey, expenseData: updatedMap, netAmount: amt, currency: _currencyCode,
            );
          } else {
            await _firestore.updateExpense(docId, updatedMap);
          }
          if (mounted) FlashySnackBar.show(context, message: 'expense_updated'.tr());
        } on ArgumentError catch (e) {
          if (mounted) FlashySnackBar.show(context, message: e.message?.toString() ?? 'failed_to_update_expense'.tr(), isError: true);
        } catch (e) {
          if (mounted) FlashySnackBar.show(context, message: 'failed_to_update_expense'.tr(namedArgs: {'error': e.toString()}), isError: true);
        }
      },
    );
  }

  Widget _buildModalTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    String hintText = '',
    int? maxLength,
    bool isAmount = false,
    String? prefixText,
  }) {
    const fieldStyle = TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display');
    final textField = TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: isAmount
          ? [
              FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
              LengthLimitingTextInputFormatter(18),
              const ThousandsSeparatorInputFormatter(),
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
      style: fieldStyle,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF000000), fontFamily: 'SF Pro Display')),
        const SizedBox(height: 8),
        Container(
          height: 44,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          // Render the prefix (e.g. currency symbol) as a static widget so it
          // stays visible even when the field is empty and not focused.
          child: prefixText == null
              ? textField
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(prefixText, style: fieldStyle),
                    const SizedBox(width: 4),
                    Expanded(child: textField),
                  ],
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
    return ModalCalendar(
      calendarDate: calendarDate,
      selectedDay: selectedDay,
      onDaySelected: onDaySelected,
      onMonthChanged: onMonthChanged,
      spacing: 8,
      selectedColor: const Color(0xFFFF0004),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredExpenses;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          _buildHeader(),
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

  Widget _buildHeader() {
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
              Text('expenses'.tr(),
                  style: const TextStyle(color: Color(0xFF000000), fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'SF Pro Display')),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          GestureDetector(onTap: widget.onProfileTap, child: const UserAvatar()),
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
                SvgPicture.asset('assets/search icon.svg', width: 20, height: 20,
                    colorFilter: const ColorFilter.mode(Color(0xFFBDBDBD), BlendMode.srcIn)),
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
            icon: SvgPicture.asset('assets/add_expense.svg', width: 18, height: 18,
                colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn)),
            label: Text('add_expenses'.tr(),
                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display')),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(child: _buildCard(
          title: _selectedPeriodExpenseTitle,
          titleColor: const Color(0xFF0247C4),
          amount: _formatCurrency(_selectedPeriodExpenseSum),
          iconWidget: SvgPicture.asset('assets/expense_month.svg', width: 44, height: 44),
        )),
        const SizedBox(width: 24),
        Expanded(child: _buildCard(
          title: 'total_expense'.tr(),
          titleColor: Colors.red,
          amount: _formatCurrency(_totalExpenseSum),
          iconWidget: SvgPicture.asset('assets/total_expense.svg', width: 44, height: 44),
        )),
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
                Text(title,
                    style: TextStyle(fontSize: 15, color: titleColor, fontWeight: FontWeight.bold, fontFamily: 'SF Pro Display'),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(amount,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
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
        Text('expenses_list'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF000000), fontFamily: 'SF Pro Display')),
        CustomTimeframeDropdown(
          selectedPeriod: _selectedPeriod,
          options: const ['Today', 'This Week', 'This Month', 'Last 6 Months', 'This Year', 'All Time'],
          onChanged: (value) {
            setState(() {
              _selectedPeriod = value;
              if (_isGuest) _adjustDummyDatesForPeriod(value);
            });
          },
        ),
      ],
    );
  }

  Widget _buildDataTable(List<Map<String, dynamic>> expenses) {
    final tableHeight = (MediaQuery.of(context).size.height - 409).clamp(495.0, 1200.0);

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('expense_title'.tr()))),
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(left: 40, right: 16), child: _tableHeader('expense_category'.tr()))),
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('date_header'.tr(), textAlign: TextAlign.center))),
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
              itemBuilder: (_, index) => _buildDataRow(expenses[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String title, {TextAlign? textAlign}) {
    return Text(title, textAlign: textAlign,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _buildDataRow(Map<String, dynamic> doc) {
    final name = _expenseDisplayName(doc);
    final date = _localizedExpenseDate(doc['date']);
    final category = LocalizationHelper.localizeExpenseCategory((doc['category'] ?? '').toString());
    final amount = _expenseAmount(doc);

    return GestureDetector(
      onTap: () => _editExpense(doc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFFF6F8FA), borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: [
            Expanded(flex: 3, child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
            Expanded(flex: 3, child: Padding(
              padding: const EdgeInsets.only(left: 40, right: 16),
              child: Text(category,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            )),
            Expanded(flex: 3, child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(date, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            )),
            Expanded(flex: 2, child: Text(
              _isPayrollExpense(doc) ? _formatFullCurrency(amount) : _formatCurrency(amount),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF0247C4), fontWeight: FontWeight.w600, fontFamily: 'SF Pro Display'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: Color(0xFFCBCBCB))),
        color: const Color(0xFFFBFBFC),
        elevation: 4,
        onSelected: (value) {
          if (value == 'edit') {
            _editExpense(doc);
          } else if (value == 'delete') {
            _deleteExpense(doc);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: Row(
              children: [
                SvgPicture.asset('assets/edit_icon.svg', width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(Color(0xFF0247C4), BlendMode.srcIn)),
                const SizedBox(width: 8),
                Text('edit_expense'.tr(),
                    style: const TextStyle(color: Color(0xFF0247C4), fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            height: 36,
            child: Row(
              children: [
                SvgPicture.asset('assets/delete_icon.svg', width: 16, height: 16,
                    colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn)),
                const SizedBox(width: 8),
                Text('delete'.tr(),
                    style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
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
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/placeholder_workers.svg', width: 120, height: 100,
              colorFilter: const ColorFilter.mode(Color(0xFFCBCBCB), BlendMode.srcIn)),
          const SizedBox(height: 16),
          Text('add_expenses'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0247C4), fontFamily: 'SF Pro Display')),
        ],
      ),
    );
  }
}

