import 'dart:async' show StreamSubscription, TimeoutException, Timer;
import 'dart:ui';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/preferences_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../services/invoice_service.dart';
import '../utils/file_utils.dart';
import '../utils/ui_utils.dart';
import '../utils/dialog_utils.dart';
import '../utils/guest_restriction.dart';
import '../utils/currency_utils.dart';
import '../utils/company_profile_helper.dart';
import '../utils/date_time_utils.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/notification_bell.dart';
import '../widgets/notification_sidebar.dart';
import '../widgets/amount_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

Future<Uint8List> _generatePayrollInvoice(Map<String, dynamic> args) {
  return InvoiceService.generatePayrollInvoice(
    employeeName: args['employeeName'] as String,
    email: args['email'] as String,
    position: args['position'] as String,
    payPeriod: args['payPeriod'] as String,
    totalWorkDays: args['totalWorkDays'] as String,
    daysWorked: args['daysWorked'] as String,
    absents: args['absents'] as String,
    leaves: args['leaves'] as String,
    paidLeaves: args['paidLeaves'] as String? ?? '',
    unpaidLeaves: args['unpaidLeaves'] as String? ?? '',
    overtimeAmount: args['overtimeAmount'] as String,
    salary: args['salary'] as String,
    dailyRate: args['dailyRate'] as String,
    grossPay: args['grossPay'] as String,
    overtimePay: args['overtimePay'] as String,
    absentDeduction: args['absentDeduction'] as String,
    leaveDeduction: args['leaveDeduction'] as String,
    totalDeductions: args['totalDeductions'] as String,
    netSalary: args['netSalary'] as String,
    currency: args['currency'] as String,
    companyName: args['companyName'] as String? ?? 'HRMS',
    companyAddress: args['companyAddress'] as String? ?? '',
    companyEmail: args['companyEmail'] as String? ?? '',
    companyPhone: args['companyPhone'] as String? ?? '',
    companyId: args['companyId'] as String? ?? '',
    companyStampImageUrl: args['companyStampImageUrl'] as String?,
    companyLogoUrl: args['companyLogoUrl'] as String?,
    companyLogoBytes: args['companyLogoBytes'] as Uint8List?,
    workerId: args['workerId'] as String? ?? '',
  );
}

class AddPayrollScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> workerData;
  final DateTime payrollMonth;
  final DateTime? payPeriodStart;
  final DateTime? payPeriodEnd;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onBack;
  final bool readOnly;

  const AddPayrollScreen({
    super.key,
    required this.workerData,
    required this.payrollMonth,
    this.payPeriodStart,
    this.payPeriodEnd,
    this.onNotificationTap,
    this.onProfileTap,
    this.onBack,
    this.readOnly = false,
  });

  @override
  ConsumerState<AddPayrollScreen> createState() => _AddPayrollScreenState();
}

class _AddPayrollScreenState extends ConsumerState<AddPayrollScreen> {
  static const Color _primaryBlue = Color(0xFF0A44C2);
  static const Color _darkBlue = Color(0xFF082C7C);
  static const Color _textDark = Color(0xFF111827);
  static const Color _textGrey = Color(0xFF000000);
  static const Color _borderLight = Color(0xFFE5E7EB);

  late AuthService _authService;
  late FirestoreService _firestore;
  bool _initialized = false;

  final _workDaysCtrl = TextEditingController();
  final _absentsCtrl = TextEditingController();
  final _paidLeavesCtrl = TextEditingController();
  final _unpaidLeavesCtrl = TextEditingController();
  final _leavesCtrl = TextEditingController();
  final _overtimeAmountCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _absentDeductionCtrl = TextEditingController();
  final _leaveDeductionCtrl = TextEditingController();
  final _netCtrl = TextEditingController(text: r'$ 0');

  String _calculatedNet = '';
  Map<String, dynamic> _calcResult = {};
  bool _isSaving = false;
  bool _isCancellingPayroll = false;
  bool _isAttendanceLoading = true;
  bool _attendanceVerified = false;
  Object? _attendanceLoadError;
  bool _showNotifications = false;
  StreamSubscription? _attendanceSub;
  Timer? _attendanceRefreshDebounce;
  List<Map<String, dynamic>>? _liveAttendanceRecords;
  int _paidLeaves = 0;
  int _unpaidLeaves = 0;

  static const double _prorationFactor = 1.0;
  String _savedValuesFingerprint = '';
  bool _hasUnsavedChanges = false;

  String get _name => (widget.workerData['name'] ?? '').toString();

  String get _email => (widget.workerData['email'] ?? '').toString();

  String get _workerId =>
      (widget.workerData['workerId'] ?? widget.workerData['id'] ?? '')
          .toString();

  String get _position => (widget.workerData['position'] ?? '').toString();

  String get _phone =>
      (widget.workerData['contact'] ?? widget.workerData['phone'] ?? '')
          .toString();

  String get _profileImage =>
      (widget.workerData['profileImage'] ?? '').toString();

  String get _salaryStr => PayrollService.currentSalaryDisplay(
    widget.workerData,
    companyCurrency: _currencyCode,
  );

