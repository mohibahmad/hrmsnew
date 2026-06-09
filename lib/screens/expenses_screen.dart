import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';

class ExpensesScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;

  const ExpensesScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool isDataEmpty = false;
  String _searchQuery = '';
  List<QueryDocumentSnapshot> _expensesDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    FirestoreService().expensesStream.listen((snapshot) {
      if (mounted) {
        setState(() {
          _expensesDocs = snapshot.docs;
          _isLoading = false;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddExpenseModal(context);
    });
  }

  double get _totalExpenseSum {
    if (isDataEmpty) return 0.0;
    return _filteredExpenses.fold(0.0, (sum, doc) {
      final data = doc.data() as Map<String, dynamic>;
      return sum + ((data['amount'] ?? 0).toDouble());
    });
  }

  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(symbol: '\$ ', decimalDigits: 2);
    return format.format(amount);
  }

  List<QueryDocumentSnapshot> get _filteredExpenses {
    return _expensesDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final category = (data['category'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || category.contains(query);
    }).toList();
  }

  Future<void> _deleteExpense(String docId) async {
    await FirestoreService().deleteExpense(docId);
  }

  void _showAddExpenseModal(BuildContext context) {
    final categoryController = TextEditingController(text: 'Dinner');
    final amountController = TextEditingController(text: '0.00');
    final descriptionController = TextEditingController(
      text: 'Client meeting dinner',
    );
    int selectedDay = 1;

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
                    // === Modal Header ===
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.black87,
                            size: 20,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const Text(
                          'Add Expense',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          onPressed: () {
                            final double? amt = double.tryParse(
                              amountController.text,
                            );
                            if (categoryController.text.isNotEmpty &&
                                amt != null) {
                              final dateStr =
                                  '${selectedDay.toString().padLeft(2, '0')}/05/2025';
                              FirestoreService().addExpense({
                                'name': 'Ali Ahmad',
                                'date': dateStr,
                                'category': categoryController.text,
                                'amount': amt,
                              });
                              Navigator.of(context).pop();
                              FlashySnackBar.show(
                                context,
                                message: 'Successfully added expense "${categoryController.text}"',
                              );
                            }
                          },
                          child: const Text(
                            'Save',
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

                    // === Modal Form Rows ===
                    Row(
                      children: [
                        Expanded(
                          child: _buildModalTextField(
                            'Expense Category',
                            categoryController,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalTextField(
                            'Amount (\$)',
                            amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
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
                              const Text(
                                'Expense Title',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
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
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: TextField(
                                  controller: descriptionController,
                                  maxLines: null,
                                  decoration: const InputDecoration.collapsed(
                                    hintText: '',
                                  ),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModalCalendar(selectedDay, (day) {
                            setModalState(() {
                              selectedDay = day;
                            });
                          }),
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
  }

  Widget _buildModalTextField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: const InputDecoration.collapsed(hintText: ''),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModalCalendar(int selectedDay, ValueChanged<int> onDaySelected) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.chevron_left, size: 16, color: Colors.black87),
              SizedBox(width: 16),
              Text(
                'MAY 2025',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(width: 16),
              Icon(Icons.chevron_right, size: 16, color: Colors.black87),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildWeekday('SUN', Colors.red)),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('MON', const Color(0xFF0247C4))),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('TUE', const Color(0xFF0247C4))),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('WED', const Color(0xFF0247C4))),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('THU', const Color(0xFF0247C4))),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('FRI', const Color(0xFF4CAF50))),
              const SizedBox(width: 4),
              Expanded(child: _buildWeekday('SAT', const Color(0xFF0247C4))),
            ],
          ),
          const SizedBox(height: 8),
          _buildDaysGrid(selectedDay, onDaySelected),
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

  Widget _buildDaysGrid(int selectedDay, ValueChanged<int> onDaySelected) {
    List<Widget> rows = [];
    int currentDay = 1;

    for (int i = 0; i < 5; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        if (i == 0 && j == 0) {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        } else if (currentDay <= 31) {
          final day = currentDay;
          rowChildren.add(
            Expanded(
              child: _buildDayCell(
                '$day',
                day == selectedDay,
                () => onDaySelected(day),
              ),
            ),
          );
          currentDay++;
        } else {
          rowChildren.add(Expanded(child: _buildDayCell('', false, null)));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 4));
      }
      rows.add(Row(children: rowChildren));
      if (i < 4) rows.add(const SizedBox(height: 4));
    }
    return Column(children: rows);
  }

  Widget _buildDayCell(String day, bool isSelected, VoidCallback? onTap) {
    if (day.isEmpty) return const SizedBox();
    return AspectRatio(
      aspectRatio: 1.1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.red : Colors.transparent,
            border: Border.all(
              color: isSelected ? Colors.red : Colors.grey.shade300,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            day,
            style: TextStyle(
              color: isSelected ? Color(0xFFFFFFFF) : Colors.black87,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
                  isDataEmpty || filtered.isEmpty
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

  // ================= MAIN CONTENT =================

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
            children: const [
              Text(
                'Expenses',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage workforce expenses and company disbursements.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          const Spacer(),
          SvgPicture.asset(
            'assets/notification_icon.svg',
            height: 24,
            width: 24,
            colorFilter: const ColorFilter.mode(
              Color(0xFF0F172A),
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

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
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
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by workers or categories',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 14,
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
                      });
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
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: () => _showAddExpenseModal(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            minimumSize: const Size(150, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/add_expense.svg',
            width: 18,
            height: 18,
            colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn),
          ),
          label: const Text(
            'Add Expenses',
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
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
            title: 'This Month Expense',
            titleColor: const Color(0xFF0247C4),
            amount: _formatCurrency(_totalExpenseSum),
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
            title: 'Total Expense',
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
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
              ),
              const SizedBox(height: 12),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ],
          ),
          iconWidget,
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Expenses List',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            fontFamily: 'SF Pro Display',
          ),
        ),
        _buildTodayDropdown(),
      ],
    );
  }

  Widget _buildTodayDropdown() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0247C4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: const [
            Text(
              'Today',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, color: Color(0xFFFFFFFF), size: 20),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _buildPopupItem('Week', isSelected: true),
        _buildPopupItem('Month'),
        _buildPopupItem('3 Month'),
        _buildPopupItem('6 Month'),
        _buildPopupItem('Yearly'),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupItem(
    String text, {
    bool isSelected = false,
  }) {
    return PopupMenuItem<String>(
      value: text,
      height: 36,
      child: Row(
        children: [
          Icon(
            isSelected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isSelected ? const Color(0xFF0247C4) : Colors.grey.shade400,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFF0247C4)
                  : Colors.grey.shade500,
              fontSize: 13,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ],
      ),
    );
  }

  // ================= FILLED STATE (LIST) =================

  Widget _buildDataTable(List<QueryDocumentSnapshot> expenses) {
    return Container(
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: _tableHeader('Worker Name')),
                Expanded(flex: 3, child: _tableHeader('Date')),
                Expanded(flex: 3, child: _tableHeader('Expense Category')),
                Expanded(flex: 2, child: _tableHeader('Amount')),
                const SizedBox(width: 48), // Space for action icon
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: expenses.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, index) {
              return _buildDataRow(expenses[index]);
            },
          ),
          const SizedBox(height: 16),
          // Pagination
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.chevron_left, color: Colors.black54),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.black54),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 15,
        color: Color(0xFF0F172A),
        fontFamily: 'SF Pro Display',
      ),
    );
  }

  Widget _buildDataRow(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data['name'] ?? '').toString();
    final date = (data['date'] ?? '').toString();
    final category = (data['category'] ?? '').toString();
    final amount = (data['amount'] ?? 0).toDouble();
    final docId = doc.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage('assets/profile_placeholder.png'),
                ),
                const SizedBox(width: 12),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              date,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              category,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatCurrency(amount),
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0247C4),
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          _buildActionMenu(docId),
        ],
      ),
    );
  }

  Widget _buildActionMenu(String docId) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black87),
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 4,
      onSelected: (value) {
        if (value == 'delete') {
          _deleteExpense(docId);
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
              const Text(
                'Edit Expense',
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
              const Text(
                'Delete',
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
    );
  }

  // ================= EMPTY STATE =================

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            SvgPicture.asset(
              'assets/placeholder_workers.svg',
              width: 120,
              height: 100,
            ),
            const SizedBox(height: 16),
            const Text(
              'Add expenses found',
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
    );
  }
}

class ExpenseItem {
  final String name;
  final String date;
  final String category;
  final double amount;

  ExpenseItem(this.name, this.date, this.category, this.amount);
}
