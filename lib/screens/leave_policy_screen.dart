import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../services/firestore_service.dart';
import '../services/leave_policy_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/dashboard/top_header.dart';

class LeavePolicyScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const LeavePolicyScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<LeavePolicyScreen> createState() => _LeavePolicyScreenState();
}

class _LeavePolicyScreenState extends State<LeavePolicyScreen> {
  late FirestoreService _firestore;
  bool _initialized = false;
  List<Map<String, dynamic>> _policies = [];
  bool _isLoading = true;
  String? _busyPolicyId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    _loadPolicies();
  }

  void _loadPolicies() {
    _firestore.leavePoliciesStream.listen((snap) {
      if (!mounted) return;
      setState(() {
        _policies = snap.docs
            .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
            .toList();
        _isLoading = false;
      });
    });
  }

  void _showAddPolicyForm() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeavePolicyDialog(
        onSave: (data) async {
          await _firestore.addLeavePolicy(data);
        },
      ),
    );
  }

  void _showEditPolicyForm(Map<String, dynamic> policy) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => LeavePolicyDialog(
        existingPolicy: policy,
        onSave: (data) async {
          await _firestore.updateLeavePolicy(policy['id'], data);
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _companyProfile() async {
    try {
      return await _firestore.getUserProfile() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _downloadPolicy(Map<String, dynamic> policy) async {
    final id = (policy['id'] ?? policy['policyName'] ?? '').toString();
    if (_busyPolicyId != null) return;
    setState(() => _busyPolicyId = id);
    try {
      final profile = await _companyProfile();
      final companyName = (profile['businessName'] ?? profile['companyName'])
          ?.toString();
      final bytes = await LeavePolicyService.generatePdf(
        policy,
        companyName: companyName,
        companyId: profile['companyId']?.toString(),
      );
      final saved = await LeavePolicyService.downloadPdf(
        bytes,
        LeavePolicyService.safeFileName(
          (policy['policyName'] ?? 'company_leave_policy').toString(),
        ),
      );
      if (saved && mounted) {
        FlashySnackBar.show(context, message: 'Leave policy PDF downloaded');
      }
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Unable to download leave policy PDF',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyPolicyId = null);
    }
  }

  Future<void> _sharePolicy(Map<String, dynamic> policy) async {
    final id = (policy['id'] ?? policy['policyName'] ?? '').toString();
    if (_busyPolicyId != null) return;
    setState(() => _busyPolicyId = id);
    try {
      final profile = await _companyProfile();
      final companyName = (profile['businessName'] ?? profile['companyName'])
          ?.toString();
      final bytes = await LeavePolicyService.generatePdf(
        policy,
        companyName: companyName,
        companyId: profile['companyId']?.toString(),
      );
      final fileName = LeavePolicyService.safeFileName(
        (policy['policyName'] ?? 'company_leave_policy').toString(),
      );
      if (!mounted) return;
      final renderBox = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          text: LeavePolicyService.formattedText(
            policy,
            companyName: companyName,
          ),
          subject: (policy['policyName'] ?? 'Company Leave Policy').toString(),
          files: [
            XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf'),
          ],
          fileNameOverrides: [fileName],
          sharePositionOrigin: renderBox == null
              ? null
              : renderBox.localToGlobal(Offset.zero) & renderBox.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Unable to share leave policy',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busyPolicyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          TopHeader(
            onProfileTap: widget.onProfileTap,
            onNotificationTap: widget.onNotificationTap ?? () {},
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset('assets/leave.svg', width: 28, height: 28),
              const SizedBox(width: 12),
              Text(
                'leave_policy'.tr(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _showAddPolicyForm,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'add_policy'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _policies.isEmpty
                ? _buildEmptyState()
                : _buildPolicyList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/leave.svg', width: 80, height: 80),
          const SizedBox(height: 16),
          Text(
            'No leave policies yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
              fontFamily: 'SF Pro Display',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Add Policy" to create your first leave policy',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyList() {
    return ListView.builder(
      itemCount: _policies.length,
      itemBuilder: (context, index) {
        final policy = _policies[index];
        return _buildPolicyCard(policy);
      },
    );
  }

  Widget _buildPolicyCard(Map<String, dynamic> policy) {
    final isActive = policy['isActive'] ?? true;
    final policyName = policy['policyName'] ?? '';
    final leaveType = policy['leaveType'] ?? '';
    final allowedLeaves = policy['allowedLeaves'] ?? '';
    final paidUnpaid = policy['paidUnpaid'] ?? '';
    final applicableTo = policy['applicableTo'] ?? '';
    final isBusy = _busyPolicyId == (policy['id'] ?? policyName).toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? const Color(0xFFE2E8F0)
              : const Color(0xFFE2E8F0).withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFEEF2FF)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(
                    Icons.description_outlined,
                    color: isActive ? const Color(0xFF4F46E5) : Colors.grey,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      policyName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isActive ? const Color(0xFF000000) : Colors.grey,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$leaveType • $allowedLeaves days/year • $paidUnpaid',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[500],
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? 'Active' : 'Disabled',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isActive ? const Color(0xFF16A34A) : Colors.grey,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _chip('Applicable: $applicableTo'),
              if ((policy['startDate'] ?? '').toString().isNotEmpty)
                _chip('From: ${policy['startDate']}'),
              if ((policy['endDate'] ?? '').toString().isNotEmpty)
                _chip('To: ${policy['endDate']}'),
              if (policy['carryForward'] == true) _chip('Carry Forward'),
              if (policy['approvalRequired'] == true)
                _chip('Approval Required'),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          Row(
            children: [
              _actionBtn(
                'Edit',
                Icons.edit_outlined,
                () => _showEditPolicyForm(policy),
              ),
              _actionBtn(
                isBusy ? 'Generating…' : 'Download PDF',
                Icons.download_outlined,
                isBusy ? () {} : () => _downloadPolicy(policy),
              ),
              _actionBtn(
                'Share',
                Icons.share_outlined,
                isBusy ? () {} : () => _sharePolicy(policy),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF64748B),
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    VoidCallback onTap, {
    Color? color,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color ?? const Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: color ?? const Color(0xFF64748B),
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

class PolicyDetailDialog extends StatelessWidget {
  final Map<String, dynamic> policy;
  const PolicyDetailDialog({super.key, required this.policy});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.78,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.policy_outlined,
                      color: Color(0xFF4F46E5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      policy['policyName'] ?? 'Leave Policy',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('Policy Name', policy['policyName'] ?? '-'),
                    _section('Leave Type', policy['leaveType'] ?? '-'),
                    _section(
                      'Allowed Leaves',
                      '${policy['allowedLeaves'] ?? '-'} days per year',
                    ),
                    _section('Paid / Unpaid', policy['paidUnpaid'] ?? '-'),
                    _section('Applicable To', policy['applicableTo'] ?? '-'),
                    if ((policy['startDate'] ?? '').toString().isNotEmpty)
                      _section('Start Date', '${policy['startDate']}'),
                    if ((policy['endDate'] ?? '').toString().isNotEmpty)
                      _section('End Date', '${policy['endDate']}'),
                    _section(
                      'Carry Forward',
                      policy['carryForward'] == true
                          ? 'Yes (${policy['carryForwardDays'] ?? 0} max days)'
                          : 'No',
                    ),
                    _section(
                      'Approval Required',
                      policy['approvalRequired'] == true ? 'Yes' : 'No',
                    ),
                    if ((policy['noticePeriod'] ?? '').toString().isNotEmpty)
                      _section('Notice Period', '${policy['noticePeriod']}'),
                    if ((policy['description'] ?? '').toString().isNotEmpty)
                      _section(
                        'Description / Rules',
                        '${policy['description']}',
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[500],
                fontFamily: 'SF Pro Display',
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1E293B),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LeavePolicyDialog extends StatefulWidget {
  final Map<String, dynamic>? existingPolicy;
  final Future<void> Function(Map<String, dynamic> data) onSave;

  const LeavePolicyDialog({
    super.key,
    this.existingPolicy,
    required this.onSave,
  });

  @override
  State<LeavePolicyDialog> createState() => _LeavePolicyDialogState();
}

class _LeavePolicyDialogState extends State<LeavePolicyDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _policyNameCtrl;
  late TextEditingController _allowedLeavesCtrl;
  late TextEditingController _carryForwardDaysCtrl;
  late TextEditingController _noticePeriodCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _startDateCtrl;
  late TextEditingController _endDateCtrl;

  String _leaveType = 'Sick';
  String _paidUnpaid = 'Paid';
  String _applicableTo = 'All Workers';
  bool _carryForward = false;
  bool _approvalRequired = false;
  bool _isSaving = false;

  final List<String> _leaveTypes = [
    'Sick',
    'Casual',
    'Medical',
    'Unpaid',
    'Annual',
    'Maternity',
    'Paternity',
    'Bereavement',
  ];

  final List<String> _paidUnpaidOptions = ['Paid', 'Unpaid', 'Half Paid'];
  final List<String> _applicableToOptions = [
    'All Workers',
    'Department',
    'Selected Workers',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingPolicy;
    _policyNameCtrl = TextEditingController(text: p?['policyName'] ?? '');
    _allowedLeavesCtrl = TextEditingController(
      text: p?['allowedLeaves']?.toString() ?? '',
    );
    _carryForwardDaysCtrl = TextEditingController(
      text: p?['carryForwardDays']?.toString() ?? '',
    );
    _noticePeriodCtrl = TextEditingController(text: p?['noticePeriod'] ?? '');
    _descriptionCtrl = TextEditingController(text: p?['description'] ?? '');
    _startDateCtrl = TextEditingController(text: p?['startDate'] ?? '');
    _endDateCtrl = TextEditingController(text: p?['endDate'] ?? '');

    if (p != null) {
      _leaveType = p['leaveType'] ?? 'Sick';
      _paidUnpaid = p['paidUnpaid'] ?? 'Paid';
      _applicableTo = p['applicableTo'] ?? 'All Workers';
      _carryForward = p['carryForward'] ?? false;
      _approvalRequired = p['approvalRequired'] ?? false;
    }
  }

  @override
  void dispose() {
    _policyNameCtrl.dispose();
    _allowedLeavesCtrl.dispose();
    _carryForwardDaysCtrl.dispose();
    _noticePeriodCtrl.dispose();
    _descriptionCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      ctrl.text = DateFormat('yyyy-MM-dd').format(date);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final data = {
        'policyName': _policyNameCtrl.text.trim(),
        'leaveType': _leaveType,
        'allowedLeaves': _allowedLeavesCtrl.text.trim(),
        'paidUnpaid': _paidUnpaid,
        'applicableTo': _applicableTo,
        'startDate': _startDateCtrl.text.trim(),
        'endDate': _endDateCtrl.text.trim(),
        'carryForward': _carryForward,
        'carryForwardDays': _carryForward
            ? int.tryParse(_carryForwardDaysCtrl.text.trim()) ?? 0
            : 0,
        'approvalRequired': _approvalRequired,
        'noticePeriod': _noticePeriodCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'pdfPath': widget.existingPolicy?['pdfPath'] ?? '',
      };
      await widget.onSave(data);
      if (mounted) {
        Navigator.pop(context);
        FlashySnackBar.show(
          context,
          message: widget.existingPolicy != null
              ? 'Policy updated successfully'
              : 'Policy saved successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Failed to save policy',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingPolicy != null;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 20, 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.policy_outlined,
                      color: Color(0xFF4F46E5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Policy' : 'Add Policy',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fieldLabel('Policy Name'),
                      _textInput(
                        _policyNameCtrl,
                        'e.g. Company Leave Policy 2026',
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Leave Type'),
                      _dropdown(_leaveType, _leaveTypes, (v) {
                        setState(() => _leaveType = v);
                      }),
                      const SizedBox(height: 16),
                      _fieldLabel('Allowed Leaves (days per year)'),
                      _numberInput(_allowedLeavesCtrl, 'e.g. 10'),
                      const SizedBox(height: 16),
                      _fieldLabel('Paid / Unpaid'),
                      _dropdown(_paidUnpaid, _paidUnpaidOptions, (v) {
                        setState(() => _paidUnpaid = v);
                      }),
                      const SizedBox(height: 16),
                      _fieldLabel('Applicable To'),
                      _dropdown(_applicableTo, _applicableToOptions, (v) {
                        setState(() => _applicableTo = v);
                      }),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Start Date'),
                                _dateInput(_startDateCtrl, 'Select date'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('End Date'),
                                _dateInput(_endDateCtrl, 'Select date'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Carry Forward'),
                      Row(
                        children: [
                          Switch(
                            value: _carryForward,
                            onChanged: (v) => setState(() => _carryForward = v),
                            activeThumbColor: const Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _carryForward ? 'Yes' : 'No',
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                      if (_carryForward) ...[
                        const SizedBox(height: 8),
                        _fieldLabel('Maximum Carry Forward Days'),
                        _numberInput(_carryForwardDaysCtrl, 'e.g. 5'),
                      ],
                      const SizedBox(height: 16),
                      _fieldLabel('Approval Required'),
                      Row(
                        children: [
                          Switch(
                            value: _approvalRequired,
                            onChanged: (v) =>
                                setState(() => _approvalRequired = v),
                            activeThumbColor: const Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _approvalRequired ? 'Yes' : 'No',
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Notice Period'),
                      _textInput(
                        _noticePeriodCtrl,
                        'e.g. Apply 2 days before leave',
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('Description / Rules'),
                      _multilineInput(
                        _descriptionCtrl,
                        'Describe your leave policy...',
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _isSaving ? null : _save,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              decoration: BoxDecoration(
                                color: _isSaving
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF4F46E5),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF4F46E5,
                                    ).withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
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
                                        isEditing
                                            ? 'Update Policy'
                                            : 'Save Policy',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
          fontFamily: 'SF Pro Display',
        ),
      ),
    );
  }

  Widget _textInput(TextEditingController ctrl, String hint) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(fontSize: 14, fontFamily: 'SF Pro Display'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: Colors.grey[400],
          fontFamily: 'SF Pro Display',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _numberInput(TextEditingController ctrl, String hint) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(fontSize: 14, fontFamily: 'SF Pro Display'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: Colors.grey[400],
          fontFamily: 'SF Pro Display',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _multilineInput(TextEditingController ctrl, String hint) {
    return TextFormField(
      controller: ctrl,
      maxLines: 4,
      minLines: 3,
      style: const TextStyle(fontSize: 14, fontFamily: 'SF Pro Display'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: Colors.grey[400],
          fontFamily: 'SF Pro Display',
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  Widget _dateInput(TextEditingController ctrl, String hint) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      onTap: () => _pickDate(ctrl),
      style: const TextStyle(fontSize: 14, fontFamily: 'SF Pro Display'),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          color: Colors.grey[400],
          fontFamily: 'SF Pro Display',
        ),
        suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _dropdown(
    String value,
    List<String> items,
    ValueChanged<String> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