  String get _currencyCode {
    final companyCurr = PreferencesService.cachedCompanyCurrency;
    if (companyCurr != null && companyCurr.isNotEmpty) {
      return CurrencyUtils.normalize(companyCurr);
    }
    return CurrencyUtils.normalize(widget.workerData['currency']);
  }

  DateTime get _payrollMonth =>
      DateTime(widget.payrollMonth.year, widget.payrollMonth.month, 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (!(_authService.currentUser?.isAnonymous ?? false)) {
      _attendanceSub = _firestore.attendanceStream.listen((snapshot) {
        _liveAttendanceRecords = snapshot.docs
            .map(
              (doc) => {...?doc.data() as Map<String, dynamic>?, 'id': doc.id},
            )
            .toList();
        _scheduleAttendanceRefresh();
      }, onError: (_, _) {});
    }

    _salaryCtrl.text = AmountText.formatFull(
      _salaryStr,
      locale: context.locale.toString(),
    );

    final attendanceCounts = PayrollService.attendanceCounts(widget.workerData);
    _absentsCtrl.text = attendanceCounts['absents'].toString();
    _paidLeaves = attendanceCounts['paidLeaves'] ?? 0;
    _unpaidLeaves = attendanceCounts['unpaidLeaves'] ?? 0;
    _paidLeavesCtrl.text = _paidLeaves.toString();
    _unpaidLeavesCtrl.text = _unpaidLeaves.toString();
    _leavesCtrl.text = (attendanceCounts['leaves'] ?? 0).toString();

    final totalDays = (widget.workerData['totalWorkDays'] ?? '').toString();
    if (totalDays.isNotEmpty) {
      _workDaysCtrl.text = totalDays;
      _overtimeAmountCtrl.text = _editableAmountValue(
        widget.workerData['overtimeAmount'],
      );
      _absentDeductionCtrl.text = widget.workerData['hasPayrollRecord'] == true
          ? _editableAmountValue(widget.workerData['absentDeduction'])
          : '';
      _leaveDeductionCtrl.text = _editableAmountValue(
        widget.workerData['leaveDeduction'],
      );
      _recalc();
    }

    if (_absentsCtrl.text.isEmpty) _absentsCtrl.text = '0';
    if (_leavesCtrl.text.isEmpty) _leavesCtrl.text = '0';

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _fetchMonthlyAttendance(),
    );
  }

  @override
  void dispose() {
    _attendanceRefreshDebounce?.cancel();
    _attendanceSub?.cancel();
    _workDaysCtrl.dispose();
    _absentsCtrl.dispose();
    _paidLeavesCtrl.dispose();
    _unpaidLeavesCtrl.dispose();
    _leavesCtrl.dispose();
    _overtimeAmountCtrl.dispose();
    _salaryCtrl.dispose();
    _absentDeductionCtrl.dispose();
    _leaveDeductionCtrl.dispose();
    _netCtrl.dispose();
    super.dispose();
  }

  void _scheduleAttendanceRefresh() {
    if (_isPaidRecord) return;
    _attendanceRefreshDebounce?.cancel();
    _attendanceRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _fetchMonthlyAttendance();
    });
  }

  void _recalc() {
    if (_workDaysCtrl.text.trim().isEmpty) {
      setState(() {
        _calcResult = {};
        _calculatedNet = '';
        _netCtrl.text = r'$ 0';
      });
      return;
    }

    final totalDays = int.tryParse(_workDaysCtrl.text.trim()) ?? 0;
    final absentDays = int.tryParse(_absentsCtrl.text.trim()) ?? 0;
    final effectiveWorkedDays = (totalDays - absentDays - _unpaidLeaves).clamp(
      0,
      totalDays,
    );

    _normalizeAbsentDeduction(absentDays: absentDays);

    final result = PayrollService.calculatePayroll(
      salary: _salaryStr,
      totalWorkDays: _workDaysCtrl.text,
      daysWorked: effectiveWorkedDays.toString(),
      absents: _absentsCtrl.text,
      leaves: _unpaidLeaves.toString(),
      overtimeAmount: _overtimeAmountCtrl.text,
      absentDeductionPerDay: _absentDeductionCtrl.text,
      leaveDeductionPerDay: _leaveDeductionCtrl.text,
      salaryType: (widget.workerData['salaryType'] ?? 'Monthly').toString(),
      prorationFactor: _prorationFactor,
    );

    if (_absentDeductionCtrl.text.trim().isEmpty) {
      final autoCalc = result['absentDeduction'] as double? ?? 0;
      if (autoCalc > 0) {
        result['absentDeduction'] = 0.0;
        result['formattedAbsentDeduct'] = '0';
        result['netSalary'] = (result['netSalary'] as double? ?? 0) + autoCalc;
        result['totalDeductions'] =
            (result['totalDeductions'] as double? ?? 0) - autoCalc;
        final cur = PayrollService.getCurrencyPrefix(_salaryStr);
        final pfx = cur.isNotEmpty ? '$cur ' : '';
        final netVal = result['netSalary'] as double? ?? 0;
        result['formattedNet'] =
            '$pfx${PayrollService.formatFullNumber(netVal)}';
        result['formattedNetSalary'] = result['formattedNet'];
      }
    }

    setState(() {
      _calcResult = result;
      _calculatedNet = result['formattedNet'] as String? ?? '';
      _netCtrl.text = _calculatedNet;
    });
  }

  String _editableValuesFingerprint() => [
    _workDaysCtrl.text.trim(),
    _absentsCtrl.text.trim(),
    _leavesCtrl.text.trim(),
    _overtimeAmountCtrl.text.trim(),
    _absentDeductionCtrl.text.trim(),
    _leaveDeductionCtrl.text.trim(),
    '$_paidLeaves',
    '$_unpaidLeaves',
  ].join('|');

  void _captureSavedValues() {
    if (widget.workerData['hasPayrollRecord'] != true) return;
    _savedValuesFingerprint = _editableValuesFingerprint();
    if (mounted && _hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = false);
    }
  }

  void _handleEditableValueChanged() {
    _recalc();
    if (widget.workerData['hasPayrollRecord'] != true ||
        _savedValuesFingerprint.isEmpty) {
      return;
    }
    final changed = _editableValuesFingerprint() != _savedValuesFingerprint;
    if (changed != _hasUnsavedChanges && mounted) {
      setState(() => _hasUnsavedChanges = changed);
    }
  }

  bool get _isPaidRecord =>
      widget.workerData['hasPayrollRecord'] == true &&
      widget.workerData['isPaid'] == true;

  bool get _canEditInputs => !widget.readOnly;

  bool get _hasAbsences => (int.tryParse(_absentsCtrl.text.trim()) ?? 0) > 0;

  void _normalizeAbsentDeduction({required int absentDays}) {
    if (absentDays <= 0) {
      if (_absentDeductionCtrl.text.isNotEmpty) {
        _absentDeductionCtrl.clear();
      }
      return;
    }

    final requested = PayrollService.extractSalary(_absentDeductionCtrl.text);
    if (requested <= 0) return;

    final leaveOnlyCalculation = PayrollService.calculatePayroll(
      salary: _salaryStr,
      totalWorkDays: _workDaysCtrl.text,
      absents: '0',
      leaves: _unpaidLeaves.toString(),
      overtimeAmount: _overtimeAmountCtrl.text,
      leaveDeductionPerDay: _leaveDeductionCtrl.text,
      salaryType: (widget.workerData['salaryType'] ?? 'Monthly').toString(),
      prorationFactor: _prorationFactor,
    );
    final capped = PayrollService.cappedAbsentDeduction(
      hasAbsences: true,
      requestedDeduction: requested,
      salary: _salaryStr,
      overtimeAmount: _overtimeAmountCtrl.text,
      leaveDeduction: (leaveOnlyCalculation['leaveDeduction'] as num? ?? 0)
          .toString(),
      salaryType: (widget.workerData['salaryType'] ?? 'Monthly').toString(),
      prorationFactor: _prorationFactor,
    );
    if (capped == requested) return;

    final text = capped % 1 == 0
        ? capped.toStringAsFixed(0)
        : capped.toStringAsFixed(2);
    _absentDeductionCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  (DateTime, DateTime) get _currentPayPeriod {
    if (_isPaidRecord) {
      final savedStart = widget.workerData['payPeriodStart'];
      final savedEnd = widget.workerData['payPeriodEnd'];
      final start = AppDateUtils.dateFromValue(savedStart);
      final end = AppDateUtils.dateFromValue(savedEnd);
      if (start != null && end != null) {
        return (start, end);
      }
    }
    return (
      widget.payPeriodStart ?? PayrollService.payPeriodStart(_payrollMonth),
      widget.payPeriodEnd ?? PayrollService.payPeriodEnd(_payrollMonth),
    );
  }

  Future<void> _fetchMonthlyAttendance() async {
    if (_email.trim().isEmpty && _workerId.trim().isEmpty) {
      if (mounted) {
        setState(() => _isAttendanceLoading = false);
        _captureSavedValues();
      }
      return;
    }
    if (_isPaidRecord) {
      if (!mounted) return;
      setState(() {
        _attendanceVerified = true;
        _attendanceLoadError = null;
        _isAttendanceLoading = false;
      });
      _recalc();
      _captureSavedValues();
      return;
    }
    if (widget.workerData['hasPayrollRecord'] == true &&
        _savedValuesFingerprint.isEmpty) {
      _captureSavedValues();
    }
    final periodRange = _currentPayPeriod;
    try {
      final futures = <Future<Map<String, int>>>[
        _firestore
            .getWorkerMonthlyAttendance(
              _email,
              workerId: _workerId,
              month: _payrollMonth,
              startDate: periodRange.$1,
              endDate: periodRange.$2,
              preFetchedRecords: _liveAttendanceRecords,
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException(
                  'Attendance request timed out. Please check your connection and retry.',
                );
              },
            ),
      ];
      final allResults = await Future.wait(futures);
      final results = <String, int>{
        'absents': 0,
        'paidLeaves': 0,
        'unpaidLeaves': 0,
        'leaves': 0,
      };
      for (final r in allResults) {
        results['absents'] = (results['absents'] ?? 0) + (r['absents'] ?? 0);
        results['paidLeaves'] =
            (results['paidLeaves'] ?? 0) + (r['paidLeaves'] ?? 0);
        results['unpaidLeaves'] =
            (results['unpaidLeaves'] ?? 0) + (r['unpaidLeaves'] ?? 0);
        results['leaves'] = (results['leaves'] ?? 0) + (r['leaves'] ?? 0);
      }

      final workingDays = await _firestore
          .getMonthlyWorkingDays(month: _payrollMonth)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('working_days_timeout'.tr());
            },
          );
      if (!mounted) return;
      setState(() {
        _absentsCtrl.text = (results['absents'] ?? 0).toString();
        _paidLeaves = results['paidLeaves'] ?? 0;
        _unpaidLeaves = results['unpaidLeaves'] ?? 0;
        _paidLeavesCtrl.text = _paidLeaves.toString();
        _unpaidLeavesCtrl.text = _unpaidLeaves.toString();
        _leavesCtrl.text = (results['leaves'] ?? 0).toString();

        final currentWorkDays = _workDaysCtrl.text.trim();
        if ((currentWorkDays.isEmpty || currentWorkDays == '0') &&
            workingDays > 0) {
          _workDaysCtrl.text = workingDays.toString();
        }
        _attendanceVerified = true;
        _attendanceLoadError = null;
      });
      _recalc();
      _handleEditableValueChanged();
    } on TimeoutException catch (e) {
      debugPrint('⚠️ _fetchMonthlyAttendance timeout for $_email: $e');
      if (mounted) {
        setState(() {
          _attendanceVerified = false;
          _attendanceLoadError = e;
        });
        FlashySnackBar.show(
          context,
          message: '${'failed_to_load_attendance'.tr()}\n${e.message ?? ''}',
          isError: true,
          maxLines: null,
        );
      }
    } catch (e) {
      debugPrint('⚠️ _fetchMonthlyAttendance error for $_email: $e');
      if (mounted) {
        setState(() {
          _attendanceVerified = false;
          _attendanceLoadError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isAttendanceLoading = false);
        if (_savedValuesFingerprint.isEmpty) _captureSavedValues();
      }
    }
  }

  Future<void> _handleSave() async {
    if (_isAttendanceLoading) {
      FlashySnackBar.show(
        context,
        message: 'attendance_still_loading'.tr(),
        isError: true,
      );
      return;
    }

    if (!_attendanceVerified) {
      final errorDetail = _attendanceLoadError?.toString() ?? '';
      FlashySnackBar.show(
        context,
        message: errorDetail.isNotEmpty
            ? '${'failed_to_load_attendance'.tr()}\n$errorDetail'
            : 'failed_to_load_attendance'.tr(),
        isError: true,
        maxLines: null,
      );
      return;
    }
    final workDaysText = _workDaysCtrl.text.trim();
    final absentsText = _absentsCtrl.text.trim();
    final leavesText = _leavesCtrl.text.trim();
    final salaryText = _salaryStr.trim();
    final salaryAmount = PayrollService.extractSalary(salaryText);

    if (workDaysText.isEmpty &&
        absentsText.isEmpty &&
        leavesText.isEmpty &&
        (salaryText.isEmpty || salaryAmount <= 0)) {
      FlashySnackBar.show(
        context,
        message: 'please_fill_all_fields'.tr(),
        isError: true,
      );
      return;
    }

    final validators = <(String, String, bool)>[
      (workDaysText, 'please_enter_total_work_days'.tr(), false),
      (absentsText, 'please_enter_absents'.tr(), false),
      (leavesText, 'please_enter_leaves'.tr(), false),
      (salaryText, 'please_enter_salary'.tr(), true),
    ];

    for (final (value, message, isCurrency) in validators) {
      if (value.isEmpty || (isCurrency && salaryAmount <= 0)) {
        FlashySnackBar.show(context, message: message, isError: true);
        return;
      }
    }
    final parsedWorkDays = int.tryParse(workDaysText) ?? 0;
    if (parsedWorkDays <= 0) {
      FlashySnackBar.show(
        context,
        message: 'work_days_must_be_greater_than_zero'.tr(),
        isError: true,
      );
      return;
    }
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final now = DateTime.now();
    final payrollIdentity = _workerId.trim().isNotEmpty
        ? _workerId.trim()
        : _email.trim().toLowerCase();
    final (periodStart, periodEnd) = _currentPayPeriod;
    final payrollKey = PayrollService.payrollKeyForPeriod(
      payrollIdentity,
      periodStart,
      periodEnd,
    );
    final netAmount =
        (_calcResult['netSalary'] as num?)?.toDouble() ??
        PayrollService.extractSalary(_calculatedNet);
    final paidAt =
        widget.workerData['paidAt'] ??
        widget.workerData['paidOn'] ??
        widget.workerData['paymentDate'] ??
        now;

    final record = <String, dynamic>{
      'workerId': _workerId,
      'name': _name,
      'email': _email,
      'position': _position,
      'contact': _phone,
      'status': 'Paid',
      'profileImage': _profileImage,
      'totalWorkDays': int.tryParse(_workDaysCtrl.text.trim()) ?? 0,
      'absents': int.tryParse(_absentsCtrl.text.trim()) ?? 0,
      'paidLeaves': _paidLeaves,
      'unpaidLeaves': _unpaidLeaves,
      'leaves': int.tryParse(_leavesCtrl.text.trim()) ?? 0,
      'overtimeAmount': PayrollService.extractSalary(_overtimeAmountCtrl.text),
      'absentDeduction': PayrollService.extractSalary(
        _absentDeductionCtrl.text,
      ),
      'leaveDeduction': PayrollService.extractSalary(_leaveDeductionCtrl.text),
      'deductionsAreTotals': false,
      'salary': _salaryStr,
      'currency': _currencyCode,
      'salaryType': (widget.workerData['salaryType'] ?? 'Monthly').toString(),
      'netSalary': _calculatedNet,
      'netSalaryAmount': netAmount,
      'netSalaryFormatted': _calculatedNet,
      'payPeriod': periodEnd,
      'payPeriodStart': periodStart,
      'payPeriodEnd': periodEnd,
      'dueDate': periodEnd,
      'payrollKey': payrollKey,
      'prorationFactor': _prorationFactor,
      'paidAt': paidAt,
      'cancelledAt': null,
      'lastModified': now,
    };

    setState(() => _isSaving = true);

    try {
      if (isGuest) {
        final guestPayroll =
            (await PreferencesService.getGuestPayroll()) ??
            <Map<String, dynamic>>[];
        final idx = guestPayroll.indexWhere((p) {
          return (p['payrollKey'] ?? '').toString() == payrollKey;
        });
        if (idx != -1) {
          guestPayroll[idx] = {...guestPayroll[idx], ...record};
        } else {
          guestPayroll.add(record);
        }
        await PreferencesService.setGuestPayroll(guestPayroll);

        final expenseRecord = <String, dynamic>{
          'name': _name,
          'date': paidAt,
          'category': 'Salary',
          'amount': netAmount,
          'description': 'Salary payment for $_name',
          'payrollKey': payrollKey,
        };
        final existingExpenseIndex = DummyData.expenses.indexWhere(
          (expense) => (expense['payrollKey'] ?? '').toString() == payrollKey,
        );
        if (netAmount > 0) {
          if (existingExpenseIndex == -1) {
            final id =
                'dummy_e${DateTime.now().microsecondsSinceEpoch}'
                '_${record.hashCode.abs()}';
            DummyData.expenses.insert(0, {...expenseRecord, 'id': id});
          } else {
            DummyData.expenses[existingExpenseIndex] = {
              ...DummyData.expenses[existingExpenseIndex],
              ...expenseRecord,
            };
          }
        } else if (existingExpenseIndex != -1) {
          DummyData.expenses.removeAt(existingExpenseIndex);
        }
        await DummyData.saveToPrefs();
        if (mounted) setState(() {});
      } else {
        final hasExisting = widget.workerData['hasPayrollRecord'] == true;
        final existingId = widget.workerData['id']?.toString() ?? '';
        final expenseRecord = <String, dynamic>{
          'name': _name,
          'date': paidAt,
          'category': 'Salary',
          'amount': netAmount,
          'description': 'Salary payment for $_name',
          'payrollKey': payrollKey,
        };
        await _firestore.savePayrollAndExpenseBatch(
          record: record,
          payrollKey: payrollKey,
          netAmount: netAmount,
          expenseRecord: expenseRecord,
          existingPayrollId: hasExisting ? existingId : null,
        );
      }

      if (!mounted) return;

      FlashySnackBar.show(context, message: 'payroll_saved_successfully'.tr());
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_save_record'.tr(),
          isError: true,
        );
      }
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    try {
      await _generateAndShowInvoice();
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'invoice_generation_failed_after_save'.tr(),
          isError: true,
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
    if (mounted) {
      widget.onBack?.call();
    }
  }

  Future<void> _handleCancelPayroll() async {
    if (_isSaving ||
        _isCancellingPayroll ||
        widget.workerData['hasPayrollRecord'] != true) {
      return;
    }
    final payrollId = (widget.workerData['id'] ?? '').toString().trim();
    final payrollKey = (widget.workerData['payrollKey'] ?? '')
        .toString()
        .trim();
    setState(() => _isCancellingPayroll = true);
    try {
      final isGuest = _authService.currentUser?.isAnonymous ?? false;
      if (isGuest) {
        final guestPayroll =
            (await PreferencesService.getGuestPayroll()) ??
            <Map<String, dynamic>>[];
        final idx = guestPayroll.indexWhere((p) {
          return (p['payrollKey'] ?? '').toString() == payrollKey ||
              (p['id'] ?? '').toString() == payrollId;
        });
        if (idx != -1) {
          final cancelledAt = DateTime.now();
          guestPayroll[idx] = {
            ...guestPayroll[idx],
            'status': 'Unpaid',
            'isPaid': false,
            'paid': false,
            'paymentStatus': 'unpaid',
            'cancelledAt': cancelledAt,
            'lastModified': cancelledAt,
          }..remove('paidAt');
          guestPayroll[idx].remove('paidOn');
          guestPayroll[idx].remove('paymentDate');
          await PreferencesService.setGuestPayroll(guestPayroll);
        }
        final expenseIndex = DummyData.expenses.indexWhere(
          (expense) => (expense['payrollKey'] ?? '').toString() == payrollKey,
        );
        if (expenseIndex != -1) {
          DummyData.expenses.removeAt(expenseIndex);
        }
        await DummyData.saveToPrefs();
        if (mounted) setState(() {});
      } else {
        await _firestore.cancelPayrollRecord(
          payrollId: payrollId,
          payrollKey: payrollKey,
        );
      }
      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: 'payroll_cancelled_for_worker'.tr(namedArgs: {'name': _name}),
      );
      widget.onBack?.call();
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'payroll_cancel_failed'.tr(),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCancellingPayroll = false);
    }
  }

  String _editableAmountValue(dynamic value) {
    final text = (value ?? '').toString().trim();
    return PayrollService.extractSalary(text) == 0 ? '' : text;
  }

  Future<void> _generateAndShowInvoice() async {
    if (_calcResult.isEmpty) {
      return;
    }

    final cr = _calcResult;
    final (periodStart, periodEnd) = _currentPayPeriod;
    final payPeriod = PayrollService.formatPayPeriodRange(
      periodStart,
      periodEnd,
      locale: context.locale.toString(),
    );
    final fileName =
        'payroll_${_name.replaceAll(' ', '_')}'
        '_${PayrollService.periodDateKey(periodStart)}'
        '_${PayrollService.periodDateKey(periodEnd)}.pdf';

    final companyProfile =
        await CompanyProfileHelper.getCompanyProfileWithFirestore(_firestore);
    final companyLogoUrl = (companyProfile['profilePicUrl'] ?? '').toString();
    final companyLogoBytes = await InvoiceService.resolveCompanyLogoBytes(
      companyLogoUrl,
    );

    final bytes = await _generatePayrollInvoice({
      'employeeName': _name,
      'email': _email,
      'position': _position,
      'payPeriod': payPeriod,
      'totalWorkDays': _workDaysCtrl.text.trim(),
      'daysWorked': (cr['workedDays'] ?? 0).toString(),
      'absents': _absentsCtrl.text.trim(),
      'leaves': _leavesCtrl.text.trim(),
      'paidLeaves': _paidLeaves.toString(),
      'unpaidLeaves': _unpaidLeaves.toString(),
      'overtimeAmount': _overtimeAmountCtrl.text.trim(),
      'salary': _salaryStr,
      'dailyRate': (cr['formattedDailyRate'] as String?) ?? '',
      'grossPay': (cr['formattedGross'] as String?) ?? '',
      'overtimePay': (cr['formattedOvertime'] as String?) ?? '',
      'absentDeduction': (cr['formattedAbsentDeduct'] as String?) ?? '',
      'leaveDeduction': (cr['formattedLeaveDeduct'] as String?) ?? '',
      'totalDeductions': (cr['formattedTotalDeductions'] as String?) ?? '',
      'netSalary': (cr['formattedNet'] as String?) ?? '',
      'currency': _currencyCode,
      'companyName': CompanyProfileHelper.companyNameOrFallback(
        companyProfile['companyName'],
      ),
      'companyAddress': (companyProfile['address'] ?? '').toString(),
      'companyEmail': (companyProfile['email'] ?? '').toString(),
      'companyPhone': (companyProfile['phone'] ?? '').toString(),
      'companyId': (companyProfile['companyId'] ?? '').toString(),
      'companyStampImageUrl': (companyProfile['companyStampUrl'] ?? '')
          .toString(),
      'companyLogoUrl': companyLogoUrl,
      'companyLogoBytes': companyLogoBytes,
      'workerId': _workerId,
    });

    if (mounted) await _showInvoicePreviewDialog(bytes, fileName);
  }

  static Future<pdfx.PdfPageImage?> _renderPdfPageHighQuality(
    pdfx.PdfPage page,
  ) => page.render(
    width: page.width * 3,
    height: page.height * 3,
    format: pdfx.PdfPageImageFormat.png,
    backgroundColor: '#ffffff',
  );

  Future<void> _showInvoicePreviewDialog(
    Uint8List pdfBytes,
    String fileName,
  ) async {
    bool isSharing = false;
    final controller = pdfx.PdfController(
      document: pdfx.PdfDocument.openData(pdfBytes),
    );

    try {
      await showDialog<void>(
        context: context,
        barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.55),
        builder: (ctx) {
          final screenSize = MediaQuery.of(ctx).size;
          final dialogWidth = screenSize.width > 620
              ? 540.0
              : screenSize.width - 16;
          final dialogHeight = screenSize.height > 900
              ? 860.0
              : screenSize.height - 32;

          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.all(16),
                  child: Container(
                    width: dialogWidth,
                    height: dialogHeight,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.18),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                          ),
                          child: SizedBox(
                            height: 40,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  'invoice_preview'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'SF Pro Display',
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: 'close'.tr(),
                                    child: IconButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      padding: EdgeInsets.zero,
                                      constraints:
                                          const BoxConstraints.tightFor(
                                            width: 40,
                                            height: 40,
                                          ),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 24,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF0247C4,
                                          ),
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: const Color(
                                            0xFF0247C4,
                                          ).withValues(alpha: 0.55),
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                        ),
                                        onPressed: isSharing
                                            ? null
                                            : () async {
                                                setDialogState(
                                                  () => isSharing = true,
                                                );
                                                try {
                                                  final saved =
                                                      await InvoiceService.shareInvoice(
                                                        pdfBytes,
                                                        fileName,
                                                      );
                                                  if (saved && ctx.mounted) {
                                                    FlashySnackBar.show(
                                                      ctx,
                                                      message:
                                                          'file_saved_and_opened'
                                                              .tr(
                                                                namedArgs: {
                                                                  'file':
                                                                      fileName,
                                                                },
                                                              ),
                                                    );
                                                  }
                                                } catch (_) {
                                                  if (ctx.mounted) {
                                                    FlashySnackBar.show(
                                                      ctx,
                                                      message:
                                                          'unexpected_error'
                                                              .tr(),
                                                      isError: true,
                                                    );
                                                  }
                                                } finally {
                                                  if (ctx.mounted) {
                                                    setDialogState(
                                                      () => isSharing = false,
                                                    );
                                                  }
                                                }
                                              },
                                        icon: isSharing
                                            ? const SizedBox(
                                                width: 23,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : SvgPicture.asset(
                                                'assets/share1.svg',
                                                width: 16,
                                                height: 16,
                                                colorFilter:
                                                    const ColorFilter.mode(
                                                      Colors.white,
                                                      BlendMode.srcIn,
                                                    ),
                                              ),
                                        label: Text(
                                          'share'.tr(),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFDDE3EA),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF0F172A,
                                    ).withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: pdfx.PdfView(
                                controller: controller,
                                renderer: _renderPdfPageHighQuality,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      try {
        controller.dispose();
      } catch (_) {}
    }
  }

  void _toggleNotifications() {
    setState(() => _showNotifications = !_showNotifications);
  }

  void _onNotificationTap(String type) {
    setState(() => _showNotifications = false);
  }

  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) return true;
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'UnsavedChangesDialog',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 12 * animation.value,
            sigmaY: 12 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: curve,
              child: Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF000000).withValues(alpha: 0.15),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEE2E2),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.warning_rounded,
                            color: Color(0xFFEF4444),
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'discard_changes'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF000000),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'unsaved_changes_message'.tr(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                          fontFamily: 'SF Pro Display',
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context, false),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'cancel'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFF000000),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context, true),
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withValues(alpha: 0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  'discard'.tr(),
                                  style: const TextStyle(
                                    color: Color(0xFFFFFFFF),
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          widget.onBack?.call();
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF8F9FB),
            body: SafeArea(
              child: Column(
                children: [
                  _buildAppBar(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPayrollDataHeader(),
                              const SizedBox(height: 24),
                              _buildEmployeeBanner(),
                              const SizedBox(height: 12),
                              _buildDetailsCard(),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_showNotifications) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleNotifications,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            NotificationSidebar(
              onClose: _toggleNotifications,
              onNotificationTap: _onNotificationTap,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop) widget.onBack?.call();
            },
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_back, color: _textDark, size: 24),
            ),
          ),
          Text(
            'workforce'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const Spacer(),
          NotificationBell(onTap: _toggleNotifications),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollDataHeader() {
    final hasRecord = widget.workerData['hasPayrollRecord'] == true;
    final showEditButtons = !widget.readOnly;
    final showSaveButton =
        showEditButtons && (!_isPaidRecord || _hasUnsavedChanges);
    final showCancelButton = hasRecord && _isPaidRecord;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'payroll_data'.tr(),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        Row(
          children: [
            if (showEditButtons && showCancelButton) ...[
              OutlinedButton(
                onPressed: _isSaving || _isCancellingPayroll
                    ? null
                    : () async {
                        final confirmed = await DeleteDialog.show(
                          context: context,
                          title: 'cancel_payroll'.tr(),
                          content: 'cancel_payroll_confirm'.tr(
                            namedArgs: {'name': _name},
                          ),
                          confirmButtonText: 'cancel_payroll',
                        );
                        if (confirmed) _handleCancelPayroll();
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935), width: 1.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isCancellingPayroll
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Color(0xFFE53935),
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'cancel_payroll'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
            if (showCancelButton && widget.readOnly) ...[
              OutlinedButton(
                onPressed: () async {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  final confirmed = await DeleteDialog.show(
                    context: context,
                    title: 'cancel_payroll'.tr(),
                    content: 'cancel_payroll_confirm'.tr(
                      namedArgs: {'name': _name},
                    ),
                    confirmButtonText: 'cancel_payroll',
                  );
                  if (confirmed) _handleCancelPayroll();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE53935),
                  side: const BorderSide(color: Color(0xFFE53935), width: 1.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isCancellingPayroll
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Color(0xFFE53935),
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'cancel_payroll'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
            if (showSaveButton) ...[
              if (hasRecord) const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _isSaving || _isCancellingPayroll
                    ? null
                    : () {
                        final isGuest =
                            _authService.currentUser?.isAnonymous ?? false;
                        if (isGuest) {
                          showGuestRestrictionDialog(context);
                          return;
                        }
                        _handleSave();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0B50C3),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isPaidRecord
                            ? (_hasUnsavedChanges
                                  ? 'save_correction'.tr()
                                  : 'save'.tr())
                            : 'process_payroll'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEmployeeBanner() {
    final (firstDay, lastDay) = _currentPayPeriod;
    final period = PayrollService.formatPayPeriodRange(
      firstDay,
      lastDay,
      locale: context.locale.toString(),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_primaryBlue, Color(0xFF1E5EE0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              WorkerAvatar(
                imageUrl: _profileImage,
                name: _name,
                size: 80,
                shape: BoxShape.circle,
              ),
            ],
          ),
          const SizedBox(width: 24),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.work_outline,
                      color: Color(0xB3FFFFFF),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _position,
                        style: const TextStyle(
                          color: Color(0xB3FFFFFF),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'current_pay_period'.tr(),
                style: const TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                period,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final cr = _calcResult;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 24, color: _darkBlue),
              const SizedBox(width: 12),
              Text(
                'attendance_salary_details'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInput(
                  'absents_label'.tr(),
                  '0',
                  _absentsCtrl,
                  readOnly: true,
                  focusedBorderColor: _borderLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInput(
                  'leaves_label'.tr(),
                  '0',
                  _paidLeavesCtrl,
                  readOnly: true,
                  focusedBorderColor: _borderLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInput(
                  'overtime_amount'.tr(),
                  '0',
                  _overtimeAmountCtrl,
                  isCurrency: true,
                  readOnly: !_canEditInputs,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInput(
                  'absent_deduction_per_day'.tr(),
                  '0',
                  _absentDeductionCtrl,
                  isCurrency: true,
                  readOnly: !_canEditInputs || !_hasAbsences,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildInput(
                  'base_salary'.tr(),
                  '',
                  _salaryCtrl,
                  readOnly: true,
                  focusedBorderColor: _borderLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildCalculatedInput()),
            ],
          ),
          const SizedBox(height: 32),

          if (cr.isNotEmpty) ...[
            _buildCalcBreakdown(cr),
            const SizedBox(height: 16),
          ],

          Divider(color: _borderLight, thickness: 1),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInput(
    String label,
    String hint,
    TextEditingController? controller, {
    bool readOnly = false,
    bool isCurrency = false,
    Color? focusedBorderColor,
    String? helperText,
  }) {
    final isDaysInput = !readOnly && !isCurrency;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textGrey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          readOnly: readOnly,
          mouseCursor: SystemMouseCursors.basic,
          onChanged: readOnly ? null : (_) => _handleEditableValueChanged(),
          keyboardType: isCurrency
              ? const TextInputType.numberWithOptions(decimal: true)
              : isDaysInput
              ? TextInputType.number
              : null,
          inputFormatters: isCurrency
              ? [CommaCurrencyFormatter(), LengthLimitingTextInputFormatter(14)]
              : isDaysInput
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ]
              : null,
          decoration: InputDecoration(
            prefixIcon: isCurrency
                ? Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Align(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        CurrencyUtils.symbolFor(_currencyCode),
                        style: TextStyle(
                          color: readOnly ? const Color(0xFF9CA3AF) : _textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  )
                : null,
            prefixIconConstraints: isCurrency
                ? const BoxConstraints(minWidth: 0, minHeight: 0)
                : null,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: focusedBorderColor ?? _borderLight),
            ),
            hoverColor: Colors.transparent,
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF9FAFB) : null,
          ),
          style: TextStyle(
            fontSize: 16,
            color: readOnly ? const Color(0xFF9CA3AF) : _textDark,
          ),
        ),
        if (helperText != null && helperText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ],
    );
  }

  Widget _buildCalculatedInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'net_pay'.tr(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        IgnorePointer(
          child: TextField(
            controller: _netCtrl,
            readOnly: true,
            enableInteractiveSelection: false,
            style: const TextStyle(
              fontSize: 16,
              color: _darkBlue,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD2E3FC)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD2E3FC)),
              ),
              filled: true,
              fillColor: const Color(0xFFEDF2FA),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalcBreakdown(Map<String, dynamic> cr) {
    String fmt(String key) => (cr[key] as String?) ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderLight),
      ),
      child: Column(
        children: [
          _breakdownRow('gross_pay'.tr(), fmt('formattedGross'), null),
          _breakdownRow('overtime_pay'.tr(), fmt('formattedOvertime'), null),
          _breakdownRow(
            'absent_deduction'.tr(),
            fmt('formattedAbsentDeduct'),
            null,
          ),
          const Divider(height: 16, thickness: 1.5),
          _breakdownRow(
            'salary_after_deduction'.tr(),
            fmt('formattedNet'),
            null,
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(
    String label,
    String value,
    String? detail, {
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
                color: _textDark,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isTotal ? 15 : 13,
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
                color: isTotal ? _darkBlue : _textDark,
              ),
            ),
          ),
          if (detail != null)
            Expanded(
              child: Text(
                detail,
                style: const TextStyle(fontSize: 12, color: Color(0xFF000000)),
              ),
            ),
        ],
      ),
    );
  }
}
