import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../services/invoice_service.dart';
import '../utils/image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';

class AddPayrollScreen extends StatefulWidget {
  final Map<String, dynamic> workerData;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onBack;
  const AddPayrollScreen({
    super.key,
    required this.workerData,
    this.onNotificationTap,
    this.onProfileTap,
    this.onBack,
  });

  @override
  State<AddPayrollScreen> createState() => _AddPayrollScreenState();
}

class _AddPayrollScreenState extends State<AddPayrollScreen> {
  final _workDaysCtrl = TextEditingController();
  final _absentsCtrl = TextEditingController();
  final _leavesCtrl = TextEditingController();
  final _overtimeCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  final _absentDeductionCtrl = TextEditingController();
  final _leaveDeductionCtrl = TextEditingController();
  String _calculatedNet = '';
  Map<String, dynamic> _calcResult = {};
  bool _isSaving = false;
  final TextEditingController _netCtrl = TextEditingController(text: r'$ 0');

  static const _primaryBlue = Color(0xFF0A44C2);
  static const _darkBlue = Color(0xFF082C7C);
  static const _textDark = Color(0xFF111827);
  static const _textGrey = Color(0xFF000000);
  static const _borderLight = Color(0xFFE5E7EB);

  String get _name => (widget.workerData['name'] ?? '').toString();
  String get _email => (widget.workerData['email'] ?? '').toString();
  String get _position => (widget.workerData['position'] ?? '').toString();
  String get _status => (widget.workerData['status'] ?? 'Active').toString();
  String get _phone =>
      (widget.workerData['contact'] ?? widget.workerData['phone'] ?? '')
          .toString();
  String get _profileImage =>
      (widget.workerData['profileImage'] ?? '').toString();

  void _recalc() {
    setState(() {
      if (_workDaysCtrl.text.trim().isNotEmpty) {
        _calcResult = PayrollService.calculatePayroll(
          salary: _salaryStr,
          totalWorkDays: _workDaysCtrl.text,
          daysWorked: _workDaysCtrl.text,
          absents: _absentsCtrl.text,
          leaves: _leavesCtrl.text,
          overtimeDays: _overtimeCtrl.text,
          absentDeductionPerDay: _absentDeductionCtrl.text,
          leaveDeductionPerDay: _leaveDeductionCtrl.text,
        );
        _calculatedNet = _calcResult['formattedNet'] as String;
        _netCtrl.text = _calculatedNet;
      } else {
        _calcResult = {};
        _calculatedNet = '';
        _netCtrl.text = r'$ 0';
      }
    });
  }

  String get _salaryStr {
    final s = widget.workerData['salary'] ?? '';
    if (s.toString().isNotEmpty) return s.toString();
    return r'$ 0';
  }

