import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';

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
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<Map<String, dynamic>> _payrollDocs = [];
  bool _isLoading = true;
  int _currentPage = 1;
  static const int _itemsPerPage = 4;
  StreamSubscription? _payrollSub;

  @override
  void dispose() {
    _payrollSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _payrollDocs = [];
    _isLoading = true;
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _payrollSub = FirestoreService().payrollStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _payrollDocs = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
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
      _payrollDocs = DummyData.payroll;
      _isLoading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
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
          Text(
            'workforce'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
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

  Widget _buildSearchBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
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

  List<Map<String, dynamic>> get _filteredEmployees {
    return _payrollDocs.where((doc) {
      final name = (doc['name'] ?? '').toString().toLowerCase();
      final pos = (doc['position'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || pos.contains(query);

      if (!matchesSearch) return false;
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Management') {
        return pos.contains('manag');
      }
      return pos.contains(_selectedFilter.toLowerCase());
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
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
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0D4CC6)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                filter['label']!,
                style: TextStyle(
                  color: isSelected ? Color(0xFFFFFFFF) : Colors.black,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
              'no_payroll_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text('worker_name_header'.tr(), style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('position'.tr(), style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('contact_no'.tr(), style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('payroll_data'.tr(), style: _headerStyle()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _currentPageItems.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeRow(_currentPageItems[index], index),
            ),
          ),
          const SizedBox(height: 16),
          _buildPagination(),
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
        borderRadius: BorderRadius.circular(8),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (doc['name'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
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
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (doc['position'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (doc['contact'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () {
                  _showPayrollDataDialog(context, doc);
                },
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(4),
                splashColor: const Color(0xFF0D4CC6).withValues(alpha: 0.15),
                highlightColor: const Color(0xFF0D4CC6).withValues(alpha: 0.05),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      'payroll_data'.tr(),
                      style: TextStyle(
                        color: Color(0xFF0D4CC6),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
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
    );
  }

  void _showPayrollDataDialog(BuildContext context, Map<String, dynamic> data) {
    final String name = (data['name'] ?? 'Mohib Ahmad').toString();
    final String email = (data['email'] ?? 'sarakhan65@gmail.com').toString();
    final String contact = (data['contact'] ?? '123 5434567').toString();
    final String status = (data['status'] ?? 'Active').toString();
    final String totalWorkDays = (data['totalWorkDays'] ?? '224').toString();
    final String absents = (data['absents'] ?? '09').toString();
    final String leaves = (data['leaves'] ?? '05').toString();
    final String overtimeDays = (data['overtimeDays'] ?? '08').toString();
    final String salary = (data['salary'] ?? '\$ 50,000').toString();

    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 500 ? screenWidth * 0.9 : 480.0;

    showDialog(
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
                // Top Header AppBar (Height: 40, Color: #004FDE)
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
                      const SizedBox(width: 40), // Spacer for centering
                      Flexible(
                        child: Text(
                          'payroll_data_preview'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFFFFFFFF),
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
                // Profile Section (Blue backdrop: #0247C4)
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
                          image: const DecorationImage(
                            image: AssetImage('assets/profileimage.png'),
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
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: Color(0xFFFFFFFF),
                                  size: 18,
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
                // White Bottom Section (5 Metric Cards, bordered sides)
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
                              const Expanded(child: SizedBox()),
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
        borderRadius: BorderRadius.circular(8),
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
                  overflow: TextOverflow.ellipsis,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D4CC6),
            borderRadius: BorderRadius.circular(4),
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
