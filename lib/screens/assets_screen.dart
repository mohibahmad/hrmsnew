import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/snackbar_utils.dart';

class AssetsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;

  const AssetsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
  });

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  bool isDataEmpty = false;
  String _searchQuery = '';

  final List<AssetData> _assets = [
    AssetData(
      'Olivia Vance',
      'Web Developer',
      'Laptop',
      '01/12/2022',
      '01/12/2022',
      true,
    ),
    AssetData(
      'Sophia Smith',
      'Graphic Designer',
      'Mouse',
      '01/12/2022',
      'In use',
      false,
    ),
    AssetData(
      'Amelia Gray',
      'Engineering',
      'Keyboard',
      '01/12/2022',
      '01/12/2022',
      true,
    ),
    AssetData(
      'Olivia Vance',
      'Graphic Designer',
      'Mac',
      '01/12/2022',
      'In use',
      false,
    ),
    AssetData(
      'Lucas Johnson',
      'Web Developer',
      'Table',
      '01/12/2022',
      'In use',
      false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Automatically show the dialog after the screen renders to match the mockup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAddAssetModal(context);
    });
  }

  List<AssetData> get _filteredAssets {
    return _assets.where((asset) {
      final matchesSearch =
          asset.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          asset.type.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          asset.position.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();
  }

  void _showAddAssetModal(BuildContext context) {
    final nameController = TextEditingController(text: 'Ali Ahmad');
    final typeController = TextEditingController(text: 'Laptop');
    final positionController = TextEditingController(text: 'Graphic Designer');
    DateTime loanedDate = DateTime(2022, 2, 1);
    DateTime returnedDate = DateTime(2026, 10, 9);
    bool isReturned = true;

    // Helper to format date
    String formatDate(DateTime date) {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    }

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
              backgroundColor: Colors.white,
              elevation: 10,
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modal Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black87),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const Text(
                          'Add Asset',
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
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () {
                            if (nameController.text.isNotEmpty &&
                                typeController.text.isNotEmpty &&
                                positionController.text.isNotEmpty) {
                              setState(() {
                                _assets.insert(
                                  0,
                                  AssetData(
                                    nameController.text,
                                    positionController.text,
                                    typeController.text,
                                    formatDate(loanedDate),
                                    isReturned
                                        ? formatDate(returnedDate)
                                        : 'In use',
                                    isReturned,
                                  ),
                                );
                              });
                              Navigator.of(context).pop();
                              FlashySnackBar.show(
                                context,
                                message: 'Successfully added asset for ${nameController.text}',
                              );
                            }
                          },
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Form Fields
                    _buildModalTextField('Worker Name', nameController),
                    const SizedBox(height: 16),
                    _buildModalTextField('Asset Type', typeController),
                    const SizedBox(height: 16),
                    _buildModalTextField('Position', positionController),
                    const SizedBox(height: 16),

                    // Date Picker for Loaned Date
                    _buildModalDatePicker(
                      context,
                      'Date Loaned',
                      formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: loanedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setModalState(() {
                            loanedDate = picked;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Toggle returned vs in use
                    Row(
                      children: [
                        const Text(
                          'Has been returned?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const Spacer(),
                        Checkbox(
                          value: isReturned,
                          activeColor: const Color(0xFF0247C4),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                isReturned = val;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (isReturned) ...[
                      const SizedBox(height: 8),
                      // Date Picker for Returned Date
                      _buildModalDatePicker(
                        context,
                        'Returned Date',
                        formatDate(returnedDate),
                        Colors.red,
                        () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: returnedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            setModalState(() {
                              returnedDate = picked;
                            });
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalTextField(String label, TextEditingController controller) {
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

  Widget _buildModalDatePicker(
    BuildContext context,
    String label,
    String value,
    Color textColor,
    VoidCallback onTap,
  ) {
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
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_month,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAssets;

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
                  const SizedBox(height: 30),
                  const Text(
                    'Asset List',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 24),
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

  // ================= TOP HEADER =================

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 94,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Workforce',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage workforce equipment inventory and loaned items.',
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
          // Notification Bell
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
        // Search Bar
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
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
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search by workers or asset details',
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
        // Add Asset Button
        ElevatedButton.icon(
          onPressed: () => _showAddAssetModal(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0247C4),
            minimumSize: const Size(140, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/add asset.svg',
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          label: const Text(
            'Add Asset',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  // ================= DATA TABLE (FILLED STATE) =================

  Widget _buildDataTable(List<AssetData> assets) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          // Table Headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: _tableHeader('Worker Name')),
                Expanded(flex: 2, child: _tableHeader('Position')),
                Expanded(flex: 2, child: _tableHeader('Type')),
                Expanded(flex: 2, child: _tableHeader('Date Loaned')),
                Expanded(flex: 2, child: _tableHeader('Date Returned')),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // Table Rows
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: assets.length,
            separatorBuilder: (context, index) =>
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, index) {
              return _buildDataRow(assets[index]);
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
                      color: Colors.white,
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

  Widget _buildDataRow(AssetData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          // Name and Avatar (Placeholder image)
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
                  data.name,
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
            flex: 2,
            child: Text(
              data.position,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0F172A),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              data.type,
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
              data.dateLoaned,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
          // Date Returned (Colored)
          Expanded(
            flex: 2,
            child: Text(
              data.dateReturned,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: data.isReturned ? Colors.red : Colors.green,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= EMPTY STATE =================

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/placeholder_workers.svg',
              width: 120,
              height: 100,
            ),
            const SizedBox(height: 16),
            const Text(
              'No Assets Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0247C4),
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Try adjusting your search query or add a new asset.",
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Data Model for Assets
class AssetData {
  final String name;
  final String position;
  final String type;
  final String dateLoaned;
  final String dateReturned;
  final bool isReturned;

  AssetData(
    this.name,
    this.position,
    this.type,
    this.dateLoaned,
    this.dateReturned,
    this.isReturned,
  );
}
