import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/time_off_service.dart';
import '../services/preferences_service.dart';
import '../widgets/sidebar_widget.dart';
import 'package:provider/provider.dart';
import '../utils/snackbar_utils.dart';
import '../utils/image_utils.dart';
import '../utils/worker_identity.dart';
import '../utils/date_utils.dart' as app_date_utils;
import '../widgets/notification_bell.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../utils/guest_restriction.dart';

const Color primaryBlue = Color(0xFF0B51C1);
const Color bgGray = Color(0xFFF7F8FA);
const Color cardLightGray = Color(0xFFF3F5F8);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF64748B);

const Color greenPresent = Color(0xFF00C853);
const Color redAbsent = Color(0xFFF44336);
const Color orangeLeave = Color(0xFFFF7B00);
const Color pillGray = Color(0xFFE2E5EA);

class WorkersAttendanceScreen extends StatefulWidget {
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
  State<WorkersAttendanceScreen> createState() =>
      _WorkersAttendanceScreenState();
}

class _WorkersAttendanceScreenState extends State<WorkersAttendanceScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatusFilter = 'All';
  String _selectedTimeframe = 'Today';
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
  bool _isDialogOpen = false;
  String? _errorMessage;
  bool _isPremium = false;
  late AuthService _authService;
  late FirestoreService _firestore;
  StreamSubscription? _workersSub;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _holidaysSub;
  StreamSubscription? _timeOffSub;
  bool _leaveNoticeShown = false;

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
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
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
    if (user != null && !user.isAnonymous) {
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
    }

    _workersSub = _firestore.workersStream.listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            _workers = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            // Re-filter period records to exclude records for deleted workers
            _periodAttendanceRecords = _periodAttendanceRecords
                .where((att) => _attendanceBelongsToCurrentWorker(att))
                .toList();
            _todayAttendance = _latestAttendancePerWorker(
              _periodAttendanceRecords,
            );
            _workersLoaded = true;
            if (_workersLoaded && _attendanceLoaded) _isLoading = false;
          });
          _showActiveLeaveNotice();
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      },
    );
    _attendanceSub = _firestore.attendanceStream.listen(
      (snapshot) {
        if (mounted) {
          setState(() {
            final sortedList = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            sortedList.sort((a, b) {
              final aTime = a['createdAt'];
              final bTime = b['createdAt'];
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return -1;
              if (bTime == null) return 1;
              if (aTime is Timestamp && bTime is Timestamp) {
                return bTime.compareTo(aTime);
              }
              return 0;
            });
            final filtered = sortedList.where((att) {
              // Skip attendance records for workers that have been deleted
              if (!_attendanceBelongsToCurrentWorker(att)) return false;
              return app_date_utils.AppDateUtils.isAttendanceRecordWithinPeriod(
                att,
                _selectedTimeframe,
              );
            }).toList();
            _periodAttendanceRecords = filtered;
            _todayAttendance = _latestAttendancePerWorker(filtered);
            _attendanceLoaded = true;
            if (_workersLoaded && _attendanceLoaded) _isLoading = false;
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      },
    );

    _holidaysSub = _firestore.holidaysStream.listen((snap) {
      if (mounted) {
        var companyWorkingDays = _companyWorkingDays;
        final holidays = <Map<String, dynamic>>[];
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['type'] == 'company_work_days') {
            final savedDays = (data['workingDays'] as List<dynamic>? ?? [])
                .whereType<num>()
                .map((day) => day.toInt())
                .where(
                  (day) => day >= DateTime.monday && day <= DateTime.sunday,
                )
                .toSet();
            if (savedDays.isNotEmpty) companyWorkingDays = savedDays;
            continue;
          }
          holidays.add({...data, 'id': doc.id});
        }
        setState(() {
          _holidays = holidays;
          _companyWorkingDays = companyWorkingDays;
        });
      }
    }, onError: (_) {});

    _timeOffSub = _firestore.timeoffStream.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _timeOffRecords = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
      });
      _showActiveLeaveNotice();
    }, onError: (_) {});
  }

  void _showActiveLeaveNotice() {
    if (_leaveNoticeShown || !mounted) return;
    final active = <Map<String, dynamic>>[];
    for (final worker in _workers) {
      final leave = TimeOffService.activeLeaveForWorker(
        worker,
        _plannedTimeOffRecords,
      );
      if (leave != null) active.add({...leave, 'workerName': worker['name']});
    }
    if (active.isEmpty) return;
    _leaveNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final leave = active.first;
      final extra = active.length > 1 ? ' (+${active.length - 1} more)' : '';
      final leaveType = (leave['action'] ?? leave['type'] ?? 'Leave')
          .toString();
      final selectedDays = TimeOffService.selectedDatesForRecord(leave).length;
      FlashySnackBar.show(
        context,
        title: '$leaveType • ${leave['workerName']}',
        message: selectedDays > 1
            ? 'This worker is on leave today ($selectedDays selected days)$extra'
            : 'This worker is on leave today$extra',
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

  bool _isWorkerOnPlannedTimeOff(Map<String, dynamic> worker) {
    return TimeOffService.isWorkerOnLeave(worker, _plannedTimeOffRecords);
  }

  Map<String, dynamic>? _attendanceManagedTimeOffForWorker(
    Map<String, dynamic> worker,
    DateTime date,
  ) {
    final target = DateTime(date.year, date.month, date.day);
    final workerId = (worker['id'] ?? '').toString().trim();
    final workerEmail = (worker['email'] ?? '').toString().trim().toLowerCase();
    final workerName = (worker['name'] ?? '').toString().trim().toLowerCase();

    for (final record in _timeOffRecords) {
      if (!_isAttendanceManagedTimeOff(record)) {
        continue;
      }
      if (!TimeOffService.isActiveRecord(record)) continue;
      final recordEmail = (record['email'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final recordWorkerId = (record['workerId'] ?? '').toString().trim();
      final recordName = (record['name'] ?? record['workerName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final belongsToWorker = workerId.isNotEmpty && recordWorkerId.isNotEmpty
          ? workerId == recordWorkerId
          : workerEmail.isNotEmpty && recordEmail.isNotEmpty
          ? workerEmail == recordEmail
          : workerName.isNotEmpty && workerName == recordName;
      if (!belongsToWorker) continue;
      if (TimeOffService.selectedDatesForRecord(record).contains(target)) {
        return record;
      }
    }
    return null;
  }

  Future<bool> _syncAttendanceAnnualLeave({
    required Map<String, dynamic> worker,
    required String selectedStatus,
    required String leaveType,
    required String reason,
  }) async {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final existing = _attendanceManagedTimeOffForWorker(
      worker,
      normalizedToday,
    );
    final shouldHaveLeave = selectedStatus == 'Leave';

    if (!shouldHaveLeave && existing == null) return true;
    if (shouldHaveLeave &&
        existing == null &&
        TimeOffService.remainingPaidLeave(worker, _timeOffRecords) <= 0) {
      return false;
    }

    final existingId = (existing?['id'] ?? '').toString();
    final projectedRecords = _timeOffRecords
        .where(
          (record) =>
              existing == null ||
              (existingId.isNotEmpty
                  ? record['id']?.toString() != existingId
                  : !identical(record, existing)),
        )
        .map(Map<String, dynamic>.from)
        .toList();

    Map<String, dynamic>? attendanceTimeOff;
    if (shouldHaveLeave) {
      final dateKey =
          '${normalizedToday.year}-'
          '${normalizedToday.month.toString().padLeft(2, '0')}-'
          '${normalizedToday.day.toString().padLeft(2, '0')}';
      attendanceTimeOff = <String, dynamic>{
        'workerId': worker['id'] ?? '',
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
        'id': existingId.isNotEmpty ? existingId : 'pending_attendance_leave',
      });
    }

    final totalPaidDays = TimeOffService.configuredPaidLeaveAllowance(worker);
    final usedLeaveDays = TimeOffService.leaveDaysUsedForWorker(
      worker,
      projectedRecords,
    );
    final balanceUpdate = <String, dynamic>{
      'availableAnnualLeaves': (totalPaidDays - usedLeaveDays)
          .clamp(0, totalPaidDays)
          .toString(),
      'leavesUsed': usedLeaveDays.toString(),
    };
    final workerId = (worker['id'] ?? '').toString();

    String savedTimeOffId = existingId;
    if (shouldHaveLeave) {
      if (workerId.isNotEmpty) {
        savedTimeOffId = await _firestore.saveTimeOffWithWorkerBalance(
          timeOffId: existingId.isEmpty ? null : existingId,
          record: attendanceTimeOff!,
          workerId: workerId,
          balance: balanceUpdate,
        );
      } else if (existingId.isNotEmpty) {
        await _firestore.updateTimeOffRecord(existingId, attendanceTimeOff!);
      } else {
        savedTimeOffId = await _firestore.addTimeOffRecord(attendanceTimeOff!);
      }
    } else if (existingId.isNotEmpty) {
      if (workerId.isNotEmpty) {
        await _firestore.deleteTimeOffWithWorkerBalance(
          timeOffId: existingId,
          workerId: workerId,
          balance: balanceUpdate,
        );
      } else {
        await _firestore.deleteTimeOffRecord(existingId);
      }
    }

    if (!mounted) return true;
    setState(() {
      _timeOffRecords = projectedRecords
          .where(
            (record) => record['id']?.toString() != 'pending_attendance_leave',
          )
          .toList();
      if (shouldHaveLeave && attendanceTimeOff != null) {
        _timeOffRecords.insert(0, {...attendanceTimeOff, 'id': savedTimeOffId});
      }
      final workerIndex = _workers.indexWhere(
        (item) =>
            (workerId.isNotEmpty && item['id']?.toString() == workerId) ||
            (item['email'] ?? '').toString().trim().toLowerCase() ==
                (worker['email'] ?? '').toString().trim().toLowerCase(),
      );
      if (workerIndex != -1) {
        _workers[workerIndex] = {..._workers[workerIndex], ...balanceUpdate};
      }
    });
    return true;
  }

  String _getWorkerStatus(Map<String, dynamic> worker) {
    if (!AttendanceService.workerExistedOnDate(worker, DateTime.now())) {
      return "";
    }

    final directStatus = worker["status"]?.toString();
    if (directStatus != null &&
        directStatus.isNotEmpty &&
        directStatus != "*****") {
      return directStatus;
    }

    final workerId = (worker['id'] ?? '').toString().trim();
    final email = (worker["email"] ?? '').toString().trim().toLowerCase();
    final attRecord = _todayAttendance.cast<Map<String, dynamic>?>().firstWhere(
      (attendance) {
        final attendanceWorkerId = (attendance?['workerId'] ?? '')
            .toString()
            .trim();
        if (workerId.isNotEmpty && attendanceWorkerId.isNotEmpty) {
          return workerId == attendanceWorkerId;
        }
        return (attendance?['email'] ?? '').toString().trim().toLowerCase() ==
            email;
      },
      orElse: () => null,
    );
    if (attRecord != null) {
      final attStatus = attRecord['status']?.toString() ?? "";
      if (attStatus.isNotEmpty && attStatus != "*****") {
        return attStatus;
      }
    }
    return "";
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
    for (final h in _holidays) {
      if (h['isEnabled'] != true) continue;
      final isRecurring = h['isRecurring'] == true;
      final rawYear = h['year'];
      final holidayYear = rawYear is num
          ? rawYear.toInt()
          : int.tryParse((rawYear ?? '').toString());
      if (!isRecurring && holidayYear != null && holidayYear != now.year) {
        continue;
      }
      final monthNum = app_date_utils.AppDateUtils.parseMonth(
        (h['month'] ?? '').toString(),
      );
      final dayNum = int.tryParse((h['day'] ?? '').toString());
      if (monthNum == now.month && dayNum == now.day) return h;
    }
    return null;
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

  List<Map<String, dynamic>> _latestAttendancePerWorker(
    List<Map<String, dynamic>> records,
  ) {
    final byEmail = <String, Map<String, dynamic>>{};
    for (final att in records) {
      final workerId = (att['workerId'] ?? '').toString().trim();
      final email = WorkerIdentity.normalizeEmail(att['email']);
      final name = WorkerIdentity.normalizeName(att['name']);
      final matchingWorker = _workers.cast<Map<String, dynamic>?>().firstWhere((
        worker,
      ) {
        final knownWorkerId = (worker?['id'] ?? '').toString().trim();
        if (workerId.isNotEmpty &&
            knownWorkerId.isNotEmpty &&
            workerId == knownWorkerId) {
          return true;
        }
        final knownEmail = WorkerIdentity.normalizeEmail(worker?['email']);
        return email.isNotEmpty && knownEmail.isNotEmpty && email == knownEmail;
      }, orElse: () => null);
      if (matchingWorker == null) continue;
      if (!AttendanceService.recordIsOnOrAfterWorkerCreation(
        worker: matchingWorker,
        attendanceRecord: att,
      )) {
        continue;
      }
      final canonicalWorkerId = (matchingWorker['id'] ?? '').toString().trim();
      final identityKey = canonicalWorkerId.isNotEmpty
          ? 'id:$canonicalWorkerId'
          : workerId.isNotEmpty
          ? 'id:$workerId'
          : email.isNotEmpty
          ? 'email:$email'
          : 'name:$name';
      if (identityKey == 'name:') continue;
      final existing = byEmail[identityKey];
      if (existing == null) {
        byEmail[identityKey] = att;
        continue;
      }
      final da = app_date_utils.AppDateUtils.attendanceRecordDate(att);
      final db = app_date_utils.AppDateUtils.attendanceRecordDate(existing);
      final isNewer =
          da != null &&
          (db == null ||
              da.isAfter(db) ||
              (da.isAtSameMomentAs(db) &&
                  (att['id'] ?? '').toString().compareTo(
                        (existing['id'] ?? '').toString(),
                      ) >
                      0));
      if (isNewer) byEmail[identityKey] = att;
    }
    return byEmail.values.toList();
  }

  Map<String, dynamic> _resolveWorkerData(
    Map<String, dynamic> attendanceOrWorker,
  ) {
    final candidateWorkerId = AttendanceService.workerIdFor(attendanceOrWorker);
    final candidateEmail = WorkerIdentity.normalizeEmail(
      attendanceOrWorker['email'],
    );
    final worker = _workers.cast<Map<String, dynamic>?>().firstWhere((item) {
      final knownWorkerId = (item?['id'] ?? '').toString().trim();
      if (candidateWorkerId.isNotEmpty &&
          knownWorkerId.isNotEmpty &&
          candidateWorkerId == knownWorkerId) {
        return true;
      }
      final knownEmail = WorkerIdentity.normalizeEmail(item?['email']);
      return candidateEmail.isNotEmpty &&
          knownEmail.isNotEmpty &&
          candidateEmail == knownEmail;
    }, orElse: () => null);

    if (worker == null) {
      return {
        ...attendanceOrWorker,
        if (candidateWorkerId.isNotEmpty) 'id': candidateWorkerId,
      };
    }
    return {...attendanceOrWorker, ...worker};
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final ids = _currentWorkerIds;
    return _workers.where((worker) {
      // Only show workers that exist (defense in depth)
      if (ids.isNotEmpty) {
        final wid = (worker['id'] ?? '').toString().trim();
        if (wid.isNotEmpty && !ids.contains(wid)) return false;
      }
      if (!AttendanceService.workerExistedOnDate(worker, DateTime.now())) {
        return false;
      }
      if (_isWorkerOnPlannedTimeOff(worker)) {
        return false;
      }
      final name = (worker["name"] ?? "").toString().toLowerCase();
      final role = (worker["position"] ?? worker["role"] ?? "")
          .toString()
          .toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || role.contains(query);
      if (_selectedStatusFilter == 'All') return matchesSearch;
      final workerStatus = _getWorkerStatus(worker);
      return matchesSearch && workerStatus == _selectedStatusFilter;
    }).toList();
  }

  /// Set of current worker IDs (non-empty) for filtering attendance.
  Set<String> get _currentWorkerIds {
    return _workers
        .map((w) => (w['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Returns true if the attendance record belongs to a worker that still exists.
  bool _attendanceBelongsToCurrentWorker(Map<String, dynamic> record) {
    final ids = _currentWorkerIds;
    if (ids.isEmpty) return true; // workers not loaded yet
    final workerId = (record['workerId'] ?? '').toString().trim();
    if (workerId.isEmpty) return true; // no workerId in record
    return ids.contains(workerId);
  }

  List<Map<String, dynamic>> get _visibleTodayAttendance {
    return _todayAttendance
        .where((record) => _attendanceBelongsToCurrentWorker(record))
        .where((record) => !_isWorkerOnPlannedTimeOff(record))
        .toList();
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
              onBackToLogin: () {
                _authService.signOut();
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
                                      Text(
                                        'worker_attendance'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textDark,
                                          fontFamily: 'SF Pro Display',
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
                                      Text(
                                        'today_attendance'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textDark,
                                          fontFamily: 'SF Pro Display',
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

  void _openAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) {
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
    if (_isWorkerOnPlannedTimeOff(data)) {
      FlashySnackBar.show(
        context,
        message: 'worker_on_time_off_attendance_blocked'.tr(),
        isError: true,
      );
      return;
    }
    _showMarkAttendanceDialog(
      context,
      data,
      defaultStatus: defaultStatus,
      titleKey: titleKey,
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

  void _showMarkAttendanceDialog(
    BuildContext context,
    Map<String, dynamic> data, {
    String? defaultStatus,
    String titleKey = 'mark_attendance',
  }) {
    final workerData = _resolveWorkerData(data);
    final name = workerData["name"] ?? "";
    final email = workerData["email"] ?? "";
    final workerId = (workerData['id'] ?? '').toString().trim();

    final normalizedEmail = WorkerIdentity.normalizeEmail(email);
    var todayRecord = AttendanceService.recordsForWorker(
      worker: workerData,
      attendanceRecords: _todayAttendance,
    ).firstWhere(_isTodayAttendance, orElse: () => <String, dynamic>{});
    if (todayRecord.isEmpty && normalizedEmail.isNotEmpty) {
      todayRecord = _todayAttendance.firstWhere(
        (record) =>
            WorkerIdentity.normalizeEmail(record['email']) == normalizedEmail &&
            _isTodayAttendance(record),
        orElse: () => <String, dynamic>{},
      );
    }
    final canSelectLeave =
        todayRecord['status'] == 'Leave' ||
        TimeOffService.remainingPaidLeave(workerData, _timeOffRecords) > 0;

    const validStatuses = {'Present', 'Absent', 'Leave'};

    final recordStatus = todayRecord['status'];
    final initialStatus =
        (defaultStatus != null && validStatuses.contains(defaultStatus))
        ? defaultStatus
        : (recordStatus != null && validStatuses.contains(recordStatus))
        ? recordStatus
        : 'Present';

    final initialReason = todayRecord['desc'] ?? '';

    setState(() => _isDialogOpen = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (BuildContext dialogContext) {
        var dialogIsSaving = false;
        String selectedStatus = validStatuses.contains(initialStatus)
            ? initialStatus
            : 'Present';
        final initialType = (todayRecord['type'] ?? '').toString();
        const absentTypes = {
          'Without Notice',
          'Sick',
          'Family Emergency',
          'Other',
        };
        const leaveTypes = {'Sick Leave', 'Casual Leave', 'Medical Leave'};
        String selectedLeaveType = selectedStatus == 'Leave'
            ? (leaveTypes.contains(initialType) ? initialType : 'Sick Leave')
            : (absentTypes.contains(initialType)
                  ? initialType
                  : 'Without Notice');

        List<Map<String, String>> reasonOptions() {
          if (selectedStatus == 'Absent') {
            return const [
              {'value': 'Without Notice', 'key': 'absent_without_notice'},
              {'value': 'Sick', 'key': 'absent_sick'},
              {'value': 'Family Emergency', 'key': 'absent_emergency'},
              {'value': 'Other', 'key': 'absent_other'},
            ];
          }
          return const [
            {'value': 'Sick Leave', 'key': 'sick_leave_type'},
            {'value': 'Casual Leave', 'key': 'casual_leave_type'},
            {'value': 'Medical Leave', 'key': 'medical_leave_type'},
          ];
        }

        String reasonLabelKey() =>
            selectedStatus == 'Absent' ? 'absent_reason' : 'leave_type';
        final reasonController = TextEditingController(text: initialReason);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: true,
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
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: dialogIsSaving
                                          ? null
                                          : () {
                                              setDialogState(() {
                                                selectedStatus = 'Present';
                                              });
                                            },
                                      child: _buildToggleChip(
                                        'present'.tr(),
                                        'assets/present icon for mark attendence.png',
                                        isSelected: selectedStatus == 'Present',
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
                                                selectedStatus = 'Absent';
                                                selectedLeaveType =
                                                    'Without Notice';
                                              });
                                            },
                                      child: _buildToggleChip(
                                        'absent'.tr(),
                                        'assets/absent.svg',
                                        isSelected: selectedStatus == 'Absent',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: canSelectLeave && !dialogIsSaving
                                          ? () {
                                              setDialogState(() {
                                                selectedStatus = 'Leave';
                                                selectedLeaveType =
                                                    'Sick Leave';
                                              });
                                            }
                                          : null,
                                      child: _buildToggleChip(
                                        'leave'.tr(),
                                        'assets/leave.svg',
                                        isSelected: selectedStatus == 'Leave',
                                        enabled: canSelectLeave,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (selectedStatus == 'Absent' ||
                                  selectedStatus == 'Leave') ...[
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
                                              value: o['value'],
                                              enabled: o['disabled'] != 'true',
                                              child: Text(
                                                (o['key'] ?? '').tr(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontFamily: 'SF Pro Display',
                                                  color: o['disabled'] == 'true'
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
                              if (selectedStatus != 'Present') ...[
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
                                        : () {
                                            setState(
                                              () => _isDialogOpen = false,
                                            );
                                            Navigator.pop(dialogContext);
                                          },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0247C4),
                                      side: const BorderSide(
                                        color: Color(0xFF0247C4),
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
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
                                            (selectedStatus != 'Present' &&
                                                reasonController.text
                                                    .trim()
                                                    .isEmpty)
                                        ? null
                                        : () async {
                                            if (dialogIsSaving) return;
                                            setDialogState(
                                              () => dialogIsSaving = true,
                                            );
                                            final reason = reasonController.text
                                                .trim();
                                            if (selectedStatus != 'Present' &&
                                                reason.isEmpty) {
                                              if (mounted) {
                                                FlashySnackBar.show(
                                                  context,
                                                  message: 'please_enter_reason'
                                                      .tr(),
                                                  isError: true,
                                                );
                                              }
                                              if (dialogContext.mounted) {
                                                setDialogState(
                                                  () => dialogIsSaving = false,
                                                );
                                              }
                                              return;
                                            }

                                            try {
                                              final isGuest =
                                                  _authService
                                                      .currentUser
                                                      ?.isAnonymous ??
                                                  false;
                                              final type =
                                                  selectedStatus == 'Present'
                                                  ? null
                                                  : selectedLeaveType;
                                              final desc =
                                                  selectedStatus == 'Present'
                                                  ? (reason.isEmpty
                                                        ? null
                                                        : reason)
                                                  : reason;

                                              if (!isGuest) {
                                                final leaveBalanceSynced =
                                                    await _syncAttendanceAnnualLeave(
                                                      worker: workerData,
                                                      selectedStatus:
                                                          selectedStatus,
                                                      leaveType:
                                                          selectedLeaveType,
                                                      reason: reason,
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
                                                      if (workerId.isNotEmpty &&
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
                                                    DummyData.attendance[index]
                                                        .remove('type');
                                                  }
                                                  if (desc != null &&
                                                      desc.isNotEmpty) {
                                                    DummyData
                                                            .attendance[index]['desc'] =
                                                        desc;
                                                  } else {
                                                    DummyData.attendance[index]
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
                                                    'createdAt': DateTime.now(),
                                                  };
                                                  if (type != null)
                                                    newRecord['type'] = type;
                                                  if (desc != null &&
                                                      desc.isNotEmpty)
                                                    newRecord['desc'] = desc;
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
                                                    _periodAttendanceRecords =
                                                        List<Map<String, dynamic>>.from(
                                                          DummyData.attendance,
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
                                              } else {
                                                if (todayRecord.isNotEmpty &&
                                                    todayRecord['id'] != null) {
                                                  await _firestore.updateAttendanceRecord(
                                                    todayRecord['id'],
                                                    {
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
                                                      'type': type,
                                                      'desc': desc,
                                                      'profileImage':
                                                          workerData['profileImage'],
                                                    },
                                                  );
                                                } else {
                                                  await _firestore.addAttendanceRecord({
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
                                                    'type': type,
                                                    'desc': desc,
                                                    'profileImage':
                                                        workerData['profileImage'],
                                                  });
                                                }
                                              }

                                              if (isGuest) {
                                                await DummyData.saveToPrefs();
                                              }

                                              if (!context.mounted) {
                                                if (dialogContext.mounted) {
                                                  setDialogState(
                                                    () =>
                                                        dialogIsSaving = false,
                                                  );
                                                }
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
                                            } catch (e) {
                                              if (!context.mounted) {
                                                if (dialogContext.mounted) {
                                                  setDialogState(
                                                    () =>
                                                        dialogIsSaving = false,
                                                  );
                                                }
                                                return;
                                              }
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
                                            if (mounted) Navigator.pop(context);
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0F52BA),
                                      disabledBackgroundColor: const Color(
                                        0xFFB0BEC5,
                                      ),
                                      disabledForegroundColor: const Color(
                                        0xFFE0E0E0,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
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
    ).then((_) {
      if (mounted) setState(() => _isDialogOpen = false);
    });
  }

  Widget _buildHolidayNotice(String name, {bool isCompanyOffDay = false}) {
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
                : (name.isNotEmpty
                      ? 'Today is $name Holiday'
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/placeholdemptystate.png',
              width: 120,
              height: 100,
              color: const Color(0xFFCBCBCB),
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
                    TimeOffService.remainingPaidLeave(
                      entry.value,
                      _timeOffRecords,
                    ) >
                    0,
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/placeholdemptystate.png',
              width: 120,
              height: 100,
              color: const Color(0xFFCBCBCB),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E5EA),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Attendance Marked',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
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
            if (data["type"] != null) ...[
              const SizedBox(height: 12),
              Text(
                (data["status"] == 'Leave'
                        ? 'leave_type_display'
                        : 'absent_type')
                    .tr(namedArgs: {'type': data["type"].toString()}),
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
    Color textColor = Color(0xFFFFFFFF);
    final displayStatus = (status.isEmpty || status == "*****")
        ? "*****"
        : status;

    if (displayStatus == "*****") {
      bgColor = pillGray;
      textColor = textDark;
    } else if (displayStatus == "Present") {
      bgColor = greenPresent;
    } else if (displayStatus == "Absent") {
      bgColor = redAbsent;
    } else if (displayStatus == "Leave") {
      bgColor = orangeLeave;
    } else {
      bgColor = pillGray;
      textColor = textDark;
    }

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
