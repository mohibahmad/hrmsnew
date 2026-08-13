import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../services/error_reporter.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/time_off_service.dart';
import '../services/preferences_service.dart';
import '../widgets/sidebar_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../utils/ui_utils.dart';
import '../utils/file_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/date_time_utils.dart' as app_date_utils;
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../utils/guest_restriction.dart';
import '../utils/localization_helper.dart';

const Color primaryBlue = Color(0xFF0B51C1);
const Color bgGray = Color(0xFFF7F8FA);
const Color cardLightGray = Color(0xFFF3F5F8);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF64748B);

const Color greenPresent = Color(0xFF00C853);
const Color redAbsent = Color(0xFFF44336);
const Color orangeLeave = Color(0xFFFF7B00);
const Color pillGray = Color(0xFFE2E5EA);

String _localizedAttendanceStatus(String status) {
  switch (status) {
    case 'Present':
      return 'present'.tr();
    case 'Absent':
      return 'absent'.tr();
    case 'Leave':
      return 'leave'.tr();
    default:
      return status;
  }
}

String _localizedAttendanceType(String type) {
  switch (type) {
    case 'Sick Leave':
      return 'sick_leave_type'.tr();
    case 'Casual Leave':
      return 'casual_leave_type'.tr();
    case 'Medical Leave':
      return 'medical_leave_type'.tr();
    case 'Unpaid Leave':
      return 'unpaid_leave_type'.tr();
    case 'Annual Leave':
      return 'annual_leave'.tr();
    case 'Without Notice':
      return 'absent_without_notice'.tr();
    case 'Sick':
      return 'absent_sick'.tr();
    case 'Family Emergency':
      return 'absent_emergency'.tr();
    case 'Other':
      return 'absent_other'.tr();
    default:
      return type;
  }
}

class WorkersAttendanceScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final bool hideSidebar;
  final VoidCallback? onBack;
  const WorkersAttendanceScreen({
    super.key,
    this.onNotificationTap,
    this.onProfileTap,
    this.hideSidebar = false,
    this.onBack,
  });

  @override
  ConsumerState<WorkersAttendanceScreen> createState() =>
      _WorkersAttendanceScreenState();
}

