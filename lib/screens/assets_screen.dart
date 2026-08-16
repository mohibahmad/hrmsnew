import 'dart:async';
import '../utils/ui_helpers.dart';
import '../utils/helpers.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoIcons;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../providers.dart';
import '../services/auth_service.dart';
import '../services/dummy_data.dart';
import '../services/firestore_service.dart';
import '../utils/utils.dart';
import '../widgets/clickable_gesture_detector.dart';
import '../widgets/notification_bell.dart';

String _adts(dynamic value) {
  DateTime? dt;

  if (value is Timestamp) {
    dt = value.toDate();
  } else if (value is DateTime) {
    dt = value;
  } else if (value is String) {
    dt = DateTime.tryParse(value);
  }

  if (dt != null) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  return value?.toString() ?? '';
}

String _formatPositionTitleCase(dynamic value) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return '';

  const acronyms = {'hr', 'it', 'qa', 'ui', 'ux', 'ui/ux', 'ceo', 'cto', 'cfo', 'coo', 'php', 'sql'};

  return text.split(RegExp(r'\s+')).map((word) {
    final lower = word.toLowerCase();
    return acronyms.contains(lower)
        ? lower.toUpperCase()
        : '${lower[0].toUpperCase()}${lower.substring(1)}';
  }).join(' ');
}

bool _assetBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;

  return switch (value?.toString().trim().toLowerCase() ?? '') {
    'true' || '1' || 'yes' => true,
    'false' || '0' || 'no' => false,
    _ => defaultValue,
  };
}

