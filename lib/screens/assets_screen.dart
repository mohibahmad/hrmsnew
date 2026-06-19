import 'dart:async';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/snackbar_utils.dart';
import '../utils/delete_dialog.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import 'package:easy_localization/easy_localization.dart';

class AssetsScreen extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const AssetsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  bool isDataEmpty = false;
  String _searchQuery = '';
  int _currentPage = 1;
  static const int _itemsPerPage = 5;

  List<AssetData> _assets = [];
  bool _isLoading = false;
  StreamSubscription? _assetsSub;

  @override
  void dispose() {
    _assetsSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _assets = DummyData.assets.map((data) {
        return AssetData(
          data['name'] ?? '',
          data['position'] ?? '',
          data['type'] ?? '',
          data['dateLoaned'] ?? '',
          data['dateReturned'] ?? '',
          data['isReturned'] ?? false,
        );
      }).toList();
    } else {
      _isLoading = true;
      _assetsSub = FirestoreService().assetsStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              final sortedDocs = snapshot.docs.toList();
              sortedDocs.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;
                final aTime = aData['createdAt'];
                final bTime = bData['createdAt'];
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return -1;
                if (bTime == null) return 1;
                if (aTime is Timestamp && bTime is Timestamp) {
                  return bTime.compareTo(aTime);
                }
                return 0;
              });
              _assets = sortedDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return AssetData(
                  data['name'] ?? '',
                  data['position'] ?? '',
                  data['type'] ?? '',
                  data['dateLoaned'] ?? '',
                  data['dateReturned'] ?? '',
                  data['isReturned'] ?? false,
                  id: doc.id,
                );
              }).toList();
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
    }
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
    final nameController = TextEditingController();
    final typeController = TextEditingController();
    final positionController = TextEditingController();
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
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Color(0xFFFFFFFF),
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
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          'add_asset'.tr(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () async {
                            if (nameController.text.isNotEmpty &&
                                typeController.text.isNotEmpty &&
                                positionController.text.isNotEmpty) {
                              final assetMap = {
                                'name': nameController.text,
                                'position': positionController.text,
                                'type': typeController.text,
                                'dateLoaned': formatDate(loanedDate),
                                'dateReturned': isReturned
                                    ? formatDate(returnedDate)
                                    : 'in_use'.tr(),
                                'isReturned': isReturned,
                              };
                              final isGuest =
                                  AuthService().currentUser?.isAnonymous ??
                                  false;
                              if (isGuest) {
                                final newAsset = {
                                  'name': nameController.text,
                                  'position': positionController.text,
                                  'type': typeController.text,
                                  'dateLoaned': formatDate(loanedDate),
                                  'dateReturned': isReturned
                                  ? formatDate(returnedDate)
                                  : 'in_use'.tr(),
                              'isReturned': isReturned,
                            };
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
                                      : 'in_use'.tr(),
                                      isReturned,
                                    ),
                                  );
                                  DummyData.assets.insert(0, newAsset);
                                });
                              } else {
                                await FirestoreService().addAsset(assetMap);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              FlashySnackBar.show(
                                context,
                                message: 'successfully_added_asset'.tr(
                                  namedArgs: {'name': nameController.text},
                                ),
                              );
                            }
                          },
                          child: Text(
                            'save'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Form Fields
                    _buildModalTextField(
                      'worker_name'.tr(),
                      nameController,
                      'worker_name_hint'.tr(),
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'asset_type'.tr(),
                      typeController,
                      'asset_type_hint'.tr(),
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'position'.tr(),
                      positionController,
                      'position_hint'.tr(),
                    ),
                    const SizedBox(height: 16),

                    // Date Picker for Loaned Date
                    _buildModalDatePicker(
                      context,
                      'date_loaned'.tr(),
                      formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () {
                        showDialog(
                          context: context,
                          barrierColor: Colors.black.withValues(alpha: 0.3),
                          builder: (BuildContext context) {
                            DateTime tempDate = loanedDate;
                            return Dialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              backgroundColor: Colors.white,
                              child: Container(
                                width: 320,
                                height: 320,
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Text(
                                      'select_date'.tr(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: CupertinoDatePicker(
                                        mode: CupertinoDatePickerMode.date,
                                        initialDateTime: tempDate,
                                        minimumYear: 2020,
                                        maximumYear: 2030,
                                        onDateTimeChanged: (DateTime picked) {
                                          tempDate = picked;
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          child: Text(
                                            'cancel'.tr(),
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(
                                              0xFF0247C4,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                          child: Text(
                                            'ok'.tr(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                          onPressed: () {
                                            setModalState(() {
                                              loanedDate = tempDate;
                                            });
                                            Navigator.of(context).pop();
                                          },
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
                    ),
                    const SizedBox(height: 16),

                    // Toggle returned vs in use
                    Row(
                      children: [
                        Text(
                          'has_been_returned'.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000000),
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
                        'returned_date'.tr(),
                        formatDate(returnedDate),
                        Colors.red,
                        () {
                          showDialog(
                            context: context,
                            barrierColor: Colors.black.withValues(alpha: 0.3),
                            builder: (BuildContext context) {
                              DateTime tempDate = returnedDate;
                              return Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                backgroundColor: Colors.white,
                                child: Container(
                                  width: 320,
                                  height: 320,
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      Text(
                                        'select_date'.tr(),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Expanded(
                                        child: CupertinoDatePicker(
                                          mode: CupertinoDatePickerMode.date,
                                          initialDateTime: tempDate,
                                          minimumYear: 2020,
                                          maximumYear: 2030,
                                          onDateTimeChanged: (DateTime picked) {
                                            tempDate = picked;
                                          },
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            child: Text(
                                              'cancel'.tr(),
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                          ),
                                          const SizedBox(width: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFF0247C4,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                            ),
                                            child: Text(
                                              'ok'.tr(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            onPressed: () {
                                              setModalState(() {
                                                returnedDate = tempDate;
                                              });
                                              Navigator.of(context).pop();
                                            },
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

  Widget _buildModalTextField(
    String label,
    TextEditingController controller,
    String hintText,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000000),
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            decoration: InputDecoration.collapsed(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
            ),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
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
            color: Color(0xFF000000),
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
              borderRadius: BorderRadius.circular(6),
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
                  Text(
                    'asset_list'.tr(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(40.0),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : (isDataEmpty || filtered.isEmpty
                            ? _buildEmptyState()
                            : _buildDataTable(filtered)),
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
                style: const TextStyle(
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
          // Notification Bell
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

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      children: [
        // Search Bar
        Expanded(
          child: Container(
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
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _currentPage = 1;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'search_assets_hint'.tr(),
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
                        _currentPage = 1;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.grey[400],
                      ),
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
              borderRadius: BorderRadius.circular(6),
            ),
            elevation: 0,
          ),
          icon: SvgPicture.asset(
            'assets/add asset.svg',
            width: 20,
            height: 20,
            colorFilter: const ColorFilter.mode(
              Color(0xFFFFFFFF),
              BlendMode.srcIn,
            ),
          ),
          label: Text(
            'add_asset'.tr(),
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
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
    final totalPages = (assets.isEmpty)
        ? 1
        : (assets.length / _itemsPerPage).ceil();
    final safeStartIndex = (_currentPage - 1) * _itemsPerPage >= assets.length
        ? 0
        : (_currentPage - 1) * _itemsPerPage;
    final paginatedAssets = assets.isEmpty
        ? <AssetData>[]
        : assets.sublist(
            safeStartIndex,
            (safeStartIndex + _itemsPerPage) > assets.length
                ? assets.length
                : (safeStartIndex + _itemsPerPage),
          );

    final double tableHeight = (MediaQuery.of(context).size.height - 279).clamp(
      495.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          // Table Headers
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 3, child: _tableHeader('worker_name'.tr())),
                Expanded(flex: 2, child: _tableHeader('position'.tr())),
                Expanded(flex: 2, child: _tableHeader('type_header'.tr())),
                Expanded(flex: 2, child: _tableHeader('date_loaned'.tr())),
                Expanded(
                  flex: 2,
                  child: _tableHeader('date_returned_header'.tr()),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // Table Rows
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: paginatedAssets.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
              itemBuilder: (context, index) {
                return _buildDataRow(paginatedAssets[index], index);
              },
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          // Pagination
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _currentPage > 1
                      ? () => setState(() => _currentPage--)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_left,
                    color: _currentPage > 1
                        ? Colors.black
                        : Colors.grey.shade400,
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
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _currentPage < totalPages
                      ? () => setState(() => _currentPage++)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.chevron_right,
                    color: _currentPage < totalPages
                        ? Colors.black
                        : Colors.grey.shade400,
                  ),
                ),
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
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
    );
  }

  Widget _buildDataRow(AssetData data, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          // Name and Avatar (Placeholder image)
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage(
                    index % 2 == 0
                        ? 'assets/profileimage.png'
                        : 'assets/boy.png',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    data.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
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
                  color: Color(0xFF000000),
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
                  color: Color(0xFF000000),
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
                  color: Color(0xFF000000),
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
            _buildAssetActionMenu(data),
          ],
        ),
      );
  }

  Widget _buildAssetActionMenu(AssetData data) {
    return SizedBox(
      width: 48,
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.black),
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFFCBCBCB)),
        ),
        color: const Color(0xFFFBFBFC),
        elevation: 4,
        onSelected: (value) async {
          if (value == 'edit') {
            _showEditAssetModal(data);
          } else if (value == 'delete') {
            final confirmed = await DeleteDialog.show(
              context: context,
              title: 'delete_asset'.tr(),
              content: 'delete_asset_desc'.tr(),
            );
            if (!confirmed) return;
            final isGuest = AuthService().currentUser?.isAnonymous ?? false;
            if (isGuest) {
              setState(() { _assets.remove(data); });
            } else {
              if (data.id != null) await FirestoreService().deleteAsset(data.id!);
            }
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
                Text(
                  'Edit',
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
                Text(
                  'delete'.tr(),
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
      ),
    );
  }

  void _showEditAssetModal(AssetData data) {
    final nameController = TextEditingController(text: data.name);
    final typeController = TextEditingController(text: data.type);
    final positionController = TextEditingController(text: data.position);
    DateTime loanedDate = DateTime(2022, 2, 1);
    DateTime returnedDate = DateTime(2026, 10, 9);
    bool isReturned = data.isReturned;

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
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 450,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.black),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          'Edit Asset',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0247C4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: () async {
                            if (nameController.text.isNotEmpty &&
                                typeController.text.isNotEmpty &&
                                positionController.text.isNotEmpty) {
                              final assetMap = {
                                'name': nameController.text,
                                'position': positionController.text,
                                'type': typeController.text,
                                'dateLoaned': formatDate(loanedDate),
                                'dateReturned': isReturned ? formatDate(returnedDate) : 'in_use'.tr(),
                                'isReturned': isReturned,
                              };
                              final isGuest = AuthService().currentUser?.isAnonymous ?? false;
                              if (isGuest) {
                                setState(() {
                                  final idx = _assets.indexWhere((a) => a.id == data.id);
                                  if (idx != -1) {
                                    _assets[idx] = AssetData(
                                      nameController.text,
                                      positionController.text,
                                      typeController.text,
                                      formatDate(loanedDate),
                                      isReturned ? formatDate(returnedDate) : 'in_use'.tr(),
                                      isReturned,
                                      id: data.id,
                                    );
                                  }
                                  final dummyIdx = DummyData.assets.indexWhere((a) => a['name'] == data.name);
                                  if (dummyIdx != -1) DummyData.assets[dummyIdx] = assetMap;
                                });
                              } else {
                                if (data.id != null) await FirestoreService().updateAsset(data.id!, assetMap);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pop();
                              FlashySnackBar.show(context, message: 'Asset updated');
                            }
                          },
                          child: Text(
                            'save'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildModalTextField('Worker Name', nameController, 'Enter worker name'),
                    const SizedBox(height: 14),
                    _buildModalTextField('Asset Type', typeController, 'Enter asset type'),
                    const SizedBox(height: 14),
                    _buildModalTextField('Position', positionController, 'Enter position'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ================= EMPTY STATE =================

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/placeholder_workers.svg',
              width: 120,
              height: 100,
              colorFilter: const ColorFilter.mode(
                Color(0xFFCBCBCB),
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'no_assets_found'.tr(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
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

// Data Model for Assets
class AssetData {
  final String? id;
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
    this.isReturned, {
    this.id,
  });
}