class _WorkersAttendanceScreenState
    extends ConsumerState<WorkersAttendanceScreen> {
  final _searchController = TextEditingController();
  final GlobalKey _statusFilterButtonKey = GlobalKey();
  double? _statusFilterButtonWidth;
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  final String _selectedTimeframe = 'Today';
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _todayAttendance = [];
  List<Map<String, dynamic>> _periodAttendanceRecords = [];
  List<Map<String, dynamic>> _holidays = [];
  Set<int> _companyWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  List<Map<String, dynamic>> _timeOffRecords = [];
  bool _isLoading = true;
  bool _workersLoaded = false;
  bool _attendanceLoaded = false;
  bool _holidaysLoaded = false;
  bool _timeOffLoaded = false;
  bool _isDialogOpen = false;
  String? _errorMessage;

  bool _isPremium = PreferencesService.cachedIsPremium;
  late AuthService _authService;
  late FirestoreService _firestore;
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;
  StreamSubscription? _timeOffSub;
  bool _leaveNoticeShown = false;
  bool _autoMarkInProgress = false;
  bool _autoMarkDoneForToday = false;
  final Map<String, Map<String, dynamic>> _workersById = {};
  final Map<String, Map<String, dynamic>> _workersByEmail = {};

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  bool get _authenticatedDataLoaded =>
      _workersLoaded && _attendanceLoaded && _holidaysLoaded && _timeOffLoaded;

  @override
  void dispose() {
    _workersSub?.cancel();
    _attendanceSub?.cancel();
    _holidaysSub?.cancel();
    _timeOffSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
    final currentUser = _authService.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      _firestore
          .getUserProfile()
          .then((profile) {
            if (profile != null && mounted) {
              final pic = profile['profilePic'];
              if (pic != null && pic.toString().isNotEmpty) {
                AuthService.profilePicNotifier.value = pic.toString();
              }
            }
          })
          .catchError((_) {});
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      final companyWorkingDays =
          await PreferencesService.getCompanyWorkingDays();
      if (!mounted) return;
      final periodAttendance =
          List<Map<String, dynamic>>.from(DummyData.attendance).where((record) {
            return app_date_utils.AppDateUtils.isAttendanceRecordWithinPeriod(
              record,
              _selectedTimeframe,
            );
          }).toList();
      setState(() {
        _workers = List<Map<String, dynamic>>.from(DummyData.workers);
        _rebuildWorkerIndexes();
        _periodAttendanceRecords = periodAttendance;
        _todayAttendance = _latestAttendancePerWorker(periodAttendance);
        _holidays = DummyData.holidays.values
            .expand((l) => l)
            .cast<Map<String, dynamic>>()
            .toList();
        _companyWorkingDays = companyWorkingDays;
        _timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
        _isLoading = false;
      });
      _showActiveLeaveNotice();
      return;
    }

    final user = _authService.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      });
      return;
    }

    try {
      final profile = await _firestore.getUserProfile();
      if (mounted) {
        setState(() {
          _isPremium = profile?['isPremium'] == true;
        });
      }
    } catch (_) {
      final prefsPremium = await PreferencesService.isPremium();
      if (mounted) {
        setState(() {
          _isPremium = prefsPremium;
        });
      }
    }

    _workersSub = _firestore.workersStream.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _workers = snapshot.docs
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
              .toList();
          _rebuildWorkerIndexes();
          _workersLoaded = true;
          _periodAttendanceRecords = _periodAttendanceRecords
              .where(_attendanceBelongsToCurrentWorker)
              .toList();
          _todayAttendance = _latestAttendancePerWorker(
            _periodAttendanceRecords,
          );
          _isLoading = _errorMessage == null && !_authenticatedDataLoaded;
        });
        _showActiveLeaveNotice();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      },
    );

    final attendanceNow = DateTime.now();
    final attendancePeriodStart = app_date_utils.AppDateUtils.periodStart(
      _selectedTimeframe,
      attendanceNow,
    );
    final periodEndDate = app_date_utils.AppDateUtils.periodEnd(
      _selectedTimeframe,
      attendanceNow,
    );
    final attendancePeriodEnd = DateTime(
      periodEndDate.year,
      periodEndDate.month,
      periodEndDate.day,
      23,
      59,
      59,
      999,
    );
    _attendanceSub = _firestore
        .attendanceStreamForPeriod(
          start: attendancePeriodStart,
          end: attendancePeriodEnd,
        )
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              final sortedList = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              sortedList.sort((a, b) {
                final aTime = a['createdAt'];
                final bTime = b['createdAt'];
                if (aTime == null && bTime == null) return 0;
                if (aTime == null) return 1;
                if (bTime == null) return -1;
                if (aTime is Timestamp && bTime is Timestamp) {
                  return bTime.compareTo(aTime);
                }
                return 0;
              });
              _attendanceLoaded = true;
              final filtered = sortedList.where((att) {
                if (!_attendanceBelongsToCurrentWorker(att)) return false;
                return app_date_utils
                    .AppDateUtils.isAttendanceRecordWithinPeriod(
                  att,
                  _selectedTimeframe,
                );
              }).toList();
              _periodAttendanceRecords = filtered;
              _todayAttendance = _latestAttendancePerWorker(filtered);
              _isLoading = _errorMessage == null && !_authenticatedDataLoaded;
            });
            _autoMarkPlannedLeaves();
          },
          onError: (e) {
            if (!mounted) return;
            setState(() {
              _errorMessage = e.toString();
              _isLoading = false;
            });
          },
        );

    _holidaysSub = _firestore.holidaysStream.listen(
      (snapshot) {
        if (!mounted) return;
        var companyWorkingDays = _companyWorkingDays;
        final holidays = <Map<String, dynamic>>[];
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['type'] == 'company_work_days') {
            final rawWorkingDays = data['workingDays'];
            final savedDays = rawWorkingDays is List
                ? rawWorkingDays
                      .whereType<num>()
                      .map((day) => day.toInt())
                      .where(
                        (day) =>
                            day >= DateTime.monday && day <= DateTime.sunday,
                      )
                      .toSet()
                : <int>{};
            if (savedDays.isNotEmpty) companyWorkingDays = savedDays;
            continue;
          }
          holidays.add({...data, 'id': doc.id});
        }
        setState(() {
          _holidays = holidays;
          _companyWorkingDays = companyWorkingDays;
          _holidaysLoaded = true;
          _isLoading = _errorMessage == null && !_authenticatedDataLoaded;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      },
    );

    _timeOffSub = _firestore.timeoffStream.listen(
      (snapshot) {
        if (!mounted) return;
        final now = DateTime.now();
        final previousTodayLeaveKeys =
            TimeOffService.activeLeaveAssignmentKeysForDate(
              _plannedTimeOffRecords,
              now,
            );
        final newRecords = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        setState(() {
          _timeOffRecords = newRecords;
          _timeOffLoaded = true;
          _isLoading = _errorMessage == null && !_authenticatedDataLoaded;
        });
        final currentTodayLeaveKeys =
            TimeOffService.activeLeaveAssignmentKeysForDate(
              _plannedTimeOffRecords,
              now,
            );
        final todayAssignmentsChanged =
            previousTodayLeaveKeys.length != currentTodayLeaveKeys.length ||
            !previousTodayLeaveKeys.containsAll(currentTodayLeaveKeys);
        if (todayAssignmentsChanged) {
          _autoMarkDoneForToday = false;
          _leaveNoticeShown = false;
          _autoMarkPlannedLeaves();
        }
        _showActiveLeaveNotice();
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      },
    );
  }

  void _showActiveLeaveNotice() {
    if (_leaveNoticeShown || !mounted) return;
    if (!_isGuest && (!_workersLoaded || !_timeOffLoaded)) return;
    _autoMarkPlannedLeaves();
    final active = <Map<String, dynamic>>[];
    for (final worker in _workers) {
      final leave = _activePlannedTimeOffForWorker(worker);
      if (leave != null) {
        active.add({...leave, 'workerName': worker['name']});
      }
    }
    if (active.isEmpty) return;
    _leaveNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final leave = active.first;
      final rawType = (leave['action'] ?? leave['type'] ?? 'Leave').toString();
      final workerName = (leave['workerName'] ?? '').toString();
      final extra = active.length > 1 ? ' (+${active.length - 1})' : '';
      FlashySnackBar.show(
        context,
        title: '${_localizedAttendanceType(rawType)} • $workerName$extra',
        message: 'worker_on_time_off_attendance_blocked'.tr(),
      );
    });
  }

  bool _isAttendanceManagedTimeOff(Map<String, dynamic> record) {
    return (record['source'] ?? '').toString().trim().toLowerCase() ==
        'attendance';
  }

  List<Map<String, dynamic>> get _plannedTimeOffRecords => _timeOffRecords
      .where((record) => !_isAttendanceManagedTimeOff(record))
      .toList();

  Map<String, dynamic>? _activePlannedTimeOffForWorker(
    Map<String, dynamic> worker,
  ) {
    if (_isGuest) {
      return TimeOffService.activeLeaveForWorker(
        worker,
        _plannedTimeOffRecords,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final record in _plannedTimeOffRecords) {
      if (!TimeOffService.isActiveRecord(record)) continue;
      if (!_authenticatedRecordBelongsToWorker(record, worker)) continue;
      if (TimeOffService.selectedDatesForRecord(record).contains(today)) {
        return record;
      }
    }
    return null;
  }

  bool _isWorkerOnPlannedTimeOff(Map<String, dynamic> worker) {
    return _activePlannedTimeOffForWorker(worker) != null;
  }

  Future<void> _autoMarkPlannedLeaves() async {
    if (_isGuest || _autoMarkInProgress || _autoMarkDoneForToday) return;
    if (!_workersLoaded || !_timeOffLoaded || !_attendanceLoaded) return;
    _autoMarkInProgress = true;
    _autoMarkDoneForToday = true;
    try {
      final now = DateTime.now();
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final marked = <Map<String, dynamic>>[];
      for (final worker in _workers) {
        final leave = _activePlannedTimeOffForWorker(worker);
        if (leave == null) continue;
        final workerId = (worker['workerId'] ?? worker['id'] ?? '')
            .toString()
            .trim();
        if (workerId.isEmpty) continue;
        final leaveType = TimeOffService.normalizeLeaveType(
          (leave['action'] ?? leave['type'] ?? 'Sick Leave').toString(),
        );
        final existingAttendance = _todayAttendance
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (record) =>
                  record != null &&
                  _authenticatedRecordBelongsToWorker(record, worker),
              orElse: () => null,
            );
        final existingStatus = (existingAttendance?['status'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final existingType = TimeOffService.normalizeLeaveType(
          (existingAttendance?['type'] ?? '').toString(),
        );
        if (existingStatus == 'leave' && existingType == leaveType) continue;

        final attendanceRecord = AttendanceService.applyApprovedTimeOff(
          attendanceRecord: <String, dynamic>{
            if (existingAttendance != null) ...existingAttendance,
            'workerId': workerId,
            'name': worker['name'] ?? 'Worker',
            'workerName': worker['name'] ?? 'Worker',
            'email': worker['email'] ?? '',
            'position': worker['position'] ?? worker['role'] ?? 'Worker',
            'contact': worker['phone'] ?? worker['contact'] ?? '',
            'profileImage': worker['profileImage'] ?? '',
            'attendanceDate': todayKey,
          },
          timeOffRecord: leave,
          automaticDescription: 'auto_marked_on_leave'.tr(),
        );
        try {
          final result = await _firestore.saveAttendanceWithLeaveSync(
            attendanceRecord: attendanceRecord,
            attendanceId: (existingAttendance?['id'] ?? '').toString(),
            workerId: workerId,
          );
          marked.add({...attendanceRecord, 'id': result.attendanceId});
        } catch (error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'AutoMarkPlannedLeave:$workerId',
          );
        }
      }
      if (marked.isNotEmpty && mounted) {
        setState(() {
          final updated = List<Map<String, dynamic>>.from(_todayAttendance);
          for (final markedRecord in marked) {
            final worker = _resolveWorkerData(markedRecord);
            updated.removeWhere(
              (record) => _authenticatedRecordBelongsToWorker(record, worker),
            );
            updated.add(markedRecord);
          }
          _todayAttendance = updated;
        });
      }
    } finally {
      _autoMarkInProgress = false;
    }
  }

  bool _authenticatedRecordBelongsToWorker(
    Map<String, dynamic> record,
    Map<String, dynamic> worker,
  ) {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    // `record['id']` is the attendance document ID, not the worker ID.
    // Treating it as a worker ID prevents legacy records (which rely on email)
    // from resolving to their worker profile and drops fields such as leaves.
    final recordWorkerId = (record['workerId'] ?? record['userId'] ?? '')
        .toString()
        .trim();
    if (recordWorkerId.isNotEmpty) {
      return workerId.isNotEmpty && recordWorkerId == workerId;
    }

    final workerEmail = WorkerIdentity.normalizeEmail(worker['email']);
    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
    if (recordEmail.isNotEmpty) {
      return workerEmail.isNotEmpty && recordEmail == workerEmail;
    }

    final workerName = WorkerIdentity.normalizeName(worker['name']);
    final recordName = WorkerIdentity.normalizeName(
      record['name'] ?? record['workerName'],
    );
    if (workerName.isEmpty || recordName.isEmpty || workerName != recordName) {
      return false;
    }

    final matchingNames = _workers.where((item) {
      return WorkerIdentity.normalizeName(item['name']) == workerName;
    }).length;
    return matchingNames == 1;
  }

  Future<bool> _syncAttendanceAnnualLeave({
    required Map<String, dynamic> worker,
    required Map<String, dynamic> originalAttendance,
    required String selectedStatus,
    required String leaveType,
    required String reason,
    required Map<String, dynamic> attendanceData,
    String? attendanceId,
  }) async {
    final workerId = (worker['workerId'] ?? worker['id'] ?? '')
        .toString()
        .trim();
    if (workerId.isEmpty) {
      throw StateError('Missing worker identity');
    }
    // Use a fresh Firestore snapshot for every edit transition. The dialog can
    // open before the realtime Time Off stream has delivered its first event;
    // relying on that local list is what made an existing leave look new.
    final syncTimeOffRecords = await _firestore.getTimeoffOnce();

    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    String dateOnlyString(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final linkedTimeOffId = (originalAttendance['timeOffId'] ?? '')
        .toString()
        .trim();
    Map<String, dynamic>? existing;
    if (linkedTimeOffId.isNotEmpty) {
      for (final record in syncTimeOffRecords) {
        if ((record['id'] ?? '').toString().trim() == linkedTimeOffId &&
            TimeOffService.isActiveRecord(record)) {
          existing = record;
          break;
        }
      }
    }
    existing ??= TimeOffService.activeLeaveForWorker(
      worker,
      syncTimeOffRecords,
      onDate: normalizedToday,
    );

    final shouldHaveLeave = selectedStatus == 'Leave';
    final existingId = (existing?['id'] ?? '').toString().trim();
    final oldStatus = (originalAttendance['status'] ?? '').toString().trim();
    final oldType = TimeOffService.normalizeLeaveType(
      (originalAttendance['type'] ?? '').toString(),
    );
    final selectedType = TimeOffService.normalizeLeaveType(leaveType);
    final existingType = TimeOffService.normalizeLeaveType(
      (existing?['type'] ?? existing?['action'] ?? '').toString(),
    );
    final keepsExistingReservation =
        shouldHaveLeave && existing != null && existingType == selectedType;
    final keepsLegacyManualLeave =
        shouldHaveLeave &&
        existing == null &&
        oldStatus == 'Leave' &&
        oldType == selectedType;
    final writesTimeOff =
        shouldHaveLeave && !keepsExistingReservation && !keepsLegacyManualLeave;
    final existingDates = existing == null
        ? const <DateTime>[]
        : TimeOffService.selectedDatesForRecord(existing);
    final remainingExistingDates =
        existingDates
            .where(
              (date) =>
                  date.year != normalizedToday.year ||
                  date.month != normalizedToday.month ||
                  date.day != normalizedToday.day,
            )
            .toList()
          ..sort();
    final updatesRemainingTimeOff =
        existingId.isNotEmpty &&
        remainingExistingDates.isNotEmpty &&
        (writesTimeOff || !shouldHaveLeave);
    final deletesTimeOff =
        !shouldHaveLeave &&
        existingId.isNotEmpty &&
        remainingExistingDates.isEmpty;
    final createsSplitTimeOff = writesTimeOff && updatesRemainingTimeOff;
    final hasTimeOffChange =
        writesTimeOff || deletesTimeOff || updatesRemainingTimeOff;

    if (writesTimeOff &&
        TimeOffService.remainingForType(
              worker,
              syncTimeOffRecords,
              selectedType,
              excludingRecordId: existingId.isEmpty ? null : existingId,
            ) <
            1) {
      return false;
    }

    final projectedRecords = syncTimeOffRecords
        .where(
          (record) =>
              !hasTimeOffChange ||
              existing == null ||
              (existingId.isNotEmpty
                  ? record['id']?.toString() != existingId
                  : !identical(record, existing)),
        )
        .map(Map<String, dynamic>.from)
        .toList();

    Map<String, dynamic>? attendanceTimeOff;
    if (writesTimeOff) {
      final dateKey =
          '${normalizedToday.year}-'
          '${normalizedToday.month.toString().padLeft(2, '0')}-'
          '${normalizedToday.day.toString().padLeft(2, '0')}';
      attendanceTimeOff = <String, dynamic>{
        'workerId': workerId,
        'name': worker['name'] ?? 'Worker',
        'workerName': worker['name'] ?? 'Worker',
        'email': worker['email'] ?? '',
        'position': worker['position'] ?? worker['role'] ?? 'Worker',
        'contact': worker['phone'] ?? worker['contact'] ?? '',
        'action': leaveType,
        'type': leaveType,
        'startDate': dateKey,
        'endDate': dateKey,
        'selectedDates': [normalizedToday],
        'notes': reason,
        'requestedDays': 1,
        'status': 'Approved',
        'isPaidLeave': true,
        'source': 'attendance',
        'attendanceDate': dateKey,
        'workerAvatar': worker['profileImage'] ?? '',
      };
      projectedRecords.add({
        ...attendanceTimeOff,
        'id': existingId.isNotEmpty && !createsSplitTimeOff
            ? existingId
            : 'pending_attendance_leave',
      });
    }

    Map<String, dynamic>? remainingTimeOffRecord;
    if (updatesRemainingTimeOff && existing != null) {
      remainingTimeOffRecord = Map<String, dynamic>.from(existing)
        ..remove('id')
        ..['selectedDates'] = remainingExistingDates
            .map(dateOnlyString)
            .toList()
        ..['startDate'] = dateOnlyString(remainingExistingDates.first)
        ..['endDate'] = dateOnlyString(remainingExistingDates.last)
        ..['requestedDays'] = remainingExistingDates.length;
      projectedRecords.add({...remainingTimeOffRecord, 'id': existingId});
    }

    final Map<String, dynamic>? balanceUpdate = hasTimeOffChange
        ? TimeOffService.canonicalWorkerLeaveFields(
            worker,
            remainingBalances:
                TimeOffService.remainingBalancesFromAssignedRecords(
                  worker,
                  projectedRecords,
                ),
          )
        : null;

    final attendancePayload = Map<String, dynamic>.from(attendanceData)
      ..['source'] = 'manual';
    if (shouldHaveLeave && existingId.isNotEmpty) {
      attendancePayload['timeOffId'] = existingId;
    } else {
      attendancePayload['timeOffId'] = FieldValue.delete();
    }

    final result = await _firestore.saveAttendanceWithLeaveSync(
      attendanceRecord: attendancePayload,
      attendanceId: attendanceId,
      timeOffId: existingId.isEmpty ? null : existingId,
      timeOffRecord: writesTimeOff ? attendanceTimeOff : null,
      remainingTimeOffRecord: remainingTimeOffRecord,
      createNewTimeOff: createsSplitTimeOff,
      deleteTimeOff: deletesTimeOff,
      workerId: workerId,
      balance: balanceUpdate,
    );
    final savedTimeOffId = result.timeOffId.isEmpty
        ? existingId
        : result.timeOffId;

    if (!mounted) return true;
    setState(() {
      _timeOffRecords = projectedRecords
          .where(
            (record) => record['id']?.toString() != 'pending_attendance_leave',
          )
          .toList();
      if (writesTimeOff && attendanceTimeOff != null) {
        _timeOffRecords.insert(0, {...attendanceTimeOff, 'id': savedTimeOffId});
      }
      final savedAttId = result.attendanceId.isNotEmpty
          ? result.attendanceId
          : (attendanceId ?? '');
      final existingIndex = _todayAttendance.indexWhere(
        (r) =>
            (r['id'] ?? '').toString().trim() == savedAttId ||
            (attendanceId != null &&
                attendanceId.isNotEmpty &&
                (r['id'] ?? '').toString().trim() == attendanceId) ||
            _authenticatedRecordBelongsToWorker(r, worker),
      );

      final cleanAttData = Map<String, dynamic>.from(attendancePayload);
      cleanAttData['source'] = 'manual';
      if (shouldHaveLeave && savedTimeOffId.isNotEmpty) {
        cleanAttData['timeOffId'] = savedTimeOffId;
      } else {
        cleanAttData.remove('timeOffId');
      }
      if (selectedStatus != 'Leave') {
        cleanAttData.remove('type');
        cleanAttData.remove('desc');
      }

      final updatedLocalRecord = <String, dynamic>{
        if (existingIndex != -1) ..._todayAttendance[existingIndex],
        ...cleanAttData,
        if (savedAttId.isNotEmpty) 'id': savedAttId,
      };
      if (selectedStatus != 'Leave') {
        updatedLocalRecord.remove('type');
        updatedLocalRecord.remove('desc');
        updatedLocalRecord.remove('timeOffId');
      }

      if (existingIndex != -1) {
        _todayAttendance[existingIndex] = updatedLocalRecord;
      } else if (savedAttId.isNotEmpty) {
        _todayAttendance.insert(0, updatedLocalRecord);
      }

      final workerIndex = _workers.indexWhere(
        (item) =>
            (item['id'] ?? item['workerId'] ?? '').toString().trim() ==
            workerId,
      );
      if (workerIndex != -1 && balanceUpdate != null) {
        _workers[workerIndex] = {..._workers[workerIndex], ...balanceUpdate};
      }
      _rebuildWorkerIndexes();
    });
    return true;
  }

  String _getWorkerStatus(Map<String, dynamic> worker) {
    final attRecord = _todayAttendance.cast<Map<String, dynamic>?>().firstWhere(
      (attendance) {
        if (attendance == null) return false;
        final belongs = _isGuest
            ? (WorkerIdentity.normalizeEmail(attendance['email']) ==
                      WorkerIdentity.normalizeEmail(worker['email']) ||
                  ((worker['id'] ?? '').toString().trim().isNotEmpty &&
                      (attendance['workerId'] ?? '').toString().trim() ==
                          (worker['id'] ?? '').toString().trim()))
            : _authenticatedRecordBelongsToWorker(attendance, worker);
        if (!belongs) return false;
        return AttendanceService.isRecordForDate(attendance, DateTime.now());
      },
      orElse: () => null,
    );

    if (attRecord != null) {
      final attStatus = attRecord['status']?.toString().trim() ?? '';
      final normAttStatus = attStatus.toLowerCase();
      if (normAttStatus == 'present' || normAttStatus == 'p') return 'Present';
      if (normAttStatus == 'absent' || normAttStatus == 'a') return 'Absent';
      if (normAttStatus == 'leave' ||
          normAttStatus == 'l' ||
          normAttStatus == 'approved') {
        return 'Leave';
      }
    }

    if (!AttendanceService.workerExistedOnDate(worker, DateTime.now())) {
      return '';
    }

    if (_isWorkerOnPlannedTimeOff(worker)) {
      return 'Leave';
    }

    final directStatus = worker['status']?.toString().trim() ?? '';
    if (_isGuest && directStatus.isNotEmpty && directStatus != '*****') {
      return directStatus;
    }
    final directLower = directStatus.toLowerCase();
    if (!_isGuest &&
        const {'present', 'absent', 'leave'}.contains(directLower)) {
      if (directLower == 'present') return 'Present';
      if (directLower == 'absent') return 'Absent';
      if (directLower == 'leave') return 'Leave';
    }

    return '';
  }

  bool _isTodayAttendance(Map<String, dynamic> record) {
    final date = app_date_utils.AppDateUtils.attendanceRecordDate(record);
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  Map<String, dynamic>? get _todayHoliday {
    final now = DateTime.now();
    final todayHolidays = <Map<String, dynamic>>[];
    for (final h in _holidays) {
      if (h['isEnabled'] == false) continue;
      final isRecurring = h['isRecurring'] == true;
      final holidayDate = app_date_utils.AppDateUtils.holidayRecordDate(
        h,
        fallbackYear: now.year,
      );
      if (holidayDate == null) continue;
      if (!isRecurring && holidayDate.year != now.year) {
        continue;
      }
      if (holidayDate.month == now.month && holidayDate.day == now.day) {
        todayHolidays.add(h);
      }
    }
    if (todayHolidays.isEmpty) return null;
    if (todayHolidays.length == 1) return todayHolidays.first;
    final combined = Map<String, dynamic>.from(todayHolidays.first);
    combined['name'] = todayHolidays
        .map((h) => (h['name'] ?? '').toString())
        .join(' and ');
    return combined;
  }

  Map<String, dynamic>? get _todayNonWorkingDay {
    final holiday = _todayHoliday;
    if (holiday != null) return holiday;
    if (!_companyWorkingDays.contains(DateTime.now().weekday)) {
      return {
        'name': 'company_off_day'.tr(),
        'isCompanyOffDay': true,
        'isEnabled': true,
      };
    }
    return null;
  }

  void _rebuildWorkerIndexes() {
    _workersById.clear();
    _workersByEmail.clear();
    for (final worker in _workers) {
      for (final key in [worker['workerId'], worker['id']]) {
        final id = (key ?? '').toString().trim();
        if (id.isNotEmpty) _workersById.putIfAbsent(id, () => worker);
      }
      final email = WorkerIdentity.normalizeEmail(worker['email']);
      if (email.isNotEmpty) _workersByEmail.putIfAbsent(email, () => worker);
    }
  }

  Map<String, dynamic>? _findWorkerForAttendanceRecord(
    Map<String, dynamic> record,
  ) {
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    if (recordWorkerId.isNotEmpty) {
      final worker = _workersById[recordWorkerId];
      if (worker != null) return worker;
      if (!_isGuest) return null;
    }

    final recordEmail = WorkerIdentity.normalizeEmail(record['email']);
    if (recordEmail.isNotEmpty) {
      final worker = _workersByEmail[recordEmail];
      if (worker != null) return worker;
    }

    if (_isGuest) return null;

    final recordName = WorkerIdentity.normalizeName(
      record['name'] ?? record['workerName'],
    );
    if (recordName.isEmpty) return null;
    Map<String, dynamic>? match;
    var matches = 0;
    for (final worker in _workers) {
      if (WorkerIdentity.normalizeName(worker['name']) == recordName) {
        match = worker;
        matches++;
        if (matches > 1) return null;
      }
    }
    return matches == 1 ? match : null;
  }

  List<Map<String, dynamic>> _latestAttendancePerWorker(
    List<Map<String, dynamic>> records,
  ) {
    final latestByWorker = <String, Map<String, dynamic>>{};
    for (final attendance in records) {
      final recordWorkerId = (attendance['workerId'] ?? '').toString().trim();
      final recordEmail = WorkerIdentity.normalizeEmail(attendance['email']);
      final recordName = WorkerIdentity.normalizeName(attendance['name']);

      final matchingWorker = _findWorkerForAttendanceRecord(attendance);
      if (matchingWorker == null) continue;
      if (!AttendanceService.workerExistedOnRecordDate(
        worker: matchingWorker,
        attendanceRecord: attendance,
      )) {
        continue;
      }

      final canonicalWorkerId = (matchingWorker['id'] ?? '').toString().trim();
      final identityKey = canonicalWorkerId.isNotEmpty
          ? 'id:$canonicalWorkerId'
          : recordWorkerId.isNotEmpty
          ? 'id:$recordWorkerId'
          : recordEmail.isNotEmpty
          ? 'email:$recordEmail'
          : 'name:$recordName';
      if (identityKey == 'name:') continue;

      final existing = latestByWorker[identityKey];
      if (existing == null) {
        latestByWorker[identityKey] = attendance;
        continue;
      }

      final currentDate = app_date_utils.AppDateUtils.attendanceRecordDate(
        attendance,
      );
      final existingDate = app_date_utils.AppDateUtils.attendanceRecordDate(
        existing,
      );
      final isNewer =
          currentDate != null &&
          (existingDate == null ||
              currentDate.isAfter(existingDate) ||
              (currentDate.isAtSameMomentAs(existingDate) &&
                  (attendance['id'] ?? '').toString().compareTo(
                        (existing['id'] ?? '').toString(),
                      ) >
                      0));
      if (isNewer) {
        latestByWorker[identityKey] = attendance;
      }
    }
    return latestByWorker.values.toList();
  }

  Map<String, dynamic> _resolveWorkerData(
    Map<String, dynamic> attendanceOrWorker,
  ) {
    final worker = _findWorkerForAttendanceRecord(attendanceOrWorker);

    if (worker == null) {
      return Map<String, dynamic>.from(attendanceOrWorker);
    }
    return {...attendanceOrWorker, ...worker};
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final list = _workers.where((worker) {
      if (!AttendanceService.workerExistedOnDate(worker, DateTime.now())) {
        return false;
      }
      if (!AttendanceService.isEligibleForAttendance(worker)) {
        return false;
      }
      final name = (worker['name'] ?? '').toString().toLowerCase();
      final role = (worker['role'] ?? worker['position'] ?? '')
          .toString()
          .toLowerCase();
      final email = (worker['email'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final workerStatus = _getWorkerStatus(worker).toLowerCase();
      return name.contains(query) ||
          role.contains(query) ||
          email.contains(query) ||
          workerStatus.contains(query);
    }).toList();

    list.sort((a, b) {
      final statusA = _getWorkerStatus(a);
      final statusB = _getWorkerStatus(b);
      final isMarkedA = statusA.isNotEmpty;
      final isMarkedB = statusB.isNotEmpty;

      if (isMarkedA != isMarkedB) {
        return isMarkedA ? 1 : -1;
      }

      final nameA = (a['name'] ?? '').toString().trim().toLowerCase();
      final nameB = (b['name'] ?? '').toString().trim().toLowerCase();
      return nameA.compareTo(nameB);
    });

    return list;
  }

  Set<String> get _currentWorkerIds {
    return _workers
        .map((worker) => (worker['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  bool _attendanceBelongsToCurrentWorker(Map<String, dynamic> record) {
    if (_isGuest) {
      final ids = _currentWorkerIds;
      if (ids.isEmpty) return true;
      final workerId = (record['workerId'] ?? '').toString().trim();
      if (workerId.isEmpty) return true;
      return ids.contains(workerId);
    }

    if (!_workersLoaded) return true;
    return _findWorkerForAttendanceRecord(record) != null;
  }

  List<Map<String, dynamic>> get _visibleTodayAttendance {
    final list = _todayAttendance
        .where((record) => _attendanceBelongsToCurrentWorker(record))
        .map((record) {
          final worker = _resolveWorkerData(record);
          final leave = _activePlannedTimeOffForWorker(worker);
          if (leave == null) return record;
          return AttendanceService.applyApprovedTimeOff(
            attendanceRecord: record,
            timeOffRecord: leave,
            automaticDescription: 'auto_marked_on_leave'.tr(),
          );
        })
        .where((record) {
          if (_selectedStatusFilter != 'All') {
            final status = (record['status'] ?? '').toString().toLowerCase();
            if (status != _selectedStatusFilter.toLowerCase()) return false;
          }
          final q = _searchQuery.trim().toLowerCase();
          if (q.isNotEmpty) {
            final name = (record['name'] ?? record['workerName'] ?? '')
                .toString()
                .toLowerCase();
            final role = (record['role'] ?? record['position'] ?? '')
                .toString()
                .toLowerCase();
            final email = (record['email'] ?? '').toString().toLowerCase();
            final statusText = (record['status'] ?? '')
                .toString()
                .toLowerCase();
            if (!(name.contains(q) ||
                role.contains(q) ||
                email.contains(q) ||
                statusText.contains(q))) {
              return false;
            }
          }
          return true;
        })
        .toList();

    list.sort((a, b) {
      final nameA = (a['name'] ?? a['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final nameB = (b['name'] ?? b['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return nameA.compareTo(nameB);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final holiday = _todayNonWorkingDay;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: bgGray,
        body: Center(child: CircularProgressIndicator(color: primaryBlue)),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: bgGray,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'error_occurred'.tr(namedArgs: {'error': _errorMessage!}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textDark,
                fontSize: 15,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgGray,
      resizeToAvoidBottomInset: false,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.hideSidebar)
            SidebarWidget(
              key: ValueKey('sidebar_${context.locale.languageCode}'),
              selectedIndex: 2,
              selectedSubIndex: 0,
              isGuest: _authService.currentUser?.isAnonymous ?? false,
              isPremium: _isPremium,
              onItemSelected: (index, {subIndex}) {
                _isDialogOpen = false;
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => HomeScreen(
                      initialIndex: index == 2 ? 2 : index,
                      initialSubIndex: index == 2 ? (subIndex ?? 0) : 0,
                    ),
                  ),
                  (route) => false,
                );
              },
              onBackToLogin: () async {
                try {
                  await _authService.signOut(preserveBiometricLogin: true);
                } catch (error, stackTrace) {
                  ErrorReporter.report(
                    error,
                    stackTrace,
                    context: 'workersAttendanceSignOut',
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),

          Expanded(
            child: IgnorePointer(
              ignoring: _isDialogOpen,
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 24, 40, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSearchBar(),
                          const SizedBox(height: 32),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 65,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 43,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'worker_attendance'.tr(),
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: textDark,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFFFFF),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFEEEEEE),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Expanded(
                                                child:
                                                    _buildWorkerAttendanceBody(
                                                      holiday,
                                                    ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                Expanded(
                                  flex: 35,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        height: 43,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Text(
                                              'today_attendance'.tr(),
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: textDark,
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            _buildStatusFilterDropdown(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Color(0xFFFFFFFF),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFEEEEEE),
                                            ),
                                          ),
                                          child: _buildTodayAttendanceBody(
                                            holiday,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveDirectAttendance(
    BuildContext context,
    Map<String, dynamic> data,
    String status,
  ) async {
    final workerData = _resolveWorkerData(data);
    final workerId = (workerData['id'] ?? workerData['workerId'] ?? '')
        .toString()
        .trim();
    final name = (workerData['name'] ?? '').toString();
    final email = (workerData['email'] ?? '').toString();
    final normalizedEmail = WorkerIdentity.normalizeEmail(email);

    var todayRecord = AttendanceService.recordsForWorker(
      worker: workerData,
      attendanceRecords: _todayAttendance,
    ).firstWhere(_isTodayAttendance, orElse: () => <String, dynamic>{});
    if (todayRecord.isEmpty &&
        normalizedEmail.isNotEmpty &&
        (_isGuest || workerId.isEmpty)) {
      todayRecord = _todayAttendance.firstWhere(
        (record) =>
            WorkerIdentity.normalizeEmail(record['email']) == normalizedEmail &&
            _isTodayAttendance(record),
        orElse: () => <String, dynamic>{},
      );
    }
    final attendanceId = (todayRecord['id'] ?? '').toString().trim();

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    final type = status == 'Leave' ? 'Annual Leave' : null;
    final String? desc = null;

    try {
      if (!isGuest) {
        if (workerId.isEmpty) return;

        final attendanceData = <String, dynamic>{
          'workerId': workerId,
          'name': name,
          'email': email,
          'role': workerData['role'] ?? workerData['position'] ?? '',
          'status': status,
          'attendanceType': workerData['type2'] ?? 'Remote',
          'workType': workerData['type1'] ?? 'Full Time',
          'profileImage': workerData['profileImage'],
        };
        if (type != null) {
          attendanceData['type'] = type;
        } else {
          attendanceData['type'] = FieldValue.delete();
        }
        if (desc != null && desc.isNotEmpty) {
          attendanceData['desc'] = desc;
        } else {
          attendanceData['desc'] = FieldValue.delete();
        }

        final leaveBalanceSynced = await _syncAttendanceAnnualLeave(
          worker: workerData,
          originalAttendance: todayRecord,
          selectedStatus: status,
          leaveType: type ?? 'Annual Leave',
          reason: desc ?? '',
          attendanceData: attendanceData,
          attendanceId: attendanceId,
        );

        if (!leaveBalanceSynced) {
          if (!context.mounted) return;
          FlashySnackBar.show(
            context,
            message: 'requested_leaves_exceed_available'.tr(),
            isError: true,
          );
          return;
        }
      } else {
        final wIdx = DummyData.workers.indexWhere((worker) {
          final id = (worker['id'] ?? '').toString().trim();
          if (workerId.isNotEmpty && id.isNotEmpty) {
            return workerId == id;
          }
          return (worker['email'] ?? '').toString().trim().toLowerCase() ==
              normalizedEmail;
        });
        if (wIdx != -1) {
          DummyData.workers[wIdx]['status'] = status;
        }
        final index = DummyData.attendance.indexWhere(
          (element) =>
              (element['email'] ?? '').toString().trim().toLowerCase() ==
                  normalizedEmail &&
              _isTodayAttendance(element),
        );
        if (index != -1) {
          DummyData.attendance[index]['status'] = status;
          if (type != null) {
            DummyData.attendance[index]['type'] = type;
          } else {
            DummyData.attendance[index].remove('type');
          }
          if (desc != null && desc.isNotEmpty) {
            DummyData.attendance[index]['desc'] = desc;
          } else {
            DummyData.attendance[index].remove('desc');
          }
        } else {
          DummyData.attendance.add({
            'workerId': workerId,
            'name': name,
            'email': email,
            'status': status,
            if (type != null) 'type': type, // ignore: use_null_aware_elements
            if (desc != null) 'desc': desc, // ignore: use_null_aware_elements
            'date': DateTime.now().toIso8601String(),
          });
        }
        await DummyData.saveToPrefs();
      }

      if (!context.mounted) return;
      setState(() {});
      final displayName = name.trim().isNotEmpty
          ? name.trim()
          : (email.trim().isNotEmpty ? email.trim() : 'Worker');
      FlashySnackBar.show(
        context,
        message: status == 'Present'
            ? 'attendance_marked_present'.tr(namedArgs: {'name': displayName})
            : 'attendance_marked_absent'.tr(namedArgs: {'name': displayName}),
        isError: false,
      );
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, context: 'DirectMarkAttendance');
      if (!context.mounted) return;
      FlashySnackBar.show(
        context,
        message: 'unexpected_error'.tr(),
        isError: true,
      );
    }
  }

  void _openAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) {
    if (_isDialogOpen) return;
    final workerData = _resolveWorkerData(data);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }
    if (_todayNonWorkingDay != null) {
      FlashySnackBar.show(
        context,
        message: 'non_working_day'.tr(),
        isError: true,
      );
      return;
    }
    if (_isWorkerOnPlannedTimeOff(workerData)) {
      FlashySnackBar.show(
        context,
        message: 'worker_on_time_off_attendance_blocked'.tr(),
        isError: true,
      );
      return;
    }
    if (titleKey != 'edit_attendance' &&
        (defaultStatus == 'Present' || defaultStatus == 'Absent')) {
      _saveDirectAttendance(context, data, defaultStatus!);
      return;
    }
    _showMarkAttendanceDialog(
      context,
      data,
      defaultStatus: defaultStatus,
      titleKey: titleKey,
    );
  }

  String _statusFilterLabel(String filterKey) {
    switch (filterKey) {
      case 'Present':
        return 'present_tab'.tr();
      case 'Absent':
        return 'absent_tab'.tr();
      case 'Leave':
        return 'on_leave'.tr();
      default:
        return 'all_filter'.tr();
    }
  }

  Widget _buildStatusFilterDropdown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = _statusFilterButtonKey.currentContext?.size?.width;
      if (width == null) return;
      if (width != _statusFilterButtonWidth) {
        setState(() => _statusFilterButtonWidth = width);
      }
    });
    return PopupMenuButton<String>(
      tooltip: '',
      constraints: _statusFilterButtonWidth == null
          ? null
          : BoxConstraints(
              minWidth: _statusFilterButtonWidth!,
              maxWidth: _statusFilterButtonWidth!,
            ),
      onSelected: (val) {
        setState(() {
          _selectedStatusFilter = val;
        });
      },
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Colors.grey.shade200, width: 1),
      ),
      color: const Color(0xFFFFFFFF),
      elevation: 4,
      itemBuilder: (context) {
        final filters = [
          {'value': 'All', 'label': 'all_filter'.tr()},
          {'value': 'Present', 'label': 'present_tab'.tr()},
          {'value': 'Absent', 'label': 'absent_tab'.tr()},
          {'value': 'Leave', 'label': 'on_leave'.tr()},
        ];
        return filters.map((f) {
          final bool selected = _selectedStatusFilter == f['value'];
          return PopupMenuItem<String>(
            value: f['value'],
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF0247C4)
                          : Colors.grey.shade300,
                      width: 2,
                    ),
                    color: selected
                        ? const Color(0xFF0247C4)
                        : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check,
                          size: 12,
                          color: Color(0xFFFFFFFF),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF0247C4)
                          : const Color(0xFF000000),
                      fontFamily: 'SF Pro Display',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        key: _statusFilterButtonKey,
        height: 43,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0247C4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/filter.png',
              width: 22,
              height: 22,
              color: const Color(0xFFFFFFFF),
              errorBuilder: (_, _, _) => const Icon(
                Icons.filter_alt_outlined,
                color: Color(0xFFFFFFFF),
                size: 22,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _statusFilterLabel(_selectedStatusFilter),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.arrow_drop_down,
              color: Color(0xFFFFFFFF),
              size: 22,
            ),
          ],
        ),
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
          GestureDetector(
            onTap: () {
              if (widget.onBack != null) {
                widget.onBack!();
              } else if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                Icons.arrow_back_ios_new,
                color: Color(0xFF000000),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'workforce'.tr(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: textDark,
              fontFamily: 'SF Pro Display',
            ),
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
                hintText: 'search_workers_name_position'.tr(),
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

  Future<void> _showMarkAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) async {
    final workerData = _resolveWorkerData(data);
    final name = (workerData['name'] ?? '').toString();
    final email = (workerData['email'] ?? '').toString();
    final workerId = (workerData['workerId'] ?? workerData['id'] ?? '')
        .toString()
        .trim();

    final normalizedEmail = WorkerIdentity.normalizeEmail(email);
    var todayRecord = AttendanceService.recordsForWorker(
      worker: workerData,
      attendanceRecords: _todayAttendance,
    ).firstWhere(_isTodayAttendance, orElse: () => <String, dynamic>{});
    if (todayRecord.isEmpty &&
        normalizedEmail.isNotEmpty &&
        (_isGuest || workerId.isEmpty)) {
      todayRecord = _todayAttendance.firstWhere(
        (record) =>
            WorkerIdentity.normalizeEmail(record['email']) == normalizedEmail &&
            _isTodayAttendance(record),
        orElse: () => <String, dynamic>{},
      );
    }
    int remainingLeaveForType(String type) =>
        TimeOffService.remainingForType(workerData, _timeOffRecords, type);
    final canSelectLeave =
        todayRecord['status'] == 'Leave' ||
        const [
          'Annual Leave',
          'Sick Leave',
          'Casual Leave',
          'Medical Leave',
        ].any((type) => remainingLeaveForType(type) > 0);

    const validStatuses = {'Present', 'Absent', 'Leave'};

    final recordStatus = todayRecord['status'];
    final initialStatus =
        (defaultStatus != null && validStatuses.contains(defaultStatus))
        ? defaultStatus
        : (recordStatus != null && validStatuses.contains(recordStatus))
        ? recordStatus
        : 'Present';

    final initialReason = (todayRecord['desc'] ?? '').toString();
    final reasonController = TextEditingController(text: initialReason);

    setState(() => _isDialogOpen = true);

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
        builder: (BuildContext dialogContext) {
          var dialogIsSaving = false;
          String selectedStatus = validStatuses.contains(initialStatus)
              ? initialStatus
              : 'Present';
          final initialType = (todayRecord['type'] ?? '').toString();
          const absentTypes = {'Without Notice', 'Family Emergency', 'Other'};
          const leaveTypes = {
            'Annual Leave',
            'Sick Leave',
            'Casual Leave',
            'Medical Leave',
          };
          int availableLeaveAllowanceForType(String type) {
            final normType = TimeOffService.normalizeLeaveType(type);
            int base = TimeOffService.remainingForType(
              workerData,
              _timeOffRecords,
              normType,
            );
            final wasInitialLeave =
                todayRecord['status'] == 'Leave' &&
                TimeOffService.normalizeLeaveType(initialType) == normType;
            if (wasInitialLeave) {
              base += 1;
            }
            return base < 0 ? 0 : base;
          }

          late String selectedLeaveType;

          bool canSelectLeaveType(String type) {
            return availableLeaveAllowanceForType(type) > 0;
          }

          String? firstAvailableLeaveType() {
            for (final type in leaveTypes) {
              if (canSelectLeaveType(type)) return type;
            }
            return null;
          }

          selectedLeaveType = selectedStatus == 'Leave'
              ? (leaveTypes.contains(initialType) &&
                        canSelectLeaveType(initialType)
                    ? initialType
                    : (firstAvailableLeaveType() ?? 'Annual Leave'))
              : (absentTypes.contains(initialType)
                    ? initialType
                    : 'Without Notice');

          int dialogRemainingLeaveForType(String type) {
            final normType = TimeOffService.normalizeLeaveType(type);
            int avail = availableLeaveAllowanceForType(normType);
            final isSelectedInDialog =
                selectedStatus == 'Leave' &&
                TimeOffService.normalizeLeaveType(selectedLeaveType) == normType;
            if (isSelectedInDialog) {
              avail -= 1;
            }
            return avail < 0 ? 0 : avail;
          }

          List<Map<String, dynamic>> reasonOptions() {
            if (selectedStatus == 'Absent') {
              return const [
                {
                  'value': 'Without Notice',
                  'key': 'absent_without_notice',
                  'disabled': 'false',
                },
                {
                  'value': 'Family Emergency',
                  'key': 'absent_emergency',
                  'disabled': 'false',
                },
                {'value': 'Other', 'key': 'absent_other', 'disabled': 'false'},
              ];
            }
            return [
              {
                'value': 'Annual Leave',
                'key': 'annual_leave',
                'disabled': canSelectLeaveType('Annual Leave')
                    ? 'false'
                    : 'true',
                'balance': dialogRemainingLeaveForType('Annual Leave'),
              },
              {
                'value': 'Sick Leave',
                'key': 'sick_leave_type',
                'disabled': canSelectLeaveType('Sick Leave') ? 'false' : 'true',
                'balance': dialogRemainingLeaveForType('Sick Leave'),
              },
              {
                'value': 'Casual Leave',
                'key': 'casual_leave_type',
                'disabled': canSelectLeaveType('Casual Leave')
                    ? 'false'
                    : 'true',
                'balance': dialogRemainingLeaveForType('Casual Leave'),
              },
              {
                'value': 'Medical Leave',
                'key': 'medical_leave_type',
                'disabled': canSelectLeaveType('Medical Leave')
                    ? 'false'
                    : 'true',
                'balance': dialogRemainingLeaveForType('Medical Leave'),
              },
            ];
          }

          String reasonLabelKey() =>
              selectedStatus == 'Absent' ? 'absent_reason' : 'leave_type';
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final showStatusChips =
                  titleKey == 'edit_attendance' || defaultStatus != 'Leave';
              return PopScope(
                canPop: !dialogIsSaving,
                child: Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0),
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 440,
                      decoration: BoxDecoration(
                        color: Color(0xFFFFFFFF),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF000000).withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 40,
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFFFFF),
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0xFFEEEEEE),
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Spacer(),
                                Text(
                                  titleKey.tr(),
                                  style: TextStyle(
                                    color: textDark,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: dialogIsSaving
                                      ? null
                                      : () => Navigator.pop(dialogContext),
                                  child: const Icon(
                                    Icons.close,
                                    color: textDark,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              24,
                              defaultStatus == 'Leave' ? 12 : 16,
                              24,
                              20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showStatusChips) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: dialogIsSaving
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    if (selectedStatus !=
                                                        'Present') {
                                                      reasonController.clear();
                                                    }
                                                    selectedStatus = 'Present';
                                                  });
                                                },
                                          child: _buildToggleChip(
                                            'present'.tr(),
                                            'assets/present icon for mark attendence.png',
                                            isSelected:
                                                selectedStatus == 'Present',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: dialogIsSaving
                                              ? null
                                              : () {
                                                  setDialogState(() {
                                                    if (selectedStatus !=
                                                        'Absent') {
                                                      reasonController.clear();
                                                    }
                                                    selectedStatus = 'Absent';
                                                    selectedLeaveType =
                                                        'Without Notice';
                                                  });
                                                },
                                          child: _buildToggleChip(
                                            'absent'.tr(),
                                            'assets/absent.svg',
                                            isSelected:
                                                selectedStatus == 'Absent',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap:
                                              canSelectLeave && !dialogIsSaving
                                              ? () {
                                                  final availType =
                                                      firstAvailableLeaveType();
                                                  if (availType == null) {
                                                    FlashySnackBar.show(
                                                      context,
                                                      message:
                                                          'requested_leaves_exceed_available'
                                                              .tr(),
                                                      isError: true,
                                                    );
                                                    return;
                                                  }
                                                  setDialogState(() {
                                                    if (selectedStatus !=
                                                        'Leave') {
                                                      reasonController.clear();
                                                    }
                                                    selectedStatus = 'Leave';
                                                    selectedLeaveType =
                                                        availType;
                                                  });
                                                }
                                              : null,
                                          child: _buildToggleChip(
                                            'leave'.tr(),
                                            'assets/leave.svg',
                                            isSelected:
                                                selectedStatus == 'Leave',
                                            enabled: canSelectLeave,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if (selectedStatus == 'Leave') ...[
                                  if (showStatusChips)
                                    const SizedBox(height: 16),
                                  Text(
                                    reasonLabelKey().tr(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        dropdownColor: Colors.white,
                                        value: selectedLeaveType,
                                        items: reasonOptions()
                                            .map(
                                              (o) => DropdownMenuItem(
                                                value: o['value'] as String,
                                                enabled:
                                                    o['disabled'] != 'true',
                                                child: Text(
                                                  selectedStatus == 'Absent'
                                                      ? (o['key'] as String? ??
                                                                '')
                                                            .tr()
                                                      : '${(o['key'] as String? ?? '').tr()} (${o['balance'] ?? 0})',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontFamily:
                                                        'SF Pro Display',
                                                    color:
                                                        o['disabled'] == 'true'
                                                        ? Colors.grey
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: dialogIsSaving
                                            ? null
                                            : (value) {
                                                if (value != null) {
                                                  setDialogState(() {
                                                    selectedLeaveType = value;
                                                  });
                                                }
                                              },
                                      ),
                                    ),
                                  ),
                                ],
                                if (selectedStatus == 'Leave') ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    'reason_required'.tr(),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 100,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: TextField(
                                      controller: reasonController,
                                      enabled: !dialogIsSaving,
                                      maxLines: null,
                                      maxLength: 100,
                                      onChanged: (_) => setDialogState(() {}),
                                      decoration: InputDecoration.collapsed(
                                        hintText: 'enter_reason_hint'.tr(),
                                        hintStyle: TextStyle(
                                          color: Colors.black.withValues(
                                            alpha: 0.38,
                                          ),
                                          fontSize: 13,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    OutlinedButton(
                                      onPressed: dialogIsSaving
                                          ? null
                                          : () => Navigator.pop(dialogContext),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0247C4,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFF0247C4),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 14,
                                        ),
                                        minimumSize: const Size(0, 40),
                                        elevation: 0,
                                      ),

                                      child: Text(
                                        'cancel'.tr(),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed:
                                          dialogIsSaving ||
                                              (selectedStatus == 'Leave' &&
                                                  reasonController.text
                                                      .trim()
                                                      .isEmpty)
                                          ? null
                                          : () async {
                                              if (dialogIsSaving) return;
                                              setDialogState(
                                                () => dialogIsSaving = true,
                                              );
                                              final reason = reasonController
                                                  .text
                                                  .trim();
                                              if (selectedStatus == 'Leave' &&
                                                  reason.isEmpty) {
                                                if (mounted) {
                                                  FlashySnackBar.show(
                                                    context,
                                                    message:
                                                        'please_enter_reason'
                                                            .tr(),
                                                    isError: true,
                                                  );
                                                }
                                                if (dialogContext.mounted) {
                                                  setDialogState(
                                                    () =>
                                                        dialogIsSaving = false,
                                                  );
                                                }
                                                return;
                                              }
                                              final isGuest =
                                                  _authService
                                                      .currentUser
                                                      ?.isAnonymous ??
                                                  false;
                                              final type =
                                                  selectedStatus == 'Leave'
                                                  ? selectedLeaveType
                                                  : null;
                                              final desc =
                                                  selectedStatus == 'Leave'
                                                  ? reason
                                                  : null;
                                              try {
                                                if (!isGuest) {
                                                  if (workerId.isEmpty) {
                                                    if (context.mounted) {
                                                      FlashySnackBar.show(
                                                        context,
                                                        message:
                                                            'unexpected_error'
                                                                .tr(),
                                                        isError: true,
                                                      );
                                                    }
                                                    if (dialogContext.mounted) {
                                                      setDialogState(
                                                        () => dialogIsSaving =
                                                            false,
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final attendanceData = <String, dynamic>{
                                                    'workerId': workerId,
                                                    'name': name,
                                                    'email': email,
                                                    'role':
                                                        workerData['role'] ??
                                                        workerData['position'] ??
                                                        '',
                                                    'status': selectedStatus,
                                                    'attendanceType':
                                                        workerData['type2'] ??
                                                        'Remote',
                                                    'workType':
                                                        workerData['type1'] ??
                                                        'Full Time',
                                                    'profileImage':
                                                        workerData['profileImage'],
                                                  };
                                                  if (type != null) {
                                                    attendanceData['type'] =
                                                        type;
                                                  } else {
                                                    attendanceData['type'] =
                                                        FieldValue.delete();
                                                  }
                                                  if (desc != null &&
                                                      desc.isNotEmpty) {
                                                    attendanceData['desc'] =
                                                        desc;
                                                  } else {
                                                    attendanceData['desc'] =
                                                        FieldValue.delete();
                                                  }
                                                  final attendanceId =
                                                      (todayRecord['id'] ?? '')
                                                          .toString()
                                                          .trim();
                                                  final leaveBalanceSynced =
                                                      await _syncAttendanceAnnualLeave(
                                                        worker: workerData,
                                                        originalAttendance:
                                                            todayRecord,
                                                        selectedStatus:
                                                            selectedStatus,
                                                        leaveType:
                                                            selectedLeaveType,
                                                        reason: reason,
                                                        attendanceData:
                                                            attendanceData,
                                                        attendanceId:
                                                            attendanceId,
                                                      );
                                                  if (!leaveBalanceSynced) {
                                                    if (context.mounted) {
                                                      FlashySnackBar.show(
                                                        context,
                                                        message:
                                                            'requested_leaves_exceed_available'
                                                                .tr(),
                                                        isError: true,
                                                      );
                                                    }
                                                    if (dialogContext.mounted) {
                                                      setDialogState(
                                                        () => dialogIsSaving =
                                                            false,
                                                      );
                                                    }
                                                    return;
                                                  }
                                                }

                                                if (isGuest) {
                                                  final wIdx = DummyData.workers
                                                      .indexWhere((worker) {
                                                        final id =
                                                            (worker['id'] ?? '')
                                                                .toString()
                                                                .trim();
                                                        if (workerId
                                                                .isNotEmpty &&
                                                            id.isNotEmpty) {
                                                          return workerId == id;
                                                        }
                                                        return (worker['email'] ??
                                                                    '')
                                                                .toString()
                                                                .trim()
                                                                .toLowerCase() ==
                                                            normalizedEmail;
                                                      });
                                                  if (wIdx != -1) {
                                                    DummyData
                                                            .workers[wIdx]['status'] =
                                                        selectedStatus;
                                                  }
                                                  final index = DummyData
                                                      .attendance
                                                      .indexWhere(
                                                        (element) =>
                                                            (element['email'] ??
                                                                        '')
                                                                    .toString()
                                                                    .trim()
                                                                    .toLowerCase() ==
                                                                normalizedEmail &&
                                                            _isTodayAttendance(
                                                              element,
                                                            ),
                                                      );
                                                  if (index != -1) {
                                                    DummyData
                                                            .attendance[index]['status'] =
                                                        selectedStatus;
                                                    if (type != null) {
                                                      DummyData
                                                              .attendance[index]['type'] =
                                                          type;
                                                    } else {
                                                      DummyData
                                                          .attendance[index]
                                                          .remove('type');
                                                    }
                                                    if (desc != null &&
                                                        desc.isNotEmpty) {
                                                      DummyData
                                                              .attendance[index]['desc'] =
                                                          desc;
                                                    } else {
                                                      DummyData
                                                          .attendance[index]
                                                          .remove('desc');
                                                    }
                                                  } else {
                                                    final newRecord = {
                                                      'id':
                                                          'dummy_a${DateTime.now().millisecondsSinceEpoch}',
                                                      'workerId': workerId,
                                                      'name': name,
                                                      'email': email,
                                                      'role':
                                                          workerData['position'] ??
                                                          workerData['role'] ??
                                                          '',
                                                      'status': selectedStatus,
                                                      'attendanceType':
                                                          workerData['attendanceType'] ??
                                                          workerData['type2'] ??
                                                          'On-Site',
                                                      'workType':
                                                          workerData['workType'] ??
                                                          workerData['type1'] ??
                                                          'Full Time',
                                                      'createdAt':
                                                          DateTime.now(),
                                                    };
                                                    if (type != null) {
                                                      newRecord['type'] = type;
                                                    }
                                                    if (desc != null &&
                                                        desc.isNotEmpty) {
                                                      newRecord['desc'] = desc;
                                                    }
                                                    DummyData.attendance.add(
                                                      newRecord,
                                                    );
                                                  }
                                                  if (mounted) {
                                                    setState(() {
                                                      _workers =
                                                          List<
                                                            Map<String, dynamic>
                                                          >.from(
                                                            DummyData.workers,
                                                          );
                                                      _rebuildWorkerIndexes();
                                                      _periodAttendanceRecords =
                                                          List<Map<String, dynamic>>.from(
                                                            DummyData
                                                                .attendance,
                                                          ).where((record) {
                                                            return app_date_utils
                                                                .AppDateUtils.isAttendanceRecordWithinPeriod(
                                                              record,
                                                              _selectedTimeframe,
                                                            );
                                                          }).toList();
                                                      _todayAttendance =
                                                          _latestAttendancePerWorker(
                                                            _periodAttendanceRecords,
                                                          );
                                                    });
                                                  }

                                                  await DummyData.saveToPrefs();
                                                }

                                                if (!context.mounted ||
                                                    !dialogContext.mounted) {
                                                  return;
                                                }
                                                FlashySnackBar.show(
                                                  context,
                                                  message:
                                                      'attendance_updated_success'
                                                          .tr(
                                                            namedArgs: {
                                                              'name': name,
                                                            },
                                                          ),
                                                );
                                                Navigator.of(
                                                  dialogContext,
                                                ).pop();
                                              } catch (e) {
                                                if (context.mounted) {
                                                  FlashySnackBar.show(
                                                    context,
                                                    message:
                                                        'attendance_update_failed'
                                                            .tr(
                                                              namedArgs: {
                                                                'error': e
                                                                    .toString(),
                                                              },
                                                            ),
                                                    isError: true,
                                                  );
                                                }
                                                if (dialogContext.mounted) {
                                                  setDialogState(
                                                    () =>
                                                        dialogIsSaving = false,
                                                  );
                                                }
                                              }
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0F52BA,
                                        ),
                                        disabledBackgroundColor: const Color(
                                          0xFFB0BEC5,
                                        ),
                                        disabledForegroundColor: const Color(
                                          0xFFE0E0E0,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 14,
                                        ),
                                        minimumSize: const Size(0, 40),
                                        elevation: 0,
                                      ),
                                      child: dialogIsSaving
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
                                              style: TextStyle(
                                                color: Color(0xFFFFFFFF),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                fontFamily: 'SF Pro Display',
                                              ),
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
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 400), () {
        reasonController.dispose();
      });
      if (mounted) {
        setState(() => _isDialogOpen = false);
      }
    }
  }

  Widget _buildHolidayNotice(String name, {bool isCompanyOffDay = false}) {
    final displayName = LocalizationHelper.localizeHolidayName(name);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/holidays_icon.svg',
            width: 56,
            height: 56,
            colorFilter: const ColorFilter.mode(
              Color(0xFFCBCBCB),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isCompanyOffDay
                ? 'company_off_day'.tr()
                : (displayName.isNotEmpty
                      ? '${'today_is_holiday'.tr()}: $displayName'
                      : 'today_is_holiday'.tr()),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0247C4),
              fontFamily: 'SF Pro Display',
            ),
          ),
          if (isCompanyOffDay) ...[
            const SizedBox(height: 8),
            Text(
              'attendance_disabled_company_off'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: textMuted,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWorkerAttendanceBody(Map<String, dynamic>? holiday) {
    if (holiday != null) {
      return _buildHolidayNotice(
        (holiday['name'] ?? '').toString(),
        isCompanyOffDay: holiday['isCompanyOffDay'] == true,
      );
    }
    if (_filteredWorkers.isEmpty) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
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
              'no_workers_found_title'.tr(),
              style: const TextStyle(
                color: Color(0xFF0247C1),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    final isHoliday = holiday != null;
    return SingleChildScrollView(
      child: Column(
        children: _filteredWorkers
            .asMap()
            .entries
            .map(
              (entry) => WorkerListItem(
                data: entry.value,
                index: entry.key,
                currentStatus: _getWorkerStatus(entry.value),
                isHoliday: isHoliday,
                canMarkLeave:
                    TimeOffService.totalAvailableLeaves(entry.value) > 0,
                onMarkAttendance: (status) {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  if (isHoliday) {
                    FlashySnackBar.show(
                      context,
                      message: 'non_working_day'.tr(),
                      isError: true,
                    );
                  } else {
                    _openAttendanceDialog(
                      context,
                      entry.value,
                      defaultStatus: status,
                    );
                  }
                },
                onTap: () {
                  final isGuest =
                      _authService.currentUser?.isAnonymous ?? false;
                  if (isGuest) {
                    showGuestRestrictionDialog(context);
                    return;
                  }
                  if (isHoliday) {
                    FlashySnackBar.show(
                      context,
                      message: 'non_working_day'.tr(),
                      isError: true,
                    );
                  } else {
                    final workerStatus = _getWorkerStatus(entry.value);
                    if (workerStatus.isEmpty) {
                      _openAttendanceDialog(context, entry.value);
                    }
                  }
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTodayAttendanceBody(Map<String, dynamic>? holiday) {
    if (holiday != null) {
      return _buildHolidayNotice(
        (holiday['name'] ?? '').toString(),
        isCompanyOffDay: holiday['isCompanyOffDay'] == true,
      );
    }
    final visibleAttendance = _visibleTodayAttendance;
    if (visibleAttendance.isEmpty) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
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
              'no_attendance_records'.tr(),
              style: const TextStyle(
                color: Color(0xFF0247C1),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: visibleAttendance
            .asMap()
            .entries
            .map(
              (entry) => TodayAttendanceItem(
                data: entry.value,
                index: entry.key,
                onEdit: () => _openAttendanceDialog(
                  context,
                  entry.value,
                  defaultStatus: (entry.value['status'] ?? 'Present')
                      .toString(),
                  titleKey: 'edit_attendance',
                ),
                onTap: () => _openAttendanceDialog(
                  context,
                  entry.value,
                  defaultStatus: (entry.value['status'] ?? 'Present')
                      .toString(),
                  titleKey: 'edit_attendance',
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildToggleChip(
    String label,
    String asset, {
    bool isSelected = false,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.grey.shade200
              : isSelected
              ? const Color(0xFF0F52BA)
              : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: !enabled
                ? Colors.grey.shade300
                : isSelected
                ? const Color(0xFF0F52BA)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            asset.endsWith('.svg')
                ? SvgPicture.asset(asset, height: 20, width: 20)
                : Image.asset(asset, height: 20, width: 20),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: !enabled
                    ? Colors.grey.shade600
                    : isSelected
                    ? const Color(0xFFFFFFFF)
                    : Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class WorkerListItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final String currentStatus;
  final bool isHoliday;
  final bool canMarkLeave;
  final ValueChanged<String> onMarkAttendance;
  final VoidCallback? onTap;

  const WorkerListItem({
    super.key,
    required this.data,
    required this.index,
    this.currentStatus = '',
    this.isHoliday = false,
    this.canMarkLeave = true,
    required this.onMarkAttendance,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          WorkerAvatar(
            imageUrl: data['profileImage'] is String
                ? data['profileImage'] as String
                : null,
            name: (data['name'] ?? '').toString(),
            size: 44,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data["name"] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  (data["email"] ?? '').toString(),
                  style: const TextStyle(
                    color: textMuted,
                    fontSize: 13,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 1,
                ),
              ],
            ),
          ),

          if (currentStatus.isEmpty) ...[
            const SizedBox(width: 12),
            _AttendanceActionButton(
              labelKey: 'present',
              status: 'Present',
              color: greenPresent,
              enabled: !isHoliday,
              onTap: onMarkAttendance,
              onDisabledTap: () {
                FlashySnackBar.show(
                  context,
                  message: 'non_working_day'.tr(),
                  isError: true,
                );
              },
            ),
            const SizedBox(width: 8),
            _AttendanceActionButton(
              labelKey: 'absent',
              status: 'Absent',
              color: redAbsent,
              enabled: !isHoliday,
              onTap: onMarkAttendance,
              onDisabledTap: () {
                FlashySnackBar.show(
                  context,
                  message: 'non_working_day'.tr(),
                  isError: true,
                );
              },
            ),
            const SizedBox(width: 8),
            _AttendanceActionButton(
              labelKey: 'leave',
              status: 'Leave',
              color: orangeLeave,
              enabled: !isHoliday && canMarkLeave,
              onTap: onMarkAttendance,
              onDisabledTap: () {
                FlashySnackBar.show(
                  context,
                  message: isHoliday
                      ? 'non_working_day'.tr()
                      : 'requested_leaves_exceed_available'.tr(),
                  isError: true,
                );
              },
            ),
          ] else ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: currentStatus == 'Leave'
                    ? const Color(0xFFFFF3E0)
                    : const Color(0xFFE2E5EA),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentStatus == 'Leave') ...[
                    const Icon(
                      Icons.beach_access_rounded,
                      size: 14,
                      color: Color(0xFFB45309),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    currentStatus == 'Leave'
                        ? 'on_leave'.tr()
                        : 'attendance_marked'.tr(),
                    style: TextStyle(
                      color: currentStatus == 'Leave'
                          ? const Color(0xFFB45309)
                          : const Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceActionButton extends StatelessWidget {
  final String labelKey;
  final String status;
  final Color color;
  final bool enabled;
  final ValueChanged<String> onTap;
  final VoidCallback? onDisabledTap;

  const _AttendanceActionButton({
    required this.labelKey,
    required this.status,
    required this.color,
    this.enabled = true,
    required this.onTap,
    this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled;
    return GestureDetector(
      onTap: isEnabled ? () => onTap(status) : onDisabledTap,
      child: Container(
        width: 72,
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isEnabled ? color : Colors.grey.shade400,
          borderRadius: BorderRadius.circular(6),
          border: null,
          boxShadow: null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelKey.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TodayAttendanceItem extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;

  const TodayAttendanceItem({
    super.key,
    required this.data,
    required this.index,
    this.onEdit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? onEdit,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FC),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                WorkerAvatar(
                  imageUrl: data['profileImage'] is String
                      ? data['profileImage'] as String
                      : null,
                  name: (data['name'] ?? '').toString(),
                  size: 44,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (data["name"] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(status: (data["status"] ?? '').toString()),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onEdit,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/edit_icon.svg',
                        height: 20,
                        width: 20,
                        colorFilter: const ColorFilter.mode(
                          Color(0xFF000000),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (data["type"] != null && data['status'] == 'Leave') ...[
              const SizedBox(height: 12),
              Text(
                (data['status'] == 'Leave'
                        ? 'leave_type_display'
                        : 'absent_type')
                    .tr(
                      namedArgs: {
                        'type': _localizedAttendanceType(
                          data['type'].toString(),
                        ),
                      },
                    ),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                  fontFamily: 'SF Pro Display',
                ),
              ),
              if (data["desc"] != null) ...[
                const SizedBox(height: 6),
                Text(
                  (data["desc"] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: textMuted,
                    height: 1.3,
                    fontFamily: 'SF Pro Display',
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String status;

  const StatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor = pillGray;
    Color textColor = const Color(0xFFFFFFFF);
    final normalizedStatus = (status.isEmpty || status == '*****')
        ? '*****'
        : status;

    if (normalizedStatus == '*****') {
      bgColor = pillGray;
      textColor = textDark;
    } else if (normalizedStatus == 'Present') {
      bgColor = greenPresent;
    } else if (normalizedStatus == 'Absent') {
      bgColor = redAbsent;
    } else if (normalizedStatus == 'Leave') {
      bgColor = orangeLeave;
    } else {
      bgColor = pillGray;
      textColor = textDark;
    }

    final displayStatus = normalizedStatus == '*****'
        ? normalizedStatus
        : _localizedAttendanceStatus(normalizedStatus);

    return Container(
      width: 72,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        displayStatus,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          fontFamily: 'SF Pro Display',
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
