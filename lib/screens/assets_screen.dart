import 'dart:async';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoIcons;
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/snackbar_utils.dart';
import '../utils/delete_dialog.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/preferences_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../utils/premium_gate.dart';
import '../utils/date_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/notification_bell.dart';
import '../utils/image_utils.dart';
import '../utils/rate_us_helper.dart';
import '../utils/guest_restriction.dart';

String _adts(dynamic value) {
  if (value == null) return '';
  if (value is Timestamp) {
    final d = value.toDate();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
  if (value is DateTime) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
    }
  }
  return value.toString();
}

String _formatPositionTitleCase(dynamic value) {
  final text = (value ?? '').toString().trim();
  if (text.isEmpty) return '';
  const acronyms = {
    'hr',
    'it',
    'qa',
    'ui',
    'ux',
    'ui/ux',
    'ceo',
    'cto',
    'cfo',
    'coo',
    'php',
    'sql',
  };
  return text
      .split(RegExp(r'\s+'))
      .map((word) {
        final lower = word.toLowerCase();
        if (acronyms.contains(lower)) return lower.toUpperCase();
        return '${lower[0].toUpperCase()}${lower.substring(1)}';
      })
      .join(' ');
}

bool _assetBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;

  final text = value?.toString().trim().toLowerCase() ?? '';
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return defaultValue;
}

