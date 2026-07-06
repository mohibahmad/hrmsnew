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
  int _currentPage = 1;
  static const int _itemsPerPage = 8;
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
    _payrollDocs = PayrollService.combinePayroll(_workersList, _rawPayrollDocs);
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
                  const SizedBox(height: 30),
                  Text(
                    'pay_roll_list'.tr(),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterTabs(),
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
          GestureDetector(
            onTap: widget.onProfileTap,
            child: const UserAvatar(),
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
                  _currentPage = 1;
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
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _currentPage = 1;
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
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
      return pos.contains('designer') &&
          !pos.contains('engineer') &&
          !pos.contains('developer');
    } else if (f == 'developer') {
      return (pos.contains('developer') || pos.contains('development')) &&
          !pos.contains('designer');
    } else if (f == 'engineering') {
      return (pos.contains('engineer') ||
              pos.contains('architect') ||
              pos.contains('analyst') ||
              pos.contains('scientist')) &&
          !pos.contains('designer') &&
          !pos.contains('developer');
    } else if (f == 'sales') {
      return pos.contains('sales') || pos.contains('marketing');
    } else if (f == 'management') {
      return pos.contains('manager') ||
          pos.contains('writer') ||
          pos.contains('hr');
    }
    return false;
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    return _payrollDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final pos = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || pos.contains(query);

      if (!matchesSearch) return false;
      return _matchesFilter(pos, _selectedFilter);
    }).toList();
  }

  List<Map<String, dynamic>> get _currentPageItems {
    final filtered = _filteredEmployees;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    if (startIndex >= filtered.length) return [];
    final endIndex = startIndex + _itemsPerPage;
    return filtered.sublist(
      startIndex,
      endIndex > filtered.length ? filtered.length : endIndex,
    );
  }

  int get _totalPages {
    final filtered = _filteredEmployees;
    if (filtered.isEmpty) return 1;
    return (filtered.length / _itemsPerPage).ceil();
  }

  Widget _buildFilterTabs() {
    final filters = <Map<String, String>>[
      {'key': 'All', 'label': 'all_filter'.tr()},
      {'key': 'Designer', 'label': 'designer'.tr()},
      {'key': 'Developer', 'label': 'developer'.tr()},
      {'key': 'Engineering', 'label': 'engineering'.tr()},
      {'key': 'Sales', 'label': 'sales'.tr()},
      {'key': 'Management', 'label': 'management'.tr()},
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter['key'];
          return GestureDetector(
            onTap: () => setState(() {
              _selectedFilter = filter['key']!;
              _currentPage = 1;
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: EdgeInsets.symmetric(horizontal: isSelected ? 12 : 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0D4CC6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                filter['label']!,
                style: TextStyle(
                  color: isSelected
                      ? Color(0xFFFFFFFF)
                      : const Color(0xFF000000),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          );
        }).toList(),
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
              isSearchEmpty ? 'no_search_results'.tr() : 'no_payroll_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
            if (isSearchEmpty) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => setState(() { _searchQuery = ''; _currentPage = 1; }),
                icon: const Icon(Icons.close, size: 16),
                label: Text('clear_search'.tr()),
              ),
            ],
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
              itemCount: _currentPageItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeRow(_currentPageItems[index], index),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: _buildPagination(),
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
                  final isPaid = (doc['status'] ?? '').toString().toLowerCase() == 'paid';
                  final hasData = (doc['totalWorkDays'] ?? '').toString().isNotEmpty;
                  return InkWell(
                    onTap: () {
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isPaid ? const Color(0xFF27AE60) : const Color(0xFFE74C3C),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isPaid ? 'paid'.tr() : 'pay'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF0247C4),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                      ],
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

  void _showPayrollDataDialog(BuildContext context, Map<String, dynamic> data, int index) async {
    final String name = (data['name'] ?? '').toString();
    final String email = (data['email'] ?? '').toString();
    final String contact = (data['contact'] ?? '').toString();
    final String status = (data['status'] ?? 'Active').toString();
    final String totalWorkDays = (data['totalWorkDays'] ?? '').toString();
    final String absents = (data['absents'] ?? '').toString();
    final String leaves = (data['leaves'] ?? '').toString();
    final String overtimeDays = (data['overtimeDays'] ?? '').toString();
    final String salary = (data['salary'] ?? '').toString();
    String salaryAfterDeductionStr =
        (data['netSalary'] ?? data['salaryAfterDeduction'] ?? '').toString();
    if (salaryAfterDeductionStr.isEmpty && salary.isNotEmpty) {
      salaryAfterDeductionStr = PayrollService.getNetSalaryDisplay(
        salary: salary,
        totalWorkDays: totalWorkDays,
        absents: absents,
        overtimeDays: overtimeDays,
      );
    }

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
                                  icon: const Icon(
                                    Icons.person,
                                    color: Color(0xFF004FDE),
                                    size: 20,
                                  ),
                                  title: 'total_work_days'.tr(),
                                  value: totalWorkDays,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildAbsentsIcon(),
                                  title: 'absents_label'.tr(),
                                  value: absents,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildLeavesIcon(),
                                  title: 'leaves_label'.tr(),
                                  value: leaves,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildOvertimeDaysIcon(),
                                  title: 'overtime_days'.tr(),
                                  value: overtimeDays,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
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
                              const SizedBox(width: 12),
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

  Widget _buildPagination() {
    final total = _totalPages;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: _currentPage > 1 ? () => setState(() => _currentPage--) : null,
          behavior: HitTestBehavior.opaque,
          child: Icon(
            Icons.chevron_left,
            color: _currentPage > 1 ? Colors.black : Colors.grey.shade400,
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
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _currentPage < total
              ? () => setState(() => _currentPage++)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Icon(
            Icons.chevron_right,
            color: _currentPage < total ? Colors.black : Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}