  @override
  void initState() {
    super.initState();
    _salaryCtrl.text = _salaryStr;
    _absentsCtrl.text = (widget.workerData['absents'] ?? '').toString();
    _leavesCtrl.text = (widget.workerData['leaves'] ?? '').toString();
    final totalDays = (widget.workerData['totalWorkDays'] ?? '').toString();
    if (totalDays.isNotEmpty) {
      _workDaysCtrl.text = totalDays;
      _overtimeCtrl.text = (widget.workerData['overtimeDays'] ?? '').toString();
      _absentDeductionCtrl.text = (widget.workerData['absentDeduction'] ?? '').toString();
      _leaveDeductionCtrl.text = (widget.workerData['leaveDeduction'] ?? '').toString();
      _recalc();
    }
    if (_absentsCtrl.text.isEmpty) _absentsCtrl.text = '0';
    if (_leavesCtrl.text.isEmpty) _leavesCtrl.text = '0';
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchMonthlyAttendance());
  }

  Future<void> _fetchMonthlyAttendance() async {
    if (_email.trim().isEmpty) return;
    try {
      final attendance = await FirestoreService().getWorkerMonthlyAttendance(_email);
      setState(() {
        _absentsCtrl.text = (attendance['absents'] ?? 0).toString();
        _leavesCtrl.text = (attendance['leaves'] ?? 0).toString();
        _recalc();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _workDaysCtrl.dispose();
    _absentsCtrl.dispose();
    _leavesCtrl.dispose();
    _overtimeCtrl.dispose();
    _salaryCtrl.dispose();
    _absentDeductionCtrl.dispose();
    _leaveDeductionCtrl.dispose();
    _netCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_workDaysCtrl.text.trim().isEmpty) {
      FlashySnackBar.show(
        context,
        message: 'Please enter Total Work Days',
        isError: true,
      );
      return;
    }
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    final record = {
      'name': _name,
      'email': _email,
      'position': _position,
      'contact': _phone,
      'status': 'Paid',
      'profileImage': _profileImage,
      'totalWorkDays': _workDaysCtrl.text.trim(),
      'absents': _absentsCtrl.text.trim(),
      'leaves': _leavesCtrl.text.trim(),
      'overtimeDays': _overtimeCtrl.text.trim(),
      'absentDeduction': _absentDeductionCtrl.text.trim(),
      'leaveDeduction': _leaveDeductionCtrl.text.trim(),
      'salary': _salaryStr,
      'netSalary': _calculatedNet,
    };
    setState(() => _isSaving = true);
    try {
      if (isGuest) {
        final existingIdx = DummyData.payroll.indexWhere((p) {
          final pEmail = (p['email'] ?? '').toString().trim().toLowerCase();
          return pEmail.isNotEmpty && pEmail == _email.trim().toLowerCase();
        });
        if (existingIdx != -1) {
          DummyData.payroll[existingIdx] = {
            ...DummyData.payroll[existingIdx],
            ...record,
          };
        } else {
          DummyData.payroll.add(record);
        }
        await DummyData.saveToPrefs();
      } else {
        final existingId = widget.workerData['id']?.toString() ?? '';
        final hasExistingRecord = (widget.workerData['totalWorkDays'] ?? '')
            .toString()
            .isNotEmpty;
        if (hasExistingRecord && existingId.isNotEmpty) {
          await FirestoreService().updatePayrollRecord(existingId, record);
        } else {
          await FirestoreService().addPayrollRecord(record);
        }
      }

      // Auto-create expense entry for salary payment
      final netAmount = PayrollService.extractSalary(_calculatedNet);
      if (netAmount > 0) {
        final now = DateTime.now();
        final dateStr =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
        final expenseRecord = {
          'name': _name,
          'date': dateStr,
          'category': 'Salary',
          'amount': netAmount,
          'description': 'Salary payment for $_name',
        };
        if (isGuest) {
          final expenseId =
              'dummy_e${DateTime.now().microsecondsSinceEpoch}_${record.hashCode.toString().replaceAll('-', '')}';
          DummyData.expenses.insert(0, {
            ...expenseRecord,
            'id': expenseId,
          });
          await DummyData.saveToPrefs();
        } else {
          await FirestoreService().addExpense(expenseRecord);
        }
      }

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'payroll_saved_successfully'.tr(),
        );
        await _generateAndShowInvoice();
        widget.onBack?.call();
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'failed_to_save_record'.tr(),
          isError: true,
        );
      }
    }
  }

  Future<void> _generateAndShowInvoice() async {
    final cr = _calcResult;
    if (cr.isEmpty) return;

    final now = DateTime.now();
    final payPeriod = '${now.month.toString().padLeft(2, '0')}/${now.year}';
    final fileName = 'payroll_${_name.replaceAll(' ', '_')}_${payPeriod.replaceAll('/', '-')}.pdf';

    final bytes = await InvoiceService.generatePayrollInvoice(
      employeeName: _name,
      email: _email,
      position: _position,
      payPeriod: payPeriod,
      totalWorkDays: _workDaysCtrl.text.trim(),
      daysWorked: _workDaysCtrl.text.trim(),
      absents: _absentsCtrl.text.trim(),
      leaves: _leavesCtrl.text.trim(),
      overtimeDays: _overtimeCtrl.text.trim(),
      salary: _salaryStr,
      dailyRate: cr['formattedDailyRate'] as String? ?? '',
      grossPay: cr['formattedGross'] as String? ?? '',
      overtimePay: cr['formattedOvertime'] as String? ?? '',
      absentDeduction: cr['formattedAbsentDeduct'] as String? ?? '',
      leaveDeduction: cr['formattedLeaveDeduct'] as String? ?? '',
      totalDeductions: cr['formattedTotalDeductions'] as String? ?? '',
      netSalary: cr['formattedNet'] as String? ?? '',
    );

    if (mounted) {
      _showInvoicePreviewDialog(bytes, fileName);
    }
  }

  void _showInvoicePreviewDialog(Uint8List pdfBytes, String fileName) {
    final controller = pdfx.PdfController(
      document: pdfx.PdfDocument.openData(pdfBytes),
    );

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 720,
          height: 800,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, size: 24, color: Color(0xFF6B7280)),
                    ),
                    const Spacer(),
                    Text(
                      'invoice_preview'.tr(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro Display',
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0247C4),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        try {
                          await InvoiceService.shareInvoice(pdfBytes, fileName);
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.share, size: 16),
                      label: Text(
                        'share'.tr(),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: const Color(0xFFE5E7EB),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: pdfx.PdfView(
                      controller: controller,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        const SizedBox(height: 24),
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
    );
  }

  Widget _buildPayrollDataHeader() {
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
            OutlinedButton(
              onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryBlue,
                side: BorderSide(color: _primaryBlue.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'discard_changes'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _handleSave,
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
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'save_payroll'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack ?? () => Navigator.of(context).pop(),
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_back, color: _textDark, size: 24),
            ),
          ),
          Text(
            'Workforce',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
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


  Widget _buildEmployeeBanner() {
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
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: getProfileImage(_profileImage, _email, 0),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                bottom: -8,
                right: -12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A63F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.badge_outlined,
                      color: Color(0xB3FFFFFF),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ID: EMP-${_email.hashCode.toString().substring(0, 5)}',
                      style: const TextStyle(
                        color: Color(0xB3FFFFFF),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 24),
                    const Icon(
                      Icons.corporate_fare_outlined,
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
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Builder(
            builder: (_) {
              final now = DateTime.now();
              final firstDay = DateTime(now.year, now.month, 1);
              final lastDay = DateTime(now.year, now.month + 1, 0);
              final monthFmt = DateFormat('MMM');
              final period =
                  '${monthFmt.format(firstDay)} ${firstDay.day} - ${monthFmt.format(lastDay)} ${lastDay.day}, ${now.year}';
              return Column(
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
              );
            },
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
            children: [
              Expanded(
                child: _buildInput('total_work_days'.tr(), '22', _workDaysCtrl),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildInput('absents_label'.tr(), '0', _absentsCtrl, readOnly: true, focusedBorderColor: _borderLight),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildInput('leaves_label'.tr(), '0', _leavesCtrl, readOnly: true, focusedBorderColor: _borderLight),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildInput('overtime_days'.tr(), '2', _overtimeCtrl),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _buildInput(
                  'salary'.tr(),
                  '',
                  _salaryCtrl,
                  readOnly: true,
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: _buildCalculatedInput(cr)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInput('absent_deduction_per_day'.tr(), '0', _absentDeductionCtrl, isCurrency: true),
                    if (cr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${'daily_rate'.tr()}: ${cr['formattedDailyRate'] ?? ''}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInput('leave_deduction_per_day'.tr(), '0', _leaveDeductionCtrl, isCurrency: true),
                    if (cr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${'daily_rate'.tr()}: ${cr['formattedDailyRate'] ?? ''}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 32),
          if (cr.isNotEmpty) ...[
            _buildCalcBreakdown(cr),
            const SizedBox(height: 16),
          ],
          Divider(color: _borderLight, thickness: 1),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: _textGrey, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'last_modified_by_admin_on'.tr(
                      namedArgs: {
                        'date': DateTime.now().toString().substring(0, 10),
                      },
                    ),
                    style: const TextStyle(color: _textGrey, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
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
  }) {
    final isDaysInput = !readOnly && !isCurrency && label != 'salary'.tr();
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
          onChanged: readOnly ? null : (_) => _recalc(),
          keyboardType: isCurrency
              ? const TextInputType.numberWithOptions(decimal: true)
              : isDaysInput
                  ? TextInputType.number
                  : null,
          inputFormatters: isCurrency
              ? [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                  LengthLimitingTextInputFormatter(10),
                ]
              : isDaysInput
                  ? [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ]
                  : null,
          decoration: InputDecoration(
            hintText: readOnly ? null : hint,
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
              borderSide: BorderSide(color: focusedBorderColor ?? _primaryBlue),
            ),
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF9FAFB) : null,
          ),
          style: const TextStyle(fontSize: 16, color: _textDark),
        ),
      ],
    );
  }

  Widget _buildCalculatedInput(Map<String, dynamic> cr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'salary_after_deduction'.tr(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          readOnly: true,
          controller: _netCtrl,
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
      ],
    );
  }




  Widget _buildCalcBreakdown(Map<String, dynamic> cr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderLight),
      ),
      child: Column(
        children: [
          _breakdownRow(
            'daily_rate'.tr(),
            cr['formattedDailyRate'] as String,
            '${cr['totalWorkDaysPerYear']} ${'days_per_year'.tr()}',
          ),
          const Divider(height: 16),
          _breakdownRow(
            'gross_pay'.tr(),
            cr['formattedGross'] as String,
            '${cr['workedDays']} ${'days'.tr()}',
          ),
          _breakdownRow(
            'overtime_pay'.tr(),
            cr['formattedOvertime'] as String,
            '${cr['overtimeDays']} ${'days_overtime_multiplier'.tr()}',
          ),
          _breakdownRow(
            'absent_deduction'.tr(),
            cr['formattedAbsentDeduct'] as String,
            '${cr['absentDays']} ${'days'.tr()}',
          ),
          _breakdownRow(
            'leave_deduction'.tr(),
            cr['formattedLeaveDeduct'] as String,
            '${cr['leaveDays']} ${'days'.tr()}',
          ),
          const Divider(height: 16, thickness: 1.5),
          _breakdownRow(
            'net_pay'.tr(),
            cr['formattedNet'] as String,
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