bool _assetReturned(Map<String, dynamic> data) {
  final rawStatus = data['isReturned'];
  if (rawStatus != null) {
    return _assetBool(rawStatus);
  }

  final value = data['dateReturned'];
  if (value == null) return false;
  final text = value.toString().trim().toLowerCase();
  return text.isNotEmpty && text != 'in_use' && text != '__in_use__';
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
  late AuthService _authService;
  late FirestoreService _firestore;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<AssetData> _assets = [];
  bool _isLoading = false;
  List<String> _workerNames = [];
  Map<String, Map<String, dynamic>> _workersMap = {};
  bool _initialized = false;
  Timer? _debounce;

  String _workerOption(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? '').toString().trim();
    final email = (worker['email'] ?? '').toString().trim();
    final id = (worker['id'] ?? '').toString().trim();
    final qualifier = email.isNotEmpty ? email : id;
    return qualifier.isEmpty ? name : '$name — $qualifier';
  }

  bool _isAssetEligibleWorker(Map<String, dynamic> worker) {
    final status =
        (worker['employmentStatus'] ??
                worker['workerStatus'] ??
                worker['status'] ??
                'Active')
            .toString()
            .trim()
            .toLowerCase();
    return !const {
      'inactive',
      'terminated',
      'deleted',
      'archived',
    }.contains(status);
  }

  void _setWorkerOptions(Iterable<Map<String, dynamic>> workers) {
    final validWorkers = workers
        .where(
          (worker) =>
              (worker['name'] ?? '').toString().trim().isNotEmpty &&
              _isAssetEligibleWorker(worker),
        )
        .toList();
    _workerNames = validWorkers.map(_workerOption).toList();
    _workersMap = {
      for (final worker in validWorkers) _workerOption(worker): worker,
    };
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
      final workerName = (entry.value['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (workerName == assetName) return entry.key;
    }
    return null;
  }

  @override
  void dispose() {
    _assetsSub?.cancel();
    _workersSub?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
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
    } else {
      _loadAssets();
      _loadWorkers();
    }
  }

  StreamSubscription? _assetsSub;
  StreamSubscription? _workersSub;

  Future<void> _loadAssets() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    _assetsSub?.cancel();
    _assetsSub = _firestore.assetsStream.listen(
      (snapshot) {
        if (!mounted) return;
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
        snapshot.docs.map(
          (doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id},
        ),
      );
      setState(() {});
    }, onError: (_) {});
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

  void _showAddAssetModal(BuildContext context) {
    final parentContext = context;
    String? selectedWorkerName;
    final typeController = TextEditingController();
    final positionController = TextEditingController();
    DateTime loanedDate = DateTime.now();
    DateTime returnedDate = DateTime.now();
    bool isReturned = false;
    var isSaving = false;

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
                              borderRadius: BorderRadius.circular(4),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final selectedOption = selectedWorkerName;
                                  final assetType = typeController.text.trim();
                                  final position = positionController.text
                                      .trim();

                                  final allFieldsEmpty =
                                      (selectedOption == null ||
                                          selectedOption.trim().isEmpty) &&
                                      assetType.isEmpty &&
                                      position.isEmpty;

                                  if (allFieldsEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_fill_all_fields'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (selectedOption == null ||
                                      selectedOption.trim().isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {
                                          'field': 'worker_name'.tr(),
                                        },
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (assetType.isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {'field': 'asset_type'.tr()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (position.isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {'field': 'position'.tr()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (isReturned &&
                                      returnedDate.isBefore(loanedDate)) {
                                    returnedDate = loanedDate;
                                  }

                                  final selectedWorkerData =
                                      _workersMap[selectedOption];
                                  if (selectedWorkerData == null) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'no_workers_found'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (selectedWorkerName != null &&
                                      typeController.text.isNotEmpty &&
                                      positionController.text.isNotEmpty) {
                                    setModalState(() => isSaving = true);
                                    final workerData = selectedWorkerData;
                                    final actualWorkerName =
                                        (workerData['name'] ?? '').toString();
                                    final selectedWorkerId =
                                        (workerData['id'] ?? '').toString();
                                    final workerProfileImage =
                                        workerData['profileImage']?.toString();
                                    try {
                                      final policies = await _firestore
                                          .getPolicies();
                                      final assetPolicyList = policies
                                          .where(
                                            (p) =>
                                                p['typeId'] == 'Asset Policy',
                                          )
                                          .toList();
                                      if (assetPolicyList.isNotEmpty) {
                                        final assetPolicy =
                                            assetPolicyList.first;
                                        final int maxAssets =
                                            int.tryParse(
                                              assetPolicy['maxAssetsPerWorker']
                                                      ?.toString() ??
                                                  '3',
                                            ) ??
                                            3;

                                        final assignedAssets = _assets.where((
                                          a,
                                        ) {
                                          final wId = (a.workerId ?? '')
                                              .toString();
                                          final wName = a.name;
                                          final returned = a.isReturned;
                                          return !returned &&
                                              (wId == selectedWorkerId ||
                                                  wName == actualWorkerName);
                                        }).length;

                                        if (assignedAssets >= maxAssets) {
                                          setModalState(() => isSaving = false);
                                          FlashySnackBar.show(
                                            context,
                                            message:
                                                'worker_asset_limit_reached'.tr(
                                                  namedArgs: {
                                                    'maxAssets': '$maxAssets',
                                                  },
                                                ),
                                            isError: true,
                                          );
                                          return;
                                        }
                                      }
                                    } catch (_) {}
                                    final workerEmail = workerData['email']
                                        ?.toString();
                                    final workerPhone = workerData['phone']
                                        ?.toString();
                                    final workerCnic =
                                        (workerData['cnic'] ??
                                                workerData['nationalId'])
                                            ?.toString();
                                    final workerDateOfJoining = _adts(
                                      workerData['dateOfJoining'],
                                    );
                                    final workerJoiningDate = _adts(
                                      workerData['joiningDate'] ??
                                          workerData['dateOfJoining'],
                                    );
                                    final assetMap = {
                                      'workerId': selectedWorkerId,
                                      'name': actualWorkerName,
                                      'position': positionController.text,
                                      'type': typeController.text,
                                      'dateLoaned': loanedDate,
                                      'dateReturned': isReturned
                                          ? returnedDate
                                          : null,
                                      'isReturned': isReturned,
                                      'profileImage': workerProfileImage ?? '',
                                      'email': workerEmail ?? '',
                                      'phone': workerPhone ?? '',
                                      'cnic': workerCnic ?? '',
                                      'dateOfJoining': workerDateOfJoining,
                                    };
                                    final firestoreAssetMap = <String, dynamic>{
                                      ...assetMap,
                                      'position': position,
                                      'type': assetType,
                                      'dateOfJoining': workerJoiningDate,
                                    };
                                    final isGuest =
                                        _authService.currentUser?.isAnonymous ??
                                        false;
                                    if (isGuest) {
                                      final newAsset = {
                                        'workerId': selectedWorkerId,
                                        'name': actualWorkerName,
                                        'position': positionController.text,
                                        'type': typeController.text,
                                        'dateLoaned': formatDate(loanedDate),
                                        'dateReturned': isReturned
                                            ? formatDate(returnedDate)
                                            : null,
                                        'isReturned': isReturned,
                                        'profileImage':
                                            workerProfileImage ?? '',
                                        'email': workerEmail ?? '',
                                        'phone': workerPhone ?? '',
                                        'cnic': workerCnic ?? '',
                                        'dateOfJoining': workerDateOfJoining,
                                      };
                                      setState(() {
                                        _assets.insert(
                                          0,
                                          AssetData(
                                            actualWorkerName,
                                            positionController.text,
                                            typeController.text,
                                            formatDate(loanedDate),
                                            isReturned
                                                ? formatDate(returnedDate)
                                                : '',
                                            isReturned,
                                            workerId: selectedWorkerId,
                                            profileImage: workerProfileImage,
                                            email: workerEmail,
                                            phone: workerPhone,
                                            cnic: workerCnic,
                                            dateOfJoining: workerDateOfJoining,
                                          ),
                                        );
                                        DummyData.assets.insert(0, newAsset);
                                      });
                                      await DummyData.saveToPrefs();
                                      setModalState(() => isSaving = false);
                                    } else {
                                      try {
                                        await _firestore.addAsset(
                                          firestoreAssetMap,
                                        );
                                      } catch (e) {
                                        setModalState(() => isSaving = false);
                                        if (!context.mounted) return;
                                        FlashySnackBar.show(
                                          context,
                                          message: 'failed_to_add_asset'.tr(
                                            namedArgs: {'error': e.toString()},
                                          ),
                                          isError: true,
                                        );
                                        return;
                                      }
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    FlashySnackBar.show(
                                      context,
                                      message: 'successfully_added_asset'.tr(
                                        namedArgs: {'name': actualWorkerName},
                                      ),
                                    );
                                    if (parentContext.mounted) {
                                      tryShowFirstMilestoneRateUs('asset');
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
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
                    _buildModalDropdown(
                      'worker_name'.tr(),
                      selectedWorkerName,
                      _workerNames,
                      'worker_name_hint'.tr(),
                      (val) {
                        setModalState(() {
                          selectedWorkerName = val;
                          if (val != null && _workersMap.containsKey(val)) {
                            final workerData = _workersMap[val]!;
                            positionController.text = _formatPositionTitleCase(
                              workerData['position'],
                            );
                          } else {
                            positionController.text = '';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'asset_type'.tr(),
                      typeController,
                      'asset_type_hint'.tr(),
                      maxLength: 50,
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'position'.tr(),
                      positionController,
                      'position_hint'.tr(),
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),

                    _buildModalDatePicker(
                      context,
                      'date_loaned'.tr(),
                      formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () {
                        _showCupertinoDatePicker(
                          context: context,
                          initialDate: loanedDate,
                          minimumDate: DateTime(2000),
                          maximumDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          title: 'date_loaned'.tr(),
                          onDateSelected: (picked) {
                            setModalState(() {
                              loanedDate = picked;
                              if (returnedDate.isBefore(loanedDate)) {
                                returnedDate = loanedDate;
                              }
                            });
                          },
                        );
                      },
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
                            if (val != null) {
                              setModalState(() {
                                isReturned = val;
                                if (isReturned &&
                                    returnedDate.isBefore(loanedDate)) {
                                  returnedDate = loanedDate;
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (isReturned) ...[
                      const SizedBox(height: 8),

                      _buildModalDatePicker(
                        context,
                        'returned_date'.tr(),
                        formatDate(returnedDate),
                        Colors.red,
                        () {
                          _showCupertinoDatePicker(
                            context: context,
                            initialDate: returnedDate,
                            minimumDate: loanedDate,
                            maximumDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            title: 'returned_date'.tr(),
                            onDateSelected: (picked) {
                              setModalState(() {
                                returnedDate = picked;
                              });
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
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
            decoration: InputDecoration.collapsed(
              hintText: hintText,
              hintStyle: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                fontFamily: 'SF Pro Display',
              ),
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
    final bool isEmpty = items.isEmpty;

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
              dropdownColor: Colors.white,
              value: isEmpty ? null : (items.contains(value) ? value : null),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              hint: Text(
                isEmpty ? 'no_workers_found'.tr() : hintText,
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              isExpanded: true,
              icon: const Icon(
                Icons.arrow_drop_down,
                color: Colors.black,
                size: 24,
              ),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
              items: items.map((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(
                    val,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
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
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        return ScaleTransition(
          scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: anim,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
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
                            color: const Color(
                              0xFF0247C4,
                            ).withValues(alpha: 0.18),
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
                                const Icon(
                                  CupertinoIcons.calendar,
                                  size: 20,
                                  color: Color(0xFF0247C4),
                                ),
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
                              onDateTimeChanged: (DateTime newDate) {
                                setPickerState(() {
                                  selected = newDate;
                                });
                              },
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
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
                      : (filtered.isEmpty
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
            height: 44,
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
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 400), () {
                        if (mounted) {
                          setState(() {
                            _searchQuery = val;
                          });
                        }
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
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
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
              final isPremium = await PreferencesService.isPremium();
              if (!mounted) return;
              if (!PremiumGate.canAddEntry(
                currentEntryCount: _assets.length,
                isPremium: isPremium,
                isGuest: isGuest,
              )) {
                if (!mounted) return;
                final upgraded = await PremiumGate.shouldShowUpgradeDialog(
                  context,
                );
                if (!mounted) return;
                if (upgraded == true) {
                  _showAddAssetModal(context);
                }
                return;
              }
              if (!mounted) return;
              _showAddAssetModal(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4),
              minimumSize: const Size(140, 44),
              fixedSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
            ),
            icon: Image.asset(
              'assets/asset_icon.png',
              width: 20,
              height: 20,
              color: Colors.white,
            ),
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
    final double tableHeight = (MediaQuery.of(context).size.height - 279).clamp(
      495.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
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
                    child: _tableHeader('worker_name'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('position'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('type_header'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('date_loaned'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('date_returned_header'.tr()),
                  ),
                ),
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
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildDataRow(assets[index], index);
              },
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

  Widget _buildDataRow(AssetData data, int index) {
    String? profileImage = data.profileImage;
    final matchKey = _optionForAsset(data) ?? '';
    if ((profileImage == null || profileImage.isEmpty) && matchKey.isNotEmpty) {
      final workerData = _workersMap[matchKey]!;
      profileImage = workerData['profileImage']?.toString();
    }
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
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  WorkerAvatar(
                    imageUrl: profileImage,
                    name: data.name,
                    size: 40,
                  ),
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
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                _formatPositionTitleCase(data.position),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                data.type,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                AppDateUtils.fromValueLocalized(
                  data.dateLoaned,
                  locale: context.locale.toString(),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF000000),
                  fontFamily: 'SF Pro Display',
                ),
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0, left: 8.0),
              child: Text(
                (data.dateReturned.trim().toLowerCase() == _inUseKey ||
                        data.dateReturned.trim().toLowerCase() == 'in_use' ||
                        data.dateReturned.trim() == '__IN_USE__' ||
                        data.dateReturned.trim().isEmpty)
                    ? 'in_use'.tr()
                    : AppDateUtils.fromValueLocalized(
                        data.dateReturned,
                        locale: context.locale.toString(),
                      ),
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
          if (value == 'edit') {
            final isGuest = _authService.currentUser?.isAnonymous ?? false;
            if (isGuest) {
              showGuestRestrictionDialog(context);
              return;
            }
            _showEditAssetModal(data);
          } else if (value == 'delete') {
            final isGuest = _authService.currentUser?.isAnonymous ?? false;
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
                  message: 'failed_to_delete_record'.tr(
                    namedArgs: {'error': e.toString()},
                  ),
                  isError: true,
                );
              }
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
                  'edit_asset'.tr(),
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

  static const _inUseKey = 'in_use';

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
        return DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
      }
    } catch (_) {}
    return null;
  }

  void _showEditAssetModal(AssetData data) {
    String? selectedWorkerName = _optionForAsset(data);
    final typeController = TextEditingController(text: data.type);
    final positionController = TextEditingController(
      text: _formatPositionTitleCase(data.position),
    );
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
                          onPressed: () => Navigator.of(context).pop(),
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
                          onPressed: isSaving
                              ? null
                              : () async {
                                  final selectedOption = selectedWorkerName;
                                  final assetType = typeController.text.trim();
                                  final position = positionController.text
                                      .trim();

                                  final allFieldsEmpty =
                                      (selectedOption == null ||
                                          selectedOption.trim().isEmpty) &&
                                      assetType.isEmpty &&
                                      position.isEmpty;

                                  if (allFieldsEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'please_fill_all_fields'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (selectedOption == null ||
                                      selectedOption.trim().isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {
                                          'field': 'worker_name'.tr(),
                                        },
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (assetType.isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {'field': 'asset_type'.tr()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (position.isEmpty) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'field_is_required'.tr(
                                        namedArgs: {'field': 'position'.tr()},
                                      ),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (isReturned &&
                                      returnedDate.isBefore(loanedDate)) {
                                    returnedDate = loanedDate;
                                  }

                                  final selectedWorkerData =
                                      _workersMap[selectedOption];
                                  if (selectedWorkerData == null) {
                                    FlashySnackBar.show(
                                      context,
                                      message: 'no_workers_found'.tr(),
                                      isError: true,
                                    );
                                    return;
                                  }

                                  if (selectedWorkerName != null &&
                                      typeController.text.isNotEmpty &&
                                      positionController.text.isNotEmpty) {
                                    setModalState(() => isSaving = true);
                                    final workerData = selectedWorkerData;
                                    final actualWorkerName =
                                        (workerData['name'] ?? '').toString();
                                    final selectedWorkerId =
                                        (workerData['id'] ?? '').toString();
                                    final workerProfileImage =
                                        workerData['profileImage']?.toString();
                                    final workerEmail = workerData['email']
                                        ?.toString();
                                    final workerPhone = workerData['phone']
                                        ?.toString();
                                    final workerCnic =
                                        (workerData['cnic'] ??
                                                workerData['nationalId'])
                                            ?.toString();
                                    final workerDateOfJoining = _adts(
                                      workerData['dateOfJoining'],
                                    );
                                    final workerJoiningDate = _adts(
                                      workerData['joiningDate'] ??
                                          workerData['dateOfJoining'],
                                    );
                                    final assetMap = {
                                      'workerId': selectedWorkerId,
                                      'name': actualWorkerName,
                                      'position': positionController.text,
                                      'type': typeController.text,
                                      'dateLoaned': loanedDate,
                                      'dateReturned': isReturned
                                          ? returnedDate
                                          : null,
                                      'isReturned': isReturned,
                                      'profileImage': workerProfileImage ?? '',
                                      'email': workerEmail ?? '',
                                      'phone': workerPhone ?? '',
                                      'cnic': workerCnic ?? '',
                                      'dateOfJoining': workerDateOfJoining,
                                    };
                                    final firestoreAssetMap = <String, dynamic>{
                                      ...assetMap,
                                      'position': position,
                                      'type': assetType,
                                      'dateOfJoining': workerJoiningDate,
                                    };
                                    final isGuest =
                                        _authService.currentUser?.isAnonymous ??
                                        false;
                                    if (isGuest) {
                                      setState(() {
                                        final idx = _assets.indexWhere(
                                          (a) => a.id == data.id,
                                        );
                                        if (idx != -1) {
                                          _assets[idx] = AssetData(
                                            actualWorkerName,
                                            positionController.text,
                                            typeController.text,
                                            formatDate(loanedDate),
                                            isReturned
                                                ? formatDate(returnedDate)
                                                : '',
                                            isReturned,
                                            id: data.id,
                                            workerId: selectedWorkerId,
                                            profileImage: workerProfileImage,
                                            email: workerEmail,
                                            phone: workerPhone,
                                            cnic: workerCnic,
                                            dateOfJoining: workerDateOfJoining,
                                          );
                                        }
                                        final dummyIdx = DummyData.assets
                                            .indexWhere(
                                              (asset) =>
                                                  (data.workerId ?? '')
                                                      .isNotEmpty
                                                  ? asset['workerId'] ==
                                                        data.workerId
                                                  : asset['name'] ==
                                                            data.name &&
                                                        asset['type'] ==
                                                            data.type,
                                            );
                                        if (dummyIdx != -1) {
                                          DummyData.assets[dummyIdx] = assetMap;
                                        }
                                      });
                                      await DummyData.saveToPrefs();
                                    } else {
                                      if (data.id != null) {
                                        try {
                                          await _firestore.updateAsset(
                                            data.id!,
                                            firestoreAssetMap,
                                          );
                                        } catch (e) {
                                          setModalState(() => isSaving = false);
                                          if (!context.mounted) return;
                                          FlashySnackBar.show(
                                            context,
                                            message: 'failed_to_update_asset'
                                                .tr(
                                                  namedArgs: {
                                                    'error': e.toString(),
                                                  },
                                                ),
                                            isError: true,
                                          );
                                          return;
                                        }
                                        setState(() {
                                          _assets = _assets.map((a) {
                                            if (a.id == data.id) {
                                              return AssetData(
                                                actualWorkerName,
                                                positionController.text,
                                                typeController.text,
                                                formatDate(loanedDate),
                                                isReturned
                                                    ? formatDate(returnedDate)
                                                    : '',
                                                isReturned,
                                                id: data.id,
                                                workerId: selectedWorkerId,
                                                profileImage:
                                                    workerProfileImage,
                                                email: workerEmail,
                                                phone: workerPhone,
                                                cnic: workerCnic,
                                                dateOfJoining:
                                                    workerDateOfJoining,
                                              );
                                            }
                                            return a;
                                          }).toList();
                                        });
                                      }
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop();
                                    FlashySnackBar.show(
                                      context,
                                      message: 'asset_updated'.tr(),
                                    );
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
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
                            final workerData = _workersMap[val]!;
                            positionController.text = _formatPositionTitleCase(
                              workerData['position'],
                            );
                          } else {
                            positionController.text = '';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'asset_type'.tr(),
                      typeController,
                      'asset_type_hint'.tr(),
                      maxLength: 50,
                    ),
                    const SizedBox(height: 16),
                    _buildModalTextField(
                      'position'.tr(),
                      positionController,
                      'position_hint'.tr(),
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),
                    _buildModalDatePicker(
                      context,
                      'date_loaned'.tr(),
                      formatDate(loanedDate),
                      const Color(0xFF0247C4),
                      () {
                        _showCupertinoDatePicker(
                          context: context,
                          initialDate: loanedDate,
                          minimumDate: DateTime(2000),
                          maximumDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          title: 'date_loaned'.tr(),
                          onDateSelected: (picked) {
                            setModalState(() {
                              loanedDate = picked;
                              if (returnedDate.isBefore(loanedDate)) {
                                returnedDate = loanedDate;
                              }
                            });
                          },
                        );
                      },
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
                            if (val != null) {
                              setModalState(() {
                                isReturned = val;
                                if (isReturned &&
                                    returnedDate.isBefore(loanedDate)) {
                                  returnedDate = loanedDate;
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    if (isReturned) ...[
                      const SizedBox(height: 8),
                      _buildModalDatePicker(
                        context,
                        'returned_date'.tr(),
                        formatDate(returnedDate),
                        Colors.red,
                        () {
                          _showCupertinoDatePicker(
                            context: context,
                            initialDate: returnedDate,
                            minimumDate: loanedDate,
                            maximumDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            title: 'returned_date'.tr(),
                            onDateSelected: (picked) {
                              setModalState(() {
                                returnedDate = picked;
                              });
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

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    final double containerHeight = (MediaQuery.of(context).size.height - 279)
        .clamp(495.0, 1200.0);
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
            colorFilter: const ColorFilter.mode(
              Color(0xFFCBCBCB),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isSearchEmpty ? 'no_search_results'.tr() : 'no_assets_found'.tr(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0247C4),
              fontFamily: 'SF Pro Display',
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

  AssetData(
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
