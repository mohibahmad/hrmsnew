import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/firestore_service.dart';

class PayrollScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onAssignTimeOff;

  const PayrollScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onAssignTimeOff,
  });

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  List<QueryDocumentSnapshot> _payrollDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    FirestoreService().payrollStream.listen((snapshot) {
      if (mounted) {
        setState(() {
          _payrollDocs = snapshot.docs;
          _isLoading = false;
        });
      }
    });
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
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 24),
                  const Text(
                    'Pay Roll List',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFilterTabs(),
                  const SizedBox(height: 24),
                  _buildTable(),
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
          const Text(
            'Workforce',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF000000),
              fontFamily: 'SF Pro Display',
            ),
          ),
          const Spacer(),
          SvgPicture.asset(
            'assets/notification_icon.svg',
            height: 24,
            width: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFF000000),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: widget.onProfileTap,
            child: CircleAvatar(
              radius: 19,
              backgroundImage: const AssetImage('assets/profileimage.png'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        decoration: InputDecoration(
          border: InputBorder.none,
          icon: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SvgPicture.asset(
              'assets/search icon.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.srcIn),
            ),
          ),
          hintText: 'Search by workers',
          hintStyle: const TextStyle(color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  child: const Icon(Icons.close, size: 18, color: Colors.grey),
                )
              : null,
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot> get _filteredEmployees {
    return _payrollDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final pos = (data['position'] ?? '').toString().toLowerCase();
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

  Widget _buildFilterTabs() {
    final filters = [
      'All',
      'Designer',
      'Developer',
      'Engineering',
      'Sales',
      'Management',
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
          final isSelected = _selectedFilter == filter;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter),
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
                filter,
                style: TextStyle(
                  color: isSelected ? Color(0xFFFFFFFF) : Colors.black87,
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

  Widget _buildTable() {
    return Container(
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
                  child: Text('Worker Name', style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Position', style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Contact no', style: _headerStyle()),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Time Off', style: _headerStyle()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_filteredEmployees.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      "No Employees Found",
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Try adjusting your filters.",
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _filteredEmployees.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _buildEmployeeRow(_filteredEmployees[index]),
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
      color: Colors.black87,
      fontFamily: 'SF Pro Display',
    );
  }

  Widget _buildEmployeeRow(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
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
                  backgroundImage: const AssetImage(
                    'assets/profile_placeholder.png',
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['name'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      (data['email'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
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
              (data['position'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              (data['contact'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  if (widget.onAssignTimeOff != null) {
                    widget.onAssignTimeOff!();
                  } else {
                    _showPayrollDataDialog(context, data);
                  }
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text(
                  'Payroll Data',
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
        ],
      ),
    );
  }

  void _showPayrollDataDialog(BuildContext context, Map<String, dynamic> data) {
    final String name = data['name'] ?? 'Mohib Ahmad';
    final String email = data['email'] ?? 'sarakhan65@gmail.com';
    final String contact = data['contact'] ?? '123 5434567';
    final String status = data['status'] ?? 'Active';
    final String totalWorkDays = data['totalWorkDays'] ?? '224';
    final String absents = data['absents'] ?? '09';
    final String leaves = data['leaves'] ?? '05';
    final String overtimeDays = data['overtimeDays'] ?? '08';
    final String salary = data['salary'] ?? '\$ 50,000';

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
                      const Flexible(
                        child: Text(
                          'PayRoll Data Preview',
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
                          border: Border.all(color: Color(0xFFFFFFFF), width: 2),
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
                                  title: 'Total Work Days',
                                  value: totalWorkDays,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildAbsentsIcon(),
                                  title: 'Absents',
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
                                  title: 'Leaves',
                                  value: leaves,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildMetricCard(
                                  icon: _buildOvertimeDaysIcon(),
                                  title: 'Overtime Days',
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
                                  title: 'Salary',
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
                    color: Colors.black54,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Icon(Icons.chevron_left, color: Colors.black54),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0D4CC6),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('1', style: TextStyle(color: Color(0xFFFFFFFF))),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: Colors.black54),
      ],
    );
  }
}
