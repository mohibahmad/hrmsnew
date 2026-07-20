import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/payroll_service.dart';
import '../utils/image_utils.dart';
import 'add_payroll_screen.dart';
import '../widgets/notification_bell.dart';
import '../widgets/amount_text.dart';
import 'login_screen.dart';

class PayrollScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onAssignTimeOff;
  final VoidCallback? onNotificationTap;

  const PayrollScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
    this.onNotificationTap,
  });

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _payrollDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawPayrollDocs = [];
  bool _isLoading = true;

  static const _defaultFilters = [
    'All',
    'Designer',
    'Developer',
    'Engineering',
    'Sales',
    'Management',
  ];
  StreamSubscription? _payrollSub;
  StreamSubscription? _workersSub;

  bool _isAddingPayroll = false;
  Map<String, dynamic>? _workerForPayroll;

  @override
  void dispose() {
    _payrollSub?.cancel();
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _combinePayroll() {
    // 🔥 FIX: Ensure every worker has payroll data
    _payrollDocs = PayrollService.combinePayroll(_workersList, _rawPayrollDocs);

    // 🔥 ADD THIS: Fix unpaid workers
    for (var doc in _payrollDocs) {
      if (doc['totalWorkDays'] == null ||
          doc['totalWorkDays'].toString().isEmpty) {
        doc['status'] = 'Unpaid';
        doc['totalWorkDays'] = '0';
        doc['absents'] = '0';
        doc['leaves'] = '0';
        doc['overtimeAmount'] = '0';
        doc['salary'] = doc['salary'] ?? '\$ 0';
        doc['netSalary'] = '\$ 0';
      }
    }
    _isLoading = false;
  }

  @override
  void initState() {
    super.initState();
    _payrollDocs = [];
    _workersList = [];
    _rawPayrollDocs = [];
    _isLoading = true;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = FirestoreService().workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workersList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _combinePayroll();
          });
        }
      });
      _payrollSub = FirestoreService().payrollStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _rawPayrollDocs = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _combinePayroll();
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
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawPayrollDocs = List<Map<String, dynamic>>.from(DummyData.payroll);
      _combinePayroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAddingPayroll && _workerForPayroll != null) {
      return AddPayrollScreen(
        workerData: _workerForPayroll!,
        onNotificationTap: widget.onNotificationTap,
        onProfileTap: widget.onProfileTap,
        onBack: () {
          setState(() {
            _isAddingPayroll = false;
            _workerForPayroll = null;
          });
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 10),

                  const SizedBox(height: 10),
                  _buildFilterTabs(),
                  const SizedBox(height: 10),
                  Text(
                    'pay_roll_list'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 24),

                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 80),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (_filteredEmployees.isEmpty
                            ? _buildEmptyState()
                            : _buildTable()),
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
              Text(
                'workforce'.tr(),
                style: TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onProfileTap,
              child: const UserAvatar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 50,
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
            width: 24,
            height: 24,
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
                hintText: 'search_by_workers_name'.tr(),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _matchesFilter(String position, String filter) {
    if (filter == 'All') return true;
    final pos = position.toLowerCase();
    final f = filter.toLowerCase();
    if (f == 'designer') {
      return pos.contains('designer') ||
          pos.contains('design lead') ||
          pos.contains('creative director') ||
          pos.contains('ui') ||
          pos.contains('ux') ||
          pos.contains('graphic') ||
          pos.contains('visual');
    } else if (f == 'developer') {
      return pos.contains('developer') ||
          pos.contains('programmer') ||
          pos.contains('coder') ||
          pos.contains('software') ||
          pos.contains('frontend') ||
          pos.contains('backend') ||
          pos.contains('full stack') ||
          pos.contains('fullstack');
    } else if (f == 'engineering') {
      return pos.contains('engineer') ||
          pos.contains('architect') ||
          pos.contains('devops') ||
          pos.contains('cloud') ||
          pos.contains('data') ||
          pos.contains('scientist') ||
          pos.contains('machine learning') ||
          pos.contains('ml') ||
          pos.contains('qa') ||
          pos.contains('tester') ||
          pos.contains('it support') ||
          pos.contains('network') ||
          pos.contains('database') ||
          pos.contains('dba') ||
          pos.contains('cyber') ||
          pos.contains('security') ||
          pos.contains('cto') ||
          pos.contains('chief technology');
    } else if (f == 'sales') {
      return pos.contains('sales') ||
          pos.contains('marketing') ||
          pos.contains('seo') ||
          pos.contains('content') ||
          pos.contains('social media') ||
          pos.contains('brand') ||
          pos.contains('business development') ||
          pos.contains('account executive') ||
          pos.contains('customer success');
    } else if (f == 'management') {
      return pos.contains('manager') ||
          pos.contains('director') ||
          pos.contains('head') ||
          pos.contains('lead') ||
          pos.contains('chief') ||
          pos.contains('cpo') ||
          pos.contains('product') ||
          pos.contains('project') ||
          pos.contains('program') ||
          pos.contains('scrum') ||
          pos.contains('agile') ||
          pos.contains('business analyst');
    }
    return pos.contains(f) || f.contains(pos);
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final filtered = _payrollDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final pos = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || pos.contains(query);

      if (!matchesSearch) return false;
      return _matchesFilter(pos, _selectedFilter);
    }).toList();

    // Sort: Paid workers at top, then Unpaid
    filtered.sort((a, b) {
      final statusA = (a['status'] ?? '').toString();
      final statusB = (b['status'] ?? '').toString();
      if (statusA == 'Paid' && statusB != 'Paid') return -1;
      if (statusA != 'Paid' && statusB == 'Paid') return 1;
      return 0;
    });

    return filtered;
  }

  List<String> get _extraPositions {
    final existing = _defaultFilters.map((e) => e.toLowerCase()).toSet();
    final extras = <String>{};
    for (final doc in _workersList) {
      final pos = (doc['position'] ?? '').toString().trim();
      if (pos.isNotEmpty && !existing.contains(pos.toLowerCase())) {
        extras.add(pos);
      }
    }
    final sorted = extras.toList()..sort();
    return sorted;
  }

  Widget _buildFilterTabs() {
    final filters = <Map<String, String>>[
      {'key': 'All', 'label': 'all_filter'.tr()},
      {'key': 'Designer', 'label': 'designer'.tr()},
      {'key': 'Developer', 'label': 'developer'.tr()},
      {'key': 'Engineering', 'label': 'engineering'.tr()},
      {'key': 'Sales', 'label': 'sales'.tr()},
      {'key': 'Management', 'label': 'management'.tr()},
      ..._extraPositions.map((pos) => {'key': pos, 'label': pos}),
    ];
    return Container(
      width: 550,
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < filters.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 38,
                  color: Color(0xFFE0E0E0).withValues(alpha: 0.5),
                ),
              _buildFilterTab(filters[i]['key']!, filters[i]['label']!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTab(String filterKey, String displayLabel) {
    final bool isSelected = _selectedFilter == filterKey;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedFilter = filterKey;
      }),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 12 : 16,
          vertical: 8,
        ),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0D4CC6) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          displayLabel,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: TextStyle(
            color: isSelected ? Color(0xFFFFFFFF) : const Color(0xFF000000),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    double dynamicHeight = MediaQuery.of(context).size.height - 450;
    if (dynamicHeight < 300) dynamicHeight = 300;
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
              isSearchEmpty
                  ? 'no_search_results'.tr()
                  : 'no_payroll_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable() {
    final double tableHeight = (MediaQuery.of(context).size.height - 329).clamp(
      440.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
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
                    child: Text(
                      'worker_name_header'.tr(),
                      style: _headerStyle(),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text('position'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Text('contact_no'.tr(), style: _headerStyle()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Text('status_header'.tr(), style: _headerStyle()),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _filteredEmployees.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeRow(_filteredEmployees[index], index),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle() {
    return const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.black,
      fontFamily: 'SF Pro Display',
    );
  }

  Widget _buildEmployeeRow(Map<String, dynamic> doc, int index) {
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
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.transparent,
                    backgroundImage: getProfileImage(
                      doc['profileImage']?.toString(),
                      doc['email']?.toString(),
                      index,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (doc['name'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (doc['email'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                            fontFamily: 'SF Pro Display',
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
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Text(
                (doc['position'] ?? '').toString(),
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black,
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 2,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 24.0),
              child: Text(
                (doc['phone'] ?? doc['contact'] ?? '').toString(),
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black,
                  fontFamily: 'SF Pro Display',
                ),
                maxLines: 1,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (context) {
                  final isPaid =
                      (doc['status'] ?? '').toString().toLowerCase() == 'paid';
                  final hasData = (doc['totalWorkDays'] ?? '')
                      .toString()
                      .isNotEmpty;
                  return InkWell(
                    onTap: () {
                      final isGuest =
                          AuthService().currentUser?.isAnonymous ?? false;
                      if (isGuest) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                        return;
                      }
                      if (isPaid && hasData) {
                        _showPayrollDataDialog(context, doc, index);
                      } else {
                        setState(() {
                          _isAddingPayroll = true;
                          _workerForPayroll = doc;
                        });
                      }
                    },
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(6),
                    child: Text(
                      isPaid ? 'paid'.tr() : 'pay'.tr(),
                      style: TextStyle(
                        color: isPaid
                            ? const Color(0xFF27AE60)
                            : const Color(0xFFE74C3C),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPayrollDataDialog(
    BuildContext context,
    Map<String, dynamic> data,
    int index,
  ) async {
    final String name = (data['name'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String contact = (data['contact'] ?? '').toString();
    final String status = (data['status'] ?? 'Active').toString();
    final String totalWorkDays = (data['totalWorkDays'] ?? '').toString();
    final String absents = (data['absents'] ?? '').toString();
    final String leaves = (data['leaves'] ?? '').toString();
    final String overtimeAmount = (data['overtimeAmount'] ?? '').toString();
    final String salary = AmountText.formatCompact(
      (data['salary'] ?? '').toString(),
    );
    String salaryAfterDeductionStr =
        (data['netSalary'] ?? data['salaryAfterDeduction'] ?? '').toString();
    if (salaryAfterDeductionStr.isEmpty && salary.isNotEmpty) {
      salaryAfterDeductionStr = PayrollService.getNetSalaryDisplay(
        salary: (data['salary'] ?? '').toString(),
        totalWorkDays: totalWorkDays,
        absents: absents,
        overtimeAmount: overtimeAmount,
        salaryType: (data['salaryType'] ?? 'Monthly').toString(),
      );
    }
    salaryAfterDeductionStr = AmountText.formatCompact(salaryAfterDeductionStr);

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.9 : 480.0;

    final result = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: Container(
            width: dialogWidth,
            height: 480,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF000000).withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  height: 40,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF004FDE),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Icon(
                            Icons.close,
                            color: Color(0xFFFFFFFF),
                            size: 24,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          'payroll_data_preview'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop('edit'),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: SvgPicture.asset(
                            'assets/edit_icon.svg',
                            height: 20,
                            width: 20,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFFFFFFFF),
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: const Color(0xFF0247C4),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(0xFFFFFFFF),
                            width: 2,
                          ),
                          image: DecorationImage(
                            image: getProfileImage(
                              data['profileImage']?.toString(),
                              data['email']?.toString(),
                              index,
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SF Pro Display',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Color(0xFFFFFFFF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.circle,
                                    color: Color(0xFF00FF00),
                                    size: 10,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    status,
                                    style: const TextStyle(
                                      color: Color(0xFF0247C4),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.mail_outline,
                                  color: Color(0xFFFFFFFF),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    email,
                                    style: const TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.phone,
                                    color: Color(0xFFFFFFFF),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    contact,
                                    style: const TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      border: Border(
                        left: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        right: BorderSide(color: Color(0xFFE8E8E8), width: 1.5),
                        bottom: BorderSide(
                          color: Color(0xFFE8E8E8),
                          width: 1.5,
                        ),
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(6),
                      ),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildAbsentsIcon(),
                                  title: 'absents_label'.tr(),
                                  value: absents,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildLeavesIcon(),
                                  title: 'leaves_label'.tr(),
                                  value: leaves,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: const Icon(
                                    Icons.payments,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'salary'.tr(),
                                  value: salary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: const Icon(
                                    Icons.account_balance_wallet,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'salary_after_deduction'.tr(),
                                  value: salaryAfterDeductionStr,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildOvertimeDaysIcon(),
                                  title: 'overtime_amount'.tr(),
                                  value: overtimeAmount,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == 'edit' && mounted) {
      setState(() {
        _isAddingPayroll = true;
        _workerForPayroll = data;
      });
    }
  }

  Widget _buildMetricCard({
    required Widget icon,
    required String title,
    required String value,
  }) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE8E8E8), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE5EEFC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF000000),
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsentsIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.person, color: Color(0xFF004FDE), size: 20),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE5EEFC),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(0.5),
            child: const Icon(Icons.cancel, color: Color(0xFF004FDE), size: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildLeavesIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.person, color: Color(0xFF004FDE), size: 20),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE5EEFC),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(0.5),
            child: const Icon(
              Icons.remove_circle,
              color: Color(0xFF004FDE),
              size: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOvertimeDaysIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.watch_later, color: Color(0xFF004FDE), size: 20),
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE5EEFC),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(0.5),
            child: const Icon(
              Icons.add_circle,
              color: Color(0xFF004FDE),
              size: 10,
            ),
          ),
        ),
      ],
    );
  }
}