bool _assetReturned(Map<String, dynamic> data) {
  final rawStatus = data['isReturned'];
  if (rawStatus != null) return _assetBool(rawStatus);

  final value = data['dateReturned'];
  if (value == null) return false;

  final text = value.toString().trim().toLowerCase();
  return text.isNotEmpty && text != 'in_use' && text != '__in_use__';
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class AssetsScreen extends ConsumerStatefulWidget {
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
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestore;

  final _searchController = TextEditingController();

  String _searchQuery = '';
  List<AssetData> _assets = [];
  bool _isLoading = false;
  List<String> _workerNames = [];
  Map<String, Map<String, dynamic>> _workersMap = {};
  bool _initialized = false;
  Timer? _debounce;

  StreamSubscription? _assetsSub;
  StreamSubscription? _workersSub;

  static const _inUseKey = 'in_use';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    final isGuest = _authService.currentUser?.isAnonymous ?? false;

    if (isGuest) {
      _loadGuestData();
    } else {
      _loadAssets();
      _loadWorkers();
    }
  }

  @override
  void dispose() {
    _assetsSub?.cancel();
    _workersSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadGuestData() {
    _assets = DummyData.assets.map((data) {
      return AssetData(
        data['name'] ?? '',
        data['position'] ?? '',
        data['type'] ?? '',
        _adts(data['dateLoaned']),
        _adts(data['dateReturned']),
        data['isReturned'] ?? false,
        profileImage: data['profileImage']?.toString(),
        workerId: data['workerId']?.toString(),
        email: data['email']?.toString(),
        phone: data['phone']?.toString(),
        cnic: data['cnic']?.toString(),
        dateOfJoining: _adts(data['dateOfJoining']),
      );
    }).toList();

    _setWorkerOptions(DummyData.workers.map(Map<String, dynamic>.from));
  }

  Future<void> _loadAssets() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    _assetsSub?.cancel();
    _assetsSub = _firestore.assetsStream.listen(
      (snapshot) {
        if (!mounted) return;

        final sortedDocs = snapshot.docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['createdAt'];
            final bTime = bData['createdAt'];

            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return -1;
            if (bTime == null) return 1;
            if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
            return 0;
          });

        setState(() {
          _assets = sortedDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return AssetData(
              (data['name'] ?? '').toString(),
              (data['position'] ?? '').toString(),
              (data['type'] ?? '').toString(),
              _adts(data['dateLoaned']),
              _adts(data['dateReturned']),
              _assetReturned(data),
              id: doc.id,
              workerId: data['workerId']?.toString(),
            );
          }).toList();
          _isLoading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  void _loadWorkers() {
    _workersSub?.cancel();
    _workersSub = _firestore.workersStream.listen((snapshot) {
      if (!mounted) return;
      _setWorkerOptions(
        snapshot.docs.map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id}),
      );
      setState(() {});
    }, onError: (_) {});
  }

  String _workerOption(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? '').toString().trim();
    final email = (worker['email'] ?? '').toString().trim();
    final id = (worker['id'] ?? '').toString().trim();
    final qualifier = email.isNotEmpty ? email : id;
    return qualifier.isEmpty ? name : '$name — $qualifier';
  }

  bool _isAssetEligibleWorker(Map<String, dynamic> worker) {
    final status = (worker['employmentStatus'] ??
            worker['workerStatus'] ??
            worker['status'] ??
            'Active')
        .toString()
        .trim()
        .toLowerCase();

    return !const {'inactive', 'terminated', 'deleted', 'archived'}.contains(status);
  }

  void _setWorkerOptions(Iterable<Map<String, dynamic>> workers) {
    final named = workers
        .where((w) => (w['name'] ?? '').toString().trim().isNotEmpty)
        .toList();

    _workersMap = {for (final w in named) _workerOption(w): w};
    _workerNames = named.where(_isAssetEligibleWorker).map(_workerOption).toList();
  }

  String? _optionForAsset(AssetData asset) {
    for (final entry in _workersMap.entries) {
      final worker = entry.value;
      final workerId = (worker['id'] ?? '').toString().trim();

      if ((asset.workerId ?? '').isNotEmpty && workerId == asset.workerId) {
        return entry.key;
      }

      final email = (worker['email'] ?? '').toString().trim().toLowerCase();
      if ((asset.email ?? '').trim().isNotEmpty &&
          email == asset.email!.trim().toLowerCase()) {
        return entry.key;
      }
    }

    final assetName = asset.name.trim().toLowerCase();
    for (final entry in _workersMap.entries) {
      final workerName = (entry.value['name'] ?? '').toString().trim().toLowerCase();
      if (workerName == assetName) return entry.key;
    }

    return null;
  }

  List<AssetData> get _filteredAssets {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return List<AssetData>.from(_assets);

    return _assets.where((asset) {
      return asset.name.toLowerCase().contains(query) ||
          asset.type.toLowerCase().contains(query) ||
          asset.position.toLowerCase().contains(query);
    }).toList();
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null ||
        dateStr.isEmpty ||
        dateStr == _inUseKey ||
        dateStr == '__IN_USE__') {
      return null;
    }

    try {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}

    return null;
  }

  bool _validateAssetForm({
    required String? selectedWorkerName,
    required String assetType,
    required String position,
    required BuildContext ctx,
  }) {
    final allEmpty = (selectedWorkerName == null || selectedWorkerName.trim().isEmpty) &&
        assetType.isEmpty &&
        position.isEmpty;

    if (allEmpty) {
      FlashySnackBar.show(ctx, message: 'please_fill_all_fields'.tr(), isError: true);
      return false;
    }

    if (selectedWorkerName == null || selectedWorkerName.trim().isEmpty) {
      FlashySnackBar.show(
        ctx,
        message: 'field_is_required'.tr(namedArgs: {'field': 'worker_name'.tr()}),
        isError: true,
      );
      return false;
    }

    if (assetType.isEmpty) {
      FlashySnackBar.show(
        ctx,
        message: 'field_is_required'.tr(namedArgs: {'field': 'asset_type'.tr()}),
        isError: true,
      );
      return false;
    }

    if (position.isEmpty) {
      FlashySnackBar.show(
        ctx,
        message: 'field_is_required'.tr(namedArgs: {'field': 'position'.tr()}),
        isError: true,
      );
      return false;
    }

    return true;
  }

  Map<String, dynamic> _buildAssetMap({
    required Map<String, dynamic> workerData,
    required String position,
    required String assetType,
    required DateTime loanedDate,
    required DateTime returnedDate,
    required bool isReturned,
  }) {
    final workerId = (workerData['id'] ?? '').toString();
    final name = (workerData['name'] ?? '').toString();
    final profileImage = workerData['profileImage']?.toString() ?? '';
    final email = workerData['email']?.toString() ?? '';
    final phone = workerData['phone']?.toString() ?? '';
    final cnic = (workerData['cnic'] ?? workerData['nationalId'])?.toString() ?? '';
    final dateOfJoining = _adts(workerData['dateOfJoining']);
    final joiningDate = _adts(workerData['joiningDate'] ?? workerData['dateOfJoining']);

    return {
      'workerId': workerId,
      'name': name,
      'position': position,
      'type': assetType,
      'dateLoaned': loanedDate,
      'dateReturned': isReturned ? returnedDate : null,
      'isReturned': isReturned,
      'profileImage': profileImage,
      'email': email,
      'phone': phone,
      'cnic': cnic,
      'dateOfJoining': dateOfJoining,
      'joiningDate': joiningDate,
    };
  }

  void _showAddAssetModal(BuildContext context) {
    final parentContext = context;
    String? selectedWorkerName;
    final typeController = TextEditingController();
    final positionController = TextEditingController();
    DateTime loanedDate = DateTime.now();
    DateTime returnedDate = DateTime.now();
    bool isReturned = false;
    var isSaving = false;

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              backgroundColor: const Color(0xFFFFFFFF),
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
                          onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final assetType = typeController.text.trim();
                                  final position = positionController.text.trim();

                                  if (!_validateAssetForm(
                                    selectedWorkerName: selectedWorkerName,
                                    assetType: assetType,
                                    position: position,
                                    ctx: ctx,
                                  )) {
                                    return;
                                  }

                                  if (isReturned && returnedDate.isBefore(loanedDate)) {
                                    returnedDate = loanedDate;
                                  }

                                  final workerData = _workersMap[selectedWorkerName];
                                  if (workerData == null) {
                                    FlashySnackBar.show(
                                      ctx,
                                      message: 'please_select_valid_worker'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  setModalState(() => isSaving = true);

                                  final workerId = (workerData['id'] ?? '').toString();
                                  final workerName = (workerData['name'] ?? '').toString();
                                  final profileImage = workerData['profileImage']?.toString();

                                  try {
                                    final policies = await _firestore.getPolicies();
                                    if (!mounted) return;

                                    final assetPolicy = policies
                                        .where((p) => p['typeId'] == 'Asset Policy')
                                        .toList();

                                    if (assetPolicy.isNotEmpty) {
                                      final maxAssets =
                                          int.tryParse(assetPolicy.first['maxAssetsPerWorker']?.toString() ?? '3') ?? 3;

                                      final assignedCount = _assets.where((a) {
                                        final wId = (a.workerId ?? '').toString();
                                        return !a.isReturned &&
                                            (wId == workerId || a.name == workerName);
                                      }).length;

                                      if (assignedCount >= maxAssets) {
                                        setModalState(() => isSaving = false);
                                        if (!ctx.mounted) return;
                                        FlashySnackBar.show(
                                          ctx,
                                          message: 'worker_asset_limit_reached'.tr(
                                            namedArgs: {'maxAssets': '$maxAssets'},
                                          ),
                                          isError: true,
                                        );
                                        return;
                                      }
                                    }
                                  } catch (_) {}

                                  final assetMap = _buildAssetMap(
                                    workerData: workerData,
                                    position: position,
                                    assetType: assetType,
                                    loanedDate: loanedDate,
                                    returnedDate: returnedDate,
                                    isReturned: isReturned,
                                  );

                                  final isGuest = _authService.currentUser?.isAnonymous ?? false;

                                  if (isGuest) {
                                    final guestAsset = {
                                      ...assetMap,
                                      'dateLoaned': _formatDate(loanedDate),
                                      'dateReturned': isReturned ? _formatDate(returnedDate) : null,
                                    };

                                    setState(() {
                                      _assets.insert(
                                        0,
                                        AssetData(
                                          workerName,
                                          position,
                                          assetType,
                                          _formatDate(loanedDate),
                                          isReturned ? _formatDate(returnedDate) : '',
                                          isReturned,
                                          workerId: workerId,
                                          profileImage: profileImage,
                                          email: workerData['email']?.toString(),
                                          phone: workerData['phone']?.toString(),
                                          cnic: (workerData['cnic'] ?? workerData['nationalId'])?.toString(),
                                          dateOfJoining: _adts(workerData['dateOfJoining']),
                                        ),
                                      );
                                      DummyData.assets.insert(0, guestAsset);
                                    });

                                    await DummyData.saveToPrefs();
                                    setModalState(() => isSaving = false);
                                  } else {
                                    try {
                                      await _firestore.addAsset(assetMap);
                                    } catch (e) {
                                      setModalState(() => isSaving = false);
                                      if (!ctx.mounted) return;
                                      FlashySnackBar.show(
                                        ctx,
                                        message: 'failed_to_add_asset'.tr(namedArgs: {'error': e.toString()}),
                                        isError: true,
                                      );
                                      return;
                                    }
                                  }

                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  FlashySnackBar.show(
                                    ctx,
                                    message: 'successfully_added_asset'.tr(namedArgs: {'name': workerName}),
                                  );
                                  if (parentContext.mounted) {
                                    tryShowFirstMilestoneRateUs('asset');
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'worker_name'.tr(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000000),
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textValue) {
                            if (textValue.text.isEmpty) return _workerNames;
                            return _workerNames.where(
                              (name) => name.toLowerCase().contains(textValue.text.toLowerCase()),
                            );
                          },
                          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                            return Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      decoration: InputDecoration.collapsed(
                                        hintText: 'worker_name_hint'.tr(),
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
                                      onChanged: (val) {
                                        setModalState(() {
                                          selectedWorkerName = val.trim().isEmpty ? null : val.trim();
                                          if (_workersMap.containsKey(val.trim())) {
                                            positionController.text = _formatPositionTitleCase(
                                              _workersMap[val.trim()]!['position'],
                                            );
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, color: Colors.black, size: 24),
                                ],
                              ),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 6,
                                color: Colors.white,
                                borderRadius: BorderRadius.zero,
                                shadowColor: Colors.black.withValues(alpha: 0.12),
                                child: Container(
                                  constraints: const BoxConstraints(maxHeight: 220, maxWidth: 420),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.zero,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      separatorBuilder: (_, _) => const Divider(
                                        height: 1,
                                        thickness: 0.6,
                                        color: Color(0xFFF3F4F6),
                                        indent: 14,
                                        endIndent: 14,
                                      ),
                                      itemBuilder: (context, index) {
                                        final option = options.elementAt(index);
                                        return InkWell(
                                          onTap: () => onSelected(option),
                                          splashColor: const Color(0xFF0247C4).withValues(alpha: 0.06),
                                          highlightColor: const Color(0xFF0247C4).withValues(alpha: 0.04),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            child: Text(
                                              option,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                color: Color(0xFF1F2937),
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          onSelected: (String val) {
                            setModalState(() {
                              selectedWorkerName = val;
                              if (_workersMap.containsKey(val)) {
                                positionController.text = _formatPositionTitleCase(
                                  _workersMap[val]!['position'],
                                );
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField('asset_type'.tr(), typeController, 'asset_type_hint'.tr(), maxLength: 50),
                    const SizedBox(height: 16),
                    _buildModalTextField('position'.tr(), positionController, 'position_hint'.tr(), readOnly: true),
                    const SizedBox(height: 16),
                    _buildModalDatePicker(
                      ctx,
                      'date_loaned'.tr(),
                      _formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () => _showCupertinoDatePicker(
                        context: ctx,
                        initialDate: loanedDate,
                        minimumDate: DateTime(2000),
                        maximumDate: DateTime.now().add(const Duration(days: 365)),
                        title: 'date_loaned'.tr(),
                        onDateSelected: (picked) {
                          setModalState(() {
                            loanedDate = picked;
                            if (returnedDate.isBefore(loanedDate)) returnedDate = loanedDate;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
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
                            if (val == null) return;
                            setModalState(() {
                              isReturned = val;
                              if (isReturned && returnedDate.isBefore(loanedDate)) {
                                returnedDate = loanedDate;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (isReturned) ...[
                      const SizedBox(height: 8),
                      _buildModalDatePicker(
                        ctx,
                        'returned_date'.tr(),
                        _formatDate(returnedDate),
                        Colors.red,
                        () => _showCupertinoDatePicker(
                          context: ctx,
                          initialDate: returnedDate,
                          minimumDate: loanedDate,
                          maximumDate: DateTime.now(),
                          title: 'returned_date'.tr(),
                          onDateSelected: (picked) => setModalState(() => returnedDate = picked),
                        ),
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

  void _showEditAssetModal(AssetData data) {
    String? selectedWorkerName = _optionForAsset(data);
    final typeController = TextEditingController(text: data.type);
    final positionController = TextEditingController(text: _formatPositionTitleCase(data.position));
    final now = DateTime.now();
    final minimumAssetDate = DateTime(1900, 1, 1);

    DateTime loanedDate = _parseDate(data.dateLoaned) ?? now;
    if (loanedDate.isBefore(minimumAssetDate)) loanedDate = minimumAssetDate;
    if (loanedDate.isAfter(now)) loanedDate = now;

    DateTime returnedDate = _parseDate(data.dateReturned) ?? now;
    if (returnedDate.isAfter(now)) returnedDate = now;
    if (returnedDate.isBefore(loanedDate)) returnedDate = loanedDate;

    bool isReturned = data.isReturned;
    var isSaving = false;

    showDialog(
      context: context,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              backgroundColor: const Color(0xFFFFFFFF),
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
                          onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          'edit_asset'.tr(),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final assetType = typeController.text.trim();
                                  final position = positionController.text.trim();

                                  if (!_validateAssetForm(
                                    selectedWorkerName: selectedWorkerName,
                                    assetType: assetType,
                                    position: position,
                                    ctx: ctx,
                                  )) {
                                    return;
                                  }

                                  if (isReturned && returnedDate.isBefore(loanedDate)) {
                                    returnedDate = loanedDate;
                                  }

                                  final workerData = _workersMap[selectedWorkerName];
                                  if (workerData == null) {
                                    FlashySnackBar.show(ctx, message: 'no_workers_found'.tr(), isError: true);
                                    return;
                                  }

                                  setModalState(() => isSaving = true);

                                  final workerId = (workerData['id'] ?? '').toString();
                                  final workerName = (workerData['name'] ?? '').toString();
                                  final profileImage = workerData['profileImage']?.toString();
                                  final email = workerData['email']?.toString();
                                  final phone = workerData['phone']?.toString();
                                  final cnic = (workerData['cnic'] ?? workerData['nationalId'])?.toString();
                                  final dateOfJoining = _adts(workerData['dateOfJoining']);
                                  final joiningDate = _adts(workerData['joiningDate'] ?? workerData['dateOfJoining']);

                                  final assetMap = _buildAssetMap(
                                    workerData: workerData,
                                    position: position,
                                    assetType: assetType,
                                    loanedDate: loanedDate,
                                    returnedDate: returnedDate,
                                    isReturned: isReturned,
                                  );

                                  final isGuest = _authService.currentUser?.isAnonymous ?? false;

                                  if (isGuest) {
                                    setState(() {
                                      final idx = _assets.indexWhere((a) => a.id == data.id);
                                      if (idx != -1) {
                                        _assets[idx] = AssetData(
                                          workerName,
                                          position,
                                          assetType,
                                          _formatDate(loanedDate),
                                          isReturned ? _formatDate(returnedDate) : '',
                                          isReturned,
                                          id: data.id,
                                          workerId: workerId,
                                          profileImage: profileImage,
                                          email: email,
                                          phone: phone,
                                          cnic: cnic,
                                          dateOfJoining: dateOfJoining,
                                        );
                                      }

                                      final dummyIdx = DummyData.assets.indexWhere((asset) {
                                        return (data.workerId ?? '').isNotEmpty
                                            ? asset['workerId'] == data.workerId
                                            : asset['name'] == data.name && asset['type'] == data.type;
                                      });

                                      if (dummyIdx != -1) {
                                        DummyData.assets[dummyIdx] = assetMap;
                                      }
                                    });

                                    await DummyData.saveToPrefs();
                                  } else {
                                    if (data.id != null) {
                                      try {
                                        await _firestore.updateAsset(data.id!, {
                                          ...assetMap,
                                          'dateOfJoining': joiningDate,
                                        });
                                      } catch (e) {
                                        setModalState(() => isSaving = false);
                                        if (!ctx.mounted) return;
                                        FlashySnackBar.show(
                                          ctx,
                                          message: 'failed_to_update_asset'.tr(namedArgs: {'error': e.toString()}),
                                          isError: true,
                                        );
                                        return;
                                      }

                                      setState(() {
                                        _assets = _assets.map((a) {
                                          if (a.id != data.id) return a;
                                          return AssetData(
                                            workerName,
                                            position,
                                            assetType,
                                            _formatDate(loanedDate),
                                            isReturned ? _formatDate(returnedDate) : '',
                                            isReturned,
                                            id: data.id,
                                            workerId: workerId,
                                            profileImage: profileImage,
                                            email: email,
                                            phone: phone,
                                            cnic: cnic,
                                            dateOfJoining: dateOfJoining,
                                          );
                                        }).toList();
                                      });
                                    }
                                  }

                                  if (!ctx.mounted) return;
                                  Navigator.of(ctx).pop();
                                  FlashySnackBar.show(ctx, message: 'asset_updated'.tr());
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
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
                    const SizedBox(height: 24),
                    _buildModalDropdown(
                      'worker_name'.tr(),
                      selectedWorkerName,
                      _workerNames,
                      'worker_name_hint'.tr(),
                      (val) {
                        setModalState(() {
                          selectedWorkerName = val;
                          if (val != null && _workersMap.containsKey(val)) {
                            positionController.text = _formatPositionTitleCase(_workersMap[val]!['position']);
                          } else {
                            positionController.text = '';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField('asset_type'.tr(), typeController, 'asset_type_hint'.tr(), maxLength: 50),
                    const SizedBox(height: 16),
                    _buildModalTextField('position'.tr(), positionController, 'position_hint'.tr(), readOnly: true),
                    const SizedBox(height: 16),
                    _buildModalDatePicker(
                      ctx,
                      'date_loaned'.tr(),
                      _formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () => _showCupertinoDatePicker(
                        context: ctx,
                        initialDate: loanedDate,
                        minimumDate: DateTime(2000),
                        maximumDate: DateTime.now().add(const Duration(days: 365)),
                        title: 'date_loaned'.tr(),
                        onDateSelected: (picked) {
                          setModalState(() {
                            loanedDate = picked;
                            if (returnedDate.isBefore(loanedDate)) returnedDate = loanedDate;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
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
                            if (val == null) return;
                            setModalState(() {
                              isReturned = val;
                              if (isReturned && returnedDate.isBefore(loanedDate)) {
                                returnedDate = loanedDate;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                    if (isReturned) ...[
                      const SizedBox(height: 8),
                      _buildModalDatePicker(
                        ctx,
                        'returned_date'.tr(),
                        _formatDate(returnedDate),
                        Colors.red,
                        () => _showCupertinoDatePicker(
                          context: ctx,
                          initialDate: returnedDate,
                          minimumDate: loanedDate,
                          maximumDate: DateTime.now(),
                          title: 'returned_date'.tr(),
                          onDateSelected: (picked) => setModalState(() => returnedDate = picked),
                        ),
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
    String hintText, {
    bool readOnly = false,
    int? maxLength,
  }) {
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
            color: readOnly ? Colors.grey.shade50 : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            maxLength: maxLength,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: InputDecoration.collapsed(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontFamily: 'SF Pro Display'),
            ),
            style: TextStyle(
              fontSize: 14,
              color: readOnly ? const Color(0xFF9E9E9E) : Colors.black,
              fontWeight: FontWeight.w500,
              fontFamily: 'SF Pro Display',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModalDropdown(
    String label,
    String? value,
    List<String> items,
    String hintText,
    ValueChanged<String?> onChanged,
  ) {
    final isEmpty = items.isEmpty;

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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              elevation: 8,
              menuMaxHeight: 250,
              dropdownColor: Colors.white,
              value: isEmpty ? null : (items.contains(value) ? value : null),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              hint: Text(
                isEmpty ? 'no_workers_found'.tr() : hintText,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontFamily: 'SF Pro Display'),
              ),
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.black, size: 24),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
              items: items.map((val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(val, style: const TextStyle(fontWeight: FontWeight.w500, fontFamily: 'SF Pro Display')),
                );
              }).toList(),
              onChanged: isEmpty ? null : onChanged,
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
                Icon(Icons.calendar_month, color: Colors.grey.shade400, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCupertinoDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime minimumDate,
    required DateTime maximumDate,
    required String title,
    required ValueChanged<DateTime> onDateSelected,
  }) {
    DateTime selected = initialDate;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'date_picker'.tr(),
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Center(
                child: StatefulBuilder(
                  builder: (_, setPickerState) {
                    return Container(
                      width: 380,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0247C4).withValues(alpha: 0.18),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                const Icon(CupertinoIcons.calendar, size: 20, color: Color(0xFF0247C4)),
                                const SizedBox(width: 8),
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 200,
                            child: CupertinoDatePicker(
                              mode: CupertinoDatePickerMode.date,
                              initialDateTime: initialDate,
                              minimumDate: minimumDate,
                              maximumDate: maximumDate,
                              onDateTimeChanged: (newDate) => setPickerState(() => selected = newDate),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(ctx).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'cancel'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF374151),
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      onDateSelected(selected);
                                      Navigator.of(ctx).pop();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0247C4),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'done'.tr(),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
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
                      : filtered.isEmpty
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
              const SizedBox(height: 4),
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

  Widget _buildTopActionRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
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
                  colorFilter: const ColorFilter.mode(Color(0xFFBDBDBD), BlendMode.srcIn),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () {
                        if (mounted) setState(() => _searchQuery = val);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'search_assets_hint'.tr(),
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
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
        const SizedBox(width: 10),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ElevatedButton.icon(
            onPressed: () async {
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (isGuest) {
                if (mounted) showGuestRestrictionDialog(context);
                return;
              }
              if (!mounted) return;
              _showAddAssetModal(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4),
              minimumSize: const Size(140, 50),
              fixedSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
            ),
            icon: Image.asset('assets/asset_icon.png', width: 20, height: 20, color: Colors.white),
            label: Text(
              'assign_assets'.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataTable(List<AssetData> assets) {
    final tableHeight = (MediaQuery.of(context).size.height - 279).clamp(495.0, 1200.0);

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('worker_name'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('position'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('type_header'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('date_loaned'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('date_returned_header'.tr()))),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: assets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildDataRow(assets[index]),
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
        fontSize: 16,
        color: Color(0xFF000000),
        fontFamily: 'SF Pro Display',
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDataRow(AssetData data) {
    String? profileImage = data.profileImage;
    final matchKey = _optionForAsset(data) ?? '';

    if ((profileImage == null || profileImage.isEmpty) && matchKey.isNotEmpty) {
      profileImage = _workersMap[matchKey]?['profileImage']?.toString();
    }

    final dateReturnedText = data.dateReturned.trim();
    final isInUse = dateReturnedText.isEmpty ||
        dateReturnedText.toLowerCase() == _inUseKey ||
        dateReturnedText.toLowerCase() == 'in_use' ||
        dateReturnedText == '__IN_USE__';

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
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  WorkerAvatar(imageUrl: profileImage, name: data.name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF000000),
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                _formatPositionTitleCase(data.position),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                data.type,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                AppDateUtils.fromValueLocalized(data.dateLoaned, locale: context.locale.toString()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Color(0xFF000000), fontFamily: 'SF Pro Display'),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, left: 8),
              child: Text(
                isInUse
                    ? 'in_use'.tr()
                    : AppDateUtils.fromValueLocalized(data.dateReturned, locale: context.locale.toString()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: data.isReturned ? Colors.green : Colors.red,
                  fontFamily: 'SF Pro Display',
                ),
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
        tooltip: '',
        icon: const Icon(Icons.more_vert, color: Colors.black),
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: const BorderSide(color: Color(0xFFCBCBCB)),
        ),
        color: const Color(0xFFFBFBFC),
        elevation: 4,
        onSelected: (value) async {
          final isGuest = _authService.currentUser?.isAnonymous ?? false;

          if (value == 'edit') {
            if (isGuest) {
              showGuestRestrictionDialog(context);
              return;
            }
            _showEditAssetModal(data);
          } else if (value == 'delete') {
            if (isGuest) {
              showGuestRestrictionDialog(context);
              return;
            }

            final confirmed = await DeleteDialog.show(
              context: context,
              title: 'delete_asset'.tr(),
              content: 'delete_asset_desc'.tr(),
            );
            if (!confirmed) return;

            final assetId = data.id?.trim() ?? '';
            if (assetId.isEmpty) return;

            try {
              await _firestore.deleteAsset(assetId);
            } catch (e) {
              if (mounted) {
                FlashySnackBar.show(
                  context,
                  message: 'failed_to_delete_record'.tr(namedArgs: {'error': e.toString()}),
                  isError: true,
                );
              }
            }
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'edit',
            height: 36,
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/edit_icon.svg',
                  width: 16,
                  height: 16,
                  colorFilter: const ColorFilter.mode(Color(0xFF0247C4), BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  'edit_asset'.tr(),
                  style: const TextStyle(
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
                  colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
                ),
                const SizedBox(width: 8),
                Text(
                  'delete'.tr(),
                  style: const TextStyle(
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

  Widget _buildEmptyState() {
    final containerHeight = (MediaQuery.of(context).size.height - 279).clamp(495.0, 1200.0);

    return Container(
      width: double.infinity,
      height: containerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/placeholder_workers.svg',
            width: 120,
            height: 100,
            colorFilter: const ColorFilter.mode(Color(0xFFCBCBCB), BlendMode.srcIn),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _searchQuery.isNotEmpty ? 'no_search_results'.tr() : 'no_assets_found'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0247C4),
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetData {
  final String? id;
  final String? workerId;
  final String name;
  final String position;
  final String type;
  final String dateLoaned;
  final String dateReturned;
  final bool isReturned;
  final String? profileImage;
  final String? email;
  final String? phone;
  final String? cnic;
  final String? dateOfJoining;

  const AssetData(
    this.name,
    this.position,
    this.type,
    this.dateLoaned,
    this.dateReturned,
    this.isReturned, {
    this.id,
    this.workerId,
    this.profileImage,
    this.email,
    this.phone,
    this.cnic,
    this.dateOfJoining,
  });
}