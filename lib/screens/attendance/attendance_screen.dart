import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';

import 'package:csv/csv.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../riverpod_providers.dart';
import '../../services/attendance_report_service.dart';
import '../../services/attendance_service.dart';
import '../../services/auth_service.dart';
import '../../services/dummy_data.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../services/time_off_service.dart';
import '../../utils/utils.dart';
import '../../widgets/clickable_gesture_detector.dart';
import '../../widgets/custom_timeframe_dropdown.dart';
import '../../widgets/notification_bell.dart';
import 'workers_attendance_screen.dart';

const Color _kPrimaryBlue = AppColors.buttonBlue;
const Color _kBgGray = AppColors.bgGrayLight;
const Color _kTextDark = AppColors.black;
const Color _kGreenPresent = AppColors.presentGreen;
const Color _kRedAbsent = Color(0xFFF13E5B);
const Color _kOrangeLeave = AppColors.leaveOrange;

String _generateCsvString(List<List<dynamic>> rows) {
  return '\ufeff${const CsvEncoder().convert(rows)}';
}

String _localizeSharePeriod(String period) {
  return switch (period) {
    'Today' => 'today'.tr(),
    'Weekly' => 'weekly'.tr(),
    'Monthly' => 'monthly'.tr(),
    '6 Monthly' => '6_month'.tr(),
    'Yearly' => 'yearly'.tr(),
    'Custom' => 'custom'.tr(),
    _ => period,
  };
}

class AttendanceRecord {
  final String name;
  final String email;
  final String role;
  final String status;
  final String attendanceType;
  final String workType;
  final String? profileImage;
  final String? phone;

  const AttendanceRecord({
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.attendanceType = 'Remote',
    this.workType = 'Full Time',
    this.profileImage,
    this.phone,
  });

  String get localizedWorkType => switch (workType) {
        'Full Time' => 'full_time'.tr(),
        'Part Time' => 'part_time'.tr(),
        'Contract' => 'contract'.tr(),
        _ => workType,
      };

  String get localizedAttendanceType => switch (attendanceType) {
        'On-Site' => 'on_site'.tr(),
        'Remote' => 'remote'.tr(),
        'Hybrid' => 'hybrid'.tr(),
        _ => attendanceType,
      };
}

class AttendanceScreen extends ConsumerStatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onWorkersAttendanceTap;

  const AttendanceScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
    this.onWorkersAttendanceTap,
  });

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late final AuthService _authService;
  late final FirestoreService _firestore;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTab = 'All';
  String _selectedTimeframe = 'Today';

  List<Map<String, dynamic>> _attendanceDocs = [];
  List<Map<String, dynamic>> _workersList = [];
  List<Map<String, dynamic>> _rawAttendanceDocs = [];
  List<Map<String, dynamic>> _timeOffRecords = [];

  bool _isLoading = true;
  bool _workersLoaded = false;
  bool _attendanceLoaded = false;
  bool _initialized = false;

  int _presentCount = 0;
  int _absentCount = 0;
  int _leaveCount = 0;

  StreamSubscription? _workersSub;
  StreamSubscription? _timeOffSub;
  StreamSubscription? _attendanceSub;
  Timer? _searchDebounce;

  List<Map<String, dynamic>>? _cachedFiltered;
  String _filterCacheKey = '';

  String _selectedSharePeriod = 'Today';
  final LayerLink _shareDropdownLink = LayerLink();
  final GlobalKey _shareButtonKey = GlobalKey();
  OverlayEntry? _shareDropdownOverlay;
  bool _isShareDropdownOpen = false;

  int _attendanceRequestId = 0;
  bool _streamSnapshotDelivered = false;

  ValueNotifier<List<Map<String, dynamic>>>? _attendancePreviewNotifier;
  Map<String, dynamic>? _attendancePreviewWorkerDoc;

  static const List<String> _sharePeriodOptions = [
    'Today',
    'Weekly',
    'Monthly',
    '6 Monthly',
    'Yearly',
    'Custom',
  ];

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  @override
  void initState() {
    super.initState();
    _attendanceDocs = [];
    _workersList = [];
    _rawAttendanceDocs = [];
    _isLoading = true;
    _workersLoaded = false;
    _attendanceLoaded = false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (_isGuest) {
      _loadGuestData();
    } else {
      _loadFirestoreData();
    }
  }

  @override
  void deactivate() {
    _removeShareDropdownOverlay();
    _isShareDropdownOpen = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _removeShareDropdownOverlay();
    _workersSub?.cancel();
    _timeOffSub?.cancel();
    _attendanceSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _attendancePreviewNotifier?.dispose();
    _initialized = false;
    super.dispose();
  }

  void _loadGuestData() {
    _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
    _rawAttendanceDocs = List<Map<String, dynamic>>.from(DummyData.attendance);
    _timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
    _workersLoaded = true;
    _attendanceLoaded = true;
    _combineAttendance();
  }

  void _loadFirestoreData() {
    _workersSub = _firestore.workersStream.listen(
      (snapshot) {
        if (!mounted) return;
        setState(() {
          _workersList = snapshot.docs
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
              .toList();
          _workersLoaded = true;
          _combineAttendance();
        });
        _loadAttendanceForTimeframe();
      },
      onError: (_) {
        if (mounted) setState(() { _workersLoaded = true; _isLoading = false; });
      },
    );

    _loadAttendanceForTimeframe();

    _timeOffSub = _firestore.timeoffStream.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _timeOffRecords = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        _combineAttendance();
      });
      _refreshAttendancePreview();
    }, onError: (_) {});
  }

  void _combineAttendance() {
    _cachedFiltered = null;
    _filterCacheKey = '';

    final periodAttendance = _rawAttendanceDocs
        .where((r) => AppDateUtils.isAttendanceRecordWithinPeriod(r, _selectedTimeframe))
        .toList()
      ..sort((a, b) {
        final aDate = AppDateUtils.attendanceRecordDate(a);
        final bDate = AppDateUtils.attendanceRecordDate(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        final byDate = bDate.compareTo(aDate);
        if (byDate != 0) return byDate;
        return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
      });

    _attendanceDocs = AttendanceService.combineAttendance(
      workersList: _workersList,
      rawAttendanceDocs: periodAttendance,
    ).map((record) {
      final recordDate = AppDateUtils.attendanceRecordDate(record);
      final statusDate = recordDate ??
          (_selectedTimeframe == 'Today' ? AppDateUtils.periodStart('Today', DateTime.now()) : null);

      if (statusDate != null &&
          TimeOffService.isWorkerOnLeave(record, _timeOffRecords, onDate: statusDate)) {
        return {...record, 'status': 'Leave'};
      }
      return record;
    }).toList();

    if (_workersLoaded && _attendanceLoaded) _isLoading = false;

    final countable = _selectedTimeframe == 'Today' ? _attendanceDocs : periodAttendance;
    final counts = AttendanceService.countRecordsByStatus(
      countable,
      _timeOffRecords,
      period: _selectedTimeframe,
      referenceDate: DateTime.now(),
    );
    _presentCount = counts['present'] ?? 0;
    _absentCount = counts['absent'] ?? 0;
    _leaveCount = counts['leave'] ?? 0;
  }

  void _loadAttendanceForTimeframe() {
    final now = DateTime.now();
    final start = AppDateUtils.periodStart(_selectedTimeframe, now);
    final periodEndDate = AppDateUtils.periodEnd(_selectedTimeframe, now);
    final end = DateTime(periodEndDate.year, periodEndDate.month, periodEndDate.day, 23, 59, 59, 999);

    final requestId = ++_attendanceRequestId;
    final requestedPeriod = _selectedTimeframe;
    _streamSnapshotDelivered = false;

    if (_isGuest) {
      _rawAttendanceDocs = List<Map<String, dynamic>>.from(DummyData.attendance);
      _attendanceLoaded = true;
      _combineAttendance();
      return;
    }

    _subscribeAttendanceStream(start, end, requestId);
    _fetchAttendanceFallback(start, end, requestId, requestedPeriod);
  }

  void _subscribeAttendanceStream(DateTime start, DateTime end, int requestId) {
    _attendanceSub?.cancel();
    _attendanceSub = _firestore.attendanceStreamForPeriod(start: start, end: end).listen(
      (snapshot) {
        if (!mounted || requestId != _attendanceRequestId) return;
        setState(() {
          _rawAttendanceDocs = snapshot.docs
              .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
              .toList();
          _attendanceLoaded = true;
          _streamSnapshotDelivered = true;
          _combineAttendance();
        });
        _refreshAttendancePreview();
      },
      onError: (e) {
        ErrorReporter.report(e, StackTrace.current, context: 'attendanceScreenStream');
        if (!mounted || requestId != _attendanceRequestId) return;
        _streamSnapshotDelivered = false;
        _firestore.getAttendanceForPeriod(start, end).then((snapshot) {
          if (!mounted || requestId != _attendanceRequestId) return;
          setState(() {
            _rawAttendanceDocs = snapshot.docs
                .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                .toList();
            _attendanceLoaded = true;
            _combineAttendance();
          });
          _refreshAttendancePreview();
        }).catchError((_) {});
      },
    );
  }

  void _fetchAttendanceFallback(DateTime start, DateTime end, int requestId, String requestedPeriod) {
    _firestore.getAttendanceForPeriod(start, end).then((snapshot) {
      if (!mounted || requestId != _attendanceRequestId || requestedPeriod != _selectedTimeframe) return;
      if (_streamSnapshotDelivered) return;
      setState(() {
        _rawAttendanceDocs = snapshot.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .toList();
        _attendanceLoaded = true;
        _combineAttendance();
      });
      _refreshAttendancePreview();
    }).catchError((_) {
      if (!mounted || requestId != _attendanceRequestId || requestedPeriod != _selectedTimeframe) return;
      if (mounted) setState(() { _attendanceLoaded = true; _isLoading = false; });
    });
  }

  String _getTimeframeTitle() {
    return switch (_selectedTimeframe) {
      'Today' => 'today_attendance'.tr(),
      'Week' || 'This Week' => 'weekly_attendance'.tr(),
      'Month' || 'This Month' => 'monthly_attendance'.tr(),
      '6 Month' || 'Last 6 Months' => 'six_month_attendance'.tr(),
      'Yearly' || 'This Year' => 'yearly_attendance'.tr(),
      _ => 'today_attendance'.tr(),
    };
  }

  List<Map<String, dynamic>> get _filteredRecords {
    final key = '${_attendanceDocs.length}_$_searchQuery$_selectedTab$_selectedTimeframe';
    if (_cachedFiltered != null && _filterCacheKey == key) return _cachedFiltered!;

    _filterCacheKey = key;
    final query = _searchQuery.toLowerCase();

    _cachedFiltered = _attendanceDocs.where((doc) {
      if (AppDateUtils.attendanceRecordDate(doc) != null &&
          !AppDateUtils.isAttendanceRecordWithinPeriod(doc, _selectedTimeframe)) {
        return false;
      }

      if (query.isNotEmpty) {
        final name = (doc['name'] ?? '').toString().toLowerCase();
        final role = (doc['role'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !role.contains(query)) return false;
      }

      final status = (doc['status'] ?? '').toString();
      return switch (_selectedTab) {
        'All' => true,
        'Present' => status == 'Present',
        'Absent' => status == 'Absent',
        'Leaves' => status == 'Leave',
        _ => false,
      };
    }).toList();

    return _cachedFiltered!;
  }

  List<Map<String, dynamic>> _filterWorkerRecords(
    Map<String, dynamic> doc, {
    String? periodOverride,
  }) {
    return AttendanceReportService.recordsForWorker(
      worker: doc,
      attendanceRecords: _rawAttendanceDocs,
      timeOffRecords: _timeOffRecords,
      range: AttendanceReportService.rangeForPeriod(periodOverride ?? _selectedTimeframe),
    );
  }

  void _refreshAttendancePreview() {
    final notifier = _attendancePreviewNotifier;
    final workerDoc = _attendancePreviewWorkerDoc;
    if (notifier != null && workerDoc != null) {
      notifier.value = _filterWorkerRecords(workerDoc, periodOverride: _selectedTimeframe);
    }
  }

  void _removeShareDropdownOverlay() {
    final overlay = _shareDropdownOverlay;
    _shareDropdownOverlay = null;
    if (overlay != null && overlay.mounted) overlay.remove();
  }

  void _dismissShareDropdown() {
    _removeShareDropdownOverlay();
    if (mounted && _isShareDropdownOpen) setState(() => _isShareDropdownOpen = false);
  }

  void _showShareDropdown() {
    if (!mounted || _shareDropdownOverlay != null) return;

    final buttonContext = _shareButtonKey.currentContext;
    final buttonRender = buttonContext?.findRenderObject();
    final overlayState = Overlay.maybeOf(context);

    if (buttonRender is! RenderBox || !buttonRender.attached || overlayState == null) return;

    final size = buttonRender.size;

    _shareDropdownOverlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          GestureDetector(
            onTap: _dismissShareDropdown,
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent, width: double.infinity, height: double.infinity),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _shareDropdownLink,
              showWhenUnlinked: false,
              offset: const Offset(0, 50),
              child: Material(
                elevation: 4,
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCFCFC),
                    border: Border.all(color: Colors.grey.shade300, width: 1.5),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _sharePeriodOptions.map((option) {
                      final isSelected = _selectedSharePeriod == option;
                      return GestureDetector(
                        onTap: () {
                          _dismissShareDropdown();
                          if (option == 'Custom') {
                            _showCustomDateRangePicker();
                          } else {
                            setState(() => _selectedSharePeriod = option);
                            _generateAndShareAttendance(option);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF0247C4) : Colors.grey.shade400,
                                    width: 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? Center(
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF0247C4),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _localizeSharePeriod(option),
                                  style: TextStyle(
                                    fontSize: 17.0,
                                    color: isSelected ? _kPrimaryBlue : Colors.grey.shade400,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlayState.insert(_shareDropdownOverlay!);
    if (mounted) setState(() => _isShareDropdownOpen = true);
  }

  Future<void> _showCustomDateRangePicker() async {
    DateTime calendarDate = DateTime.now();
    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final selectedDates = <DateTime>{};
    DateTime? dragAnchorDate;
    bool dragMoved = false;
    Offset? dragStartPosition;
    Offset? dragCurrentPosition;
    Set<DateTime> selectionBeforeDrag = {};
    final GlobalKey calendarHeaderKey = GlobalKey();

    double measuredHeaderHeight() {
      final ctx = calendarHeaderKey.currentContext;
      if (ctx == null) return 0;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return 0;
      return box.size.height;
    }

    DateTime? dateAtPosition(Offset position, DateTime monthDate) {
      const dialogWidth = 400.0;
      const padding = 12.0;
      const gap = 8.0;
      const availableWidth = dialogWidth - (padding * 2);
      const cellWidth = (availableWidth - (gap * 6)) / 7;
      const colPitch = cellWidth + gap;
      const rowPitch = cellWidth + gap;
      final headerHeight = measuredHeaderHeight() > 0 ? measuredHeaderHeight() : 18.0 + 10.0 + 12.0 + 30.0;

      final adjustedDy = position.dy - headerHeight;
      if (adjustedDy < 0) return null;

      final column = (position.dx / colPitch).floor();
      final row = (adjustedDy / rowPitch).floor();
      if (column < 0 || column > 6 || row < 0 || row > 5) return null;

      final daysInMonth = DateTime(monthDate.year, monthDate.month + 1, 0).day;
      final firstWeekday = DateTime(monthDate.year, monthDate.month, 1).weekday;
      final startOffset = firstWeekday == 7 ? 0 : firstWeekday;
      final day = (row * 7) + column - startOffset + 1;
      if (day < 1 || day > daysInMonth) return null;

      return DateTime(monthDate.year, monthDate.month, day);
    }

    final result = await showDialog<List<DateTime>?>(
      context: context,
      barrierColor: _kPrimaryBlue.withOpacity(0.5),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              backgroundColor: const Color(0xFFFFFFFF),
              elevation: 10,
              child: Container(
                width: 400,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 0,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.black, size: 20),
                              onPressed: () => Navigator.of(ctx).pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          Center(
                            child: Text(
                              'select_dates'.tr(),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPrimaryBlue,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: selectedDates.isEmpty
                                  ? null
                                  : () => Navigator.of(ctx).pop(selectedDates.toList()..sort()),
                              child: Text(
                                'generate'.tr(namedArgs: {'count': selectedDates.length.toString()}),
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Listener(
                      onPointerDown: (event) {
                        dragAnchorDate = dateAtPosition(event.localPosition, calendarDate);
                        dragStartPosition = event.localPosition;
                        dragMoved = false;
                        selectionBeforeDrag = Set<DateTime>.from(selectedDates);
                        setModalState(() {});
                      },
                      onPointerMove: (event) {
                        if (dragStartPosition != null && !dragMoved) {
                          final dx = (event.localPosition.dx - dragStartPosition!.dx).abs();
                          final dy = (event.localPosition.dy - dragStartPosition!.dy).abs();
                          if (dx > 5 || dy > 5) dragMoved = true;
                        }
                        if (!dragMoved || dragAnchorDate == null) return;

                        final current = dateAtPosition(event.localPosition, calendarDate);
                        if (current == null) return;
                        dragCurrentPosition = event.localPosition;

                        setModalState(() {
                          selectedDates
                            ..clear()
                            ..addAll(selectionBeforeDrag);
                          final isDragRemoving = selectionBeforeDrag.contains(dragAnchorDate);
                          final start = dragAnchorDate!.isBefore(current) ? dragAnchorDate! : current;
                          final end = dragAnchorDate!.isAfter(current) ? dragAnchorDate! : current;
                                                                              final safeStart = start.isAfter(today) ? today : start;
                          final safeEnd = end.isAfter(today) ? today : end;
                          for (var d = safeStart; !d.isAfter(safeEnd); d = d.add(const Duration(days: 1))) {
                            isDragRemoving ? selectedDates.remove(d) : selectedDates.add(d);
                          }
                        });
                      },
                      onPointerUp: (event) {
                        if (!dragMoved && dragAnchorDate != null) {
                          final date = dragAnchorDate!;
                          final isFuture = date.isAfter(today);
                          setModalState(() {
                            final exists = selectedDates.any(
                              (d) => d.year == date.year && d.month == date.month && d.day == date.day,
                            );
                                                                                    if (isFuture && !exists) return;
                            exists
                                ? selectedDates.removeWhere(
                                    (d) => d.year == date.year && d.month == date.month && d.day == date.day)
                                : selectedDates.add(date);
                          });
                        }
                        dragAnchorDate = null;
                        dragStartPosition = null;
                        dragCurrentPosition = null;
                        dragMoved = false;
                        selectionBeforeDrag = {};
                        setModalState(() {});
                      },
                      child: _buildCalendarWithWeekdays(
                        calendarDate,
                        selectedDates,
                        (_) {},
                        (newDate) => setModalState(() => calendarDate = newDate),
                        dragAnchor: dragAnchorDate,
                        dragCurrent: dragMoved && dragCurrentPosition != null
                            ? dateAtPosition(dragCurrentPosition!, calendarDate)
                            : null,
                        isDragRemoving:
                            dragMoved && dragAnchorDate != null && selectionBeforeDrag.contains(dragAnchorDate),
                        headerKey: calendarHeaderKey,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      _dismissShareDropdown();
      setState(() => _selectedSharePeriod = 'Custom');
      await _generateAndShareAttendance('Custom', startDate: result.first, endDate: result.last);
    }
  }

  Future<void> _generateAndShareAttendance(
    String period, {
    DateTime? startDate,
    DateTime? endDate,
    Set<DateTime>? customSelectedDates,
  }) async {
    try {
      late final AttendanceDateRange range;

      if (period == 'Custom') {
        if (startDate == null || endDate == null) {
          FlashySnackBar.show(context, message: 'please_select_date_range'.tr(), isError: true);
          return;
        }
        range = AttendanceDateRange(
          start: DateTime(startDate.year, startDate.month, startDate.day),
          end: DateTime(endDate.year, endDate.month, endDate.day),
          discreteDates: customSelectedDates,
        );
      } else {
        range = AttendanceReportService.rangeForPeriod(period);
      }

                        final reportNow = DateTime.now();
      final reportToday = DateTime(
        reportNow.year,
        reportNow.month,
        reportNow.day,
      );
      if (period == 'Custom' && _containsFutureDate(range, reportToday)) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'future_dates_attendance_report_blocked'.tr(),
            isError: true,
          );
        }
        return;
      }

      final rows = _buildReportRows(period, range);
      final csvString = await compute(_generateCsvString, rows);
      final csvBytes = Uint8List.fromList(utf8.encode(csvString));
      final fileName =
          'attendance_${period.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.csv';

      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'save_attendance_report'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: csvBytes,
      );

      if (outputFile == null) return;
      await File(outputFile).writeAsBytes(csvBytes);

      if (mounted) {
        FlashySnackBar.show(context, message: 'attendance_report_saved'.tr(namedArgs: {'file': fileName}));
        await FileOpener.open(outputFile);
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: 'error_generating_report'.tr(namedArgs: {'error': '$e'}), isError: true);
      }
    }
  }

  bool _containsFutureDate(AttendanceDateRange range, DateTime today) {
    if (range.discreteDates != null && range.discreteDates!.isNotEmpty) {
      return range.discreteDates!.any((d) {
        final day = DateTime(d.year, d.month, d.day);
        return day.isAfter(today);
      });
    }
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);
    return endDay.isAfter(today);
  }

  List<List<dynamic>> _buildReportRows(String period, AttendanceDateRange range) {
    final rows = <List<dynamic>>[];
    final periodLabel = _localizeSharePeriod(period);
    final rangeLabel =
        '${AttendanceReportService.csvTextDate(range.start).trim()} to ${AttendanceReportService.csvTextDate(range.end).trim()}';

    int overallPresents = 0, overallAbsents = 0, overallLeaves = 0;

    for (final worker in _workersList) {
      final snapshot = AttendanceReportService.snapshotForWorker(
        worker: worker,
        attendanceRecords: _rawAttendanceDocs,
        timeOffRecords: _timeOffRecords,
        range: range,
      );
      overallPresents += snapshot.presents;
      overallAbsents += snapshot.absents;
      overallLeaves += snapshot.leaves;
    }

    rows.add(['Attendance Report - $periodLabel']);
    rows.add(['Period: $rangeLabel']);
    rows.add(['Generated On: ${AttendanceReportService.csvTextDate(DateTime.now()).trim()}']);
    rows.add(['total_present'.tr(), overallPresents]);
    rows.add(['total_absent'.tr(), overallAbsents]);
    rows.add(['total_on_leave'.tr(), overallLeaves]);
    rows.add([]);

    for (final worker in _workersList) {
      _addWorkerReportSection(rows, worker, range);
    }

    return rows;
  }

  void _addWorkerReportSection(
    List<List<dynamic>> rows,
    Map<String, dynamic> worker,
    AttendanceDateRange range,
  ) {
    final snapshot = AttendanceReportService.snapshotForWorker(
      worker: worker,
      attendanceRecords: _rawAttendanceDocs,
      timeOffRecords: _timeOffRecords,
      range: range,
    );

    final name = (worker['name'] ?? worker['workerName'] ?? 'Worker').toString();
    final email = (worker['email'] ?? '').toString();
    final phone = (worker['phone'] ?? worker['contact'] ?? '').toString();
    final position = (worker['position'] ?? worker['role'] ?? '').toString();
    final workType = (worker['type1'] ?? worker['workType'] ?? 'Full Time').toString();
    final attendanceType = (worker['type2'] ?? worker['attendanceType'] ?? 'On-Site').toString();

    rows.add(['${'report_worker'.tr()}: $name']);
    rows.add(['${'report_email'.tr()}: $email']);
    if (phone.isNotEmpty) rows.add(['${'report_phone'.tr()}: $phone']);
    rows.add(['${'report_position'.tr()}: $position']);
    rows.add(['${'work_type'.tr()}: $workType']);
    rows.add(['${'attendance_type'.tr()}: $attendanceType']);
    rows.add([]);

    rows.add(['report_date'.tr(), 'report_status'.tr(), 'work_type'.tr(), 'attendance_type'.tr(), 'report_reason_notes'.tr()]);

    if (snapshot.records.isEmpty) {
      rows.add(['no_attendance_records_period'.tr(), '', '', '', '']);
    } else {
      for (final record in snapshot.records) {
        rows.add([
          AttendanceReportService.csvTextDate(AttendanceReportService.recordDateForRecord(record)),
          record['status'] ?? '-',
          record['workType'] ?? workType,
          record['attendanceType'] ?? attendanceType,
          record['desc'] ?? record['reason'] ?? '',
        ]);
      }
    }

    rows.add([]);
    rows.add(['total_working_days'.tr(), snapshot.totalWorkingDays]);
    rows.add(['total_present'.tr(), snapshot.presents]);
    rows.add(['total_absent'.tr(), snapshot.absents]);
    rows.add(['total_leave'.tr(), snapshot.leaves]);
    rows.add(['attendance_percent'.tr(), snapshot.percentage.toStringAsFixed(1)]);
    rows.add([]);
  }

  void _showAttendancePreview(BuildContext context, Map<String, dynamic> doc) {
    if (_isGuest) {
      showGuestRestrictionDialog(context);
      return;
    }

    final previewPeriod = _selectedTimeframe;
    _attendancePreviewNotifier?.dispose();

    final notifier = ValueNotifier<List<Map<String, dynamic>>>(
      _filterWorkerRecords(doc, periodOverride: previewPeriod),
    );

    final record = AttendanceRecord(
      name: (doc['name'] ?? '').toString(),
      email: (doc['email'] ?? '').toString(),
      role: (doc['role'] ?? '').toString(),
      status: (doc['status'] ?? '').toString(),
      attendanceType: (doc['attendanceType'] ?? 'Remote').toString(),
      workType: (doc['workType'] ?? 'Full Time').toString(),
      profileImage: doc['profileImage']?.toString(),
      phone: doc['phone']?.toString(),
    );

    showDialog(
      context: context,
      barrierColor: _kPrimaryBlue.withOpacity(0.5),
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: notifier,
          builder: (_, filteredRecords, _) {
            final now = DateTime.now();
            final range = AttendanceReportService.rangeForPeriod(previewPeriod, referenceDate: now);
            final filteredForRange = filteredRecords.where((record) {
              final recordDate = AttendanceReportService.recordDateForRecord(record);
              if (recordDate == null) return false;
              final day = DateTime(recordDate.year, recordDate.month, recordDate.day);
              return !day.isBefore(range.start) && !day.isAfter(range.end);
            }).toList();

            final totalDays = filteredForRange.length;
            final absents = filteredForRange.where((d) => d['status'] == 'Absent').length;
            final leaves = filteredForRange.where((d) => d['status'] == 'Leave').length;
            final presents = filteredForRange.where((d) => d['status'] == 'Present').length;
            final percentage = totalDays > 0 ? (presents / totalDays) * 100 : 0.0;

            return WorkerAttendancePreviewCard(
              record: record,
              totalWorkingDays: totalDays,
              presents: presents,
              absents: absents,
              leaves: leaves,
              percentage: percentage,
              workerRecords: filteredForRange,
              period: previewPeriod,
            );
          },
        ),
      ),
    );

    _attendancePreviewNotifier = notifier;
    _attendancePreviewWorkerDoc = doc;
  }

  Widget _buildCalendarWithWeekdays(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
    ValueChanged<DateTime> onDaySelected,
    ValueChanged<DateTime> onMonthChanged, {
    DateTime? dragAnchor,
    DateTime? dragCurrent,
    bool isDragRemoving = false,
    Key? headerKey,
  }) {
    final monthYearStr =
        '${DateFormat('MMMM', context.locale.toString()).format(calendarDate).toUpperCase()} ${calendarDate.year}';

    return Column(
      children: [
        Container(
          key: headerKey,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => onMonthChanged(DateTime(calendarDate.year, calendarDate.month - 1, 1)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.chevron_left, size: 20, color: Colors.black),
                    ),
                  ),
                  Text(monthYearStr,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, )),
                  GestureDetector(
                    onTap: () => onMonthChanged(DateTime(calendarDate.year, calendarDate.month + 1, 1)),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.chevron_right, size: 20, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                    .map((day) => _buildWeekdayLabel(day, _kPrimaryBlue))
                    .expand((w) => [w, const SizedBox(width: 8)])
                    .toList()
                  ..removeLast(),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        _buildDaysGridForRange(
          calendarDate,
          selectedDates,
          onDaySelected,
          dragAnchor: dragAnchor,
          dragCurrent: dragCurrent,
          isDragRemoving: isDragRemoving,
        ),
      ],
    );
  }

  Widget _buildWeekdayLabel(String day, Color color) {
    return Expanded(
      child: Container(
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(
          day.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildDaysGridForRange(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
    ValueChanged<DateTime> onDaySelected, {
    DateTime? dragAnchor,
    DateTime? dragCurrent,
    bool isDragRemoving = false,
  }) {
    final daysInMonth = DateTime(calendarDate.year, calendarDate.month + 1, 0).day;
    final firstWeekday = DateTime(calendarDate.year, calendarDate.month, 1).weekday;
    final startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    final dragRange = <DateTime>{};
    if (dragAnchor != null && dragCurrent != null) {
      final start = dragAnchor.isBefore(dragCurrent) ? dragAnchor : dragCurrent;
      final end = dragAnchor.isAfter(dragCurrent) ? dragAnchor : dragCurrent;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        dragRange.add(d);
      }
    }

    int currentDay = 1;
    final rows = <Widget>[];

    for (int i = 0; i < 6; i++) {
      final rowChildren = <Widget>[];
      for (int j = 0; j < 7; j++) {
        final index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(_buildDayCell('', false, false, null, null));
        } else if (currentDay <= daysInMonth) {
          final day = currentDay;
          final date = DateTime(calendarDate.year, calendarDate.month, day);
          final isSelected = selectedDates.any(
            (d) => d.year == date.year && d.month == date.month && d.day == date.day,
          );
          final isDragPreview = dragRange.contains(date) && !isDragRemoving;
          rowChildren.add(_buildDayCell('$day', isSelected, isDragPreview, () => onDaySelected(date), date));
          currentDay++;
        } else {
          rowChildren.add(_buildDayCell('', false, false, null, null));
        }
        if (j < 6) rowChildren.add(const SizedBox(width: 8));
      }
      rows.add(Row(children: rowChildren));
      if (currentDay > daysInMonth && i >= 4) break;
      if (i < 5) rows.add(const SizedBox(height: 8));
    }

    return Column(children: rows);
  }

  Widget _buildDayCell(String day, bool isSelected, bool isDragPreview, VoidCallback? onTap, DateTime? date) {
    if (day.isEmpty) return const Expanded(child: AspectRatio(aspectRatio: 1, child: SizedBox()));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isFuture = date != null && date.isAfter(today);

    const selectedBg = _kPrimaryBlue;
    final isHighlighted = isSelected || isDragPreview;

    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: isFuture ? null : onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isHighlighted ? selectedBg : Colors.transparent,
              border: Border.all(color: isHighlighted ? selectedBg : Colors.grey.shade300, width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              day,
              style: TextStyle(
                color: isHighlighted
                    ? const Color(0xFFFFFFFF)
                    : (isFuture ? Colors.grey.shade400 : Colors.black),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: _kBgGray,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchAndActionRow(),
                  const SizedBox(height: 24),
                  _buildSummaryCardsRow(),
                  const SizedBox(height: 24),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  _buildAttendanceSection(filtered),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceSection(List<Map<String, dynamic>> filtered) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _getTimeframeTitle(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _kTextDark,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const Spacer(),
            CustomTimeframeDropdown(
              selectedPeriod: _selectedTimeframe,
              onChanged: (value) {
                setState(() {
                  _selectedTimeframe = value;
                  _cachedFiltered = null;
                  _filterCacheKey = '';
                });
                _loadAttendanceForTimeframe();
                _refreshAttendancePreview();
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filtered.isEmpty)
          _buildEmptyState()
        else
          _buildAttendanceTable(filtered),
      ],
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
                  color: _kTextDark,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
          const Spacer(),
          NotificationBell(onTap: widget.onNotificationTap),
          const SizedBox(width: 20),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: widget.onProfileTap, child: const UserAvatar()),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndActionRow() {
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
                SvgPicture.asset('assets/search icon.svg', width: 24, height: 24,
                    colorFilter: const ColorFilter.mode(Color(0xFFBDBDBD), BlendMode.srcIn)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      _searchQuery = val;
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 250), () {
                        if (mounted) setState(() {});
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'search_workers_name_position'.tr(),
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              if (_isGuest) { showGuestRestrictionDialog(context); return; }
              if (widget.onWorkersAttendanceTap != null) {
                widget.onWorkersAttendanceTap!();
              } else {
                Navigator.of(context).push(PageRouteBuilder(
                  pageBuilder: (_, _, _) => WorkersAttendanceScreen(
                    onNotificationTap: widget.onNotificationTap,
                    onProfileTap: widget.onProfileTap,
                  ),
                  transitionsBuilder: (_, _, _, child) => child,
                  transitionDuration: Duration.zero,
                ));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimaryBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Text(
              'workers_attendance'.tr(),
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildShareButton(),
      ],
    );
  }

  Widget _buildShareButton() {
    return CompositedTransformTarget(
      link: _shareDropdownLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: _shareButtonKey,
          onTap: () {
            if (_isGuest) { showGuestRestrictionDialog(context); return; }
            _isShareDropdownOpen ? _dismissShareDropdown() : _showShareDropdown();
          },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: _kPrimaryBlue,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(6),
                topRight: const Radius.circular(6),
                bottomLeft: Radius.circular(_isShareDropdownOpen ? 0 : 6),
                bottomRight: Radius.circular(_isShareDropdownOpen ? 0 : 6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Text(
                    'share_attendance'.tr(),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontWeight: FontWeight.w600,
                      fontSize: 14.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, color: Color(0xFFFFFFFF), size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCardsRow() {
    final isToday = _selectedTimeframe == 'Today';
    return Row(
      children: [
        Expanded(child: _buildSummaryCard(
          title: 'total_workers'.tr(), count: '${_workersList.length}',
          iconAsset: 'assets/total_workers.svg', countColor: _kPrimaryBlue,
        )),
        const SizedBox(width: 10),
        Expanded(child: _buildSummaryCard(
          title: isToday ? 'Present'.tr() : 'present_days'.tr(), count: '$_presentCount',
          iconAsset: 'assets/present_worker.svg', countColor: _kGreenPresent,
        )),
        const SizedBox(width: 10),
        Expanded(child: _buildSummaryCard(
          title: isToday ? 'Absent'.tr() : 'absent_days'.tr(), count: '$_absentCount',
          iconAsset: 'assets/absent.svg', countColor: _kRedAbsent,
        )),
        const SizedBox(width: 10),
        Expanded(child: _buildSummaryCard(
          title: isToday ? 'On leave'.tr() : 'leave_days'.tr(), count: '$_leaveCount',
          iconAsset: 'assets/leave.svg', countColor: _kOrangeLeave,
        )),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title, required String count,
    required String iconAsset, required Color countColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [BoxShadow(color: const Color(0xFF000000).withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kTextDark, ),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
                const SizedBox(height: 12),
                Text(count, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: countColor, ),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
              ],
            ),
          ),
          iconAsset.endsWith('.svg')
              ? SvgPicture.asset(iconAsset, height: 28, width: 28)
              : Image.asset(iconAsset, height: 28, width: 28),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    final tabs = [
      ('All', 'all_tab'.tr()),
      ('Present', 'present_tab'.tr()),
      ('Absent', 'absent_tab'.tr()),
      ('Leaves', 'leaves_tab'.tr()),
    ];

    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < tabs.length; i++) ...[
              _buildTab(tabs[i].$1, tabs[i].$2),
              if (i < tabs.length - 1)
                Container(
                  width: 1,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  color: const Color(0xFFE5E7EB).withOpacity(0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String filterKey, String displayLabel) {
    final isActive = _selectedTab == filterKey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => setState(() { _selectedTab = filterKey; _cachedFiltered = null; _filterCacheKey = ''; }),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isActive ? 8 : 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? _kPrimaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            displayLabel,
            style: TextStyle(
              color: isActive ? const Color(0xFFFFFFFF) : _kTextDark,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final dynamicHeight = (MediaQuery.of(context).size.height - 350).clamp(600.0, 1200.0);
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/placeholder_workers.svg', width: 120, height: 100,
              colorFilter: const ColorFilter.mode(Color(0xFFCBCBCB), BlendMode.srcIn)),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'no_search_results'.tr() : 'no_attendance_records'.tr(),
            style: const TextStyle(color: _kPrimaryBlue, fontSize: 16, fontWeight: FontWeight.w600, ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTable(List<Map<String, dynamic>> records) {
    final tableHeight = (MediaQuery.of(context).size.height - 350).clamp(600.0, 1200.0);

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(6)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 12),
            child: Row(
              children: [
                Expanded(flex: 3, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('worker_name_header'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('status_header'.tr()))),
                Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 16), child: _tableHeader('work_type'.tr()))),
                Expanded(flex: 2, child: _tableHeader('position'.tr())),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFF7F8FC)),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _buildAttendanceRow(records[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRow(Map<String, dynamic> doc) {
    final name = (doc['name'] ?? '').toString();
    final email = (doc['email'] ?? '').toString();
    final role = (doc['role'] ?? '').toString();
    final workType = (doc['workType'] ?? 'Full Time').toString();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _showAttendancePreview(context, doc),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: const Color(0xFFF6F8FA), borderRadius: BorderRadius.circular(6)),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Row(
                    children: [
                      WorkerAvatar(imageUrl: doc['profileImage']?.toString(), name: name, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _kTextDark, ),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text(email, style: const TextStyle(fontSize: 14, color: Colors.black, ),
                                overflow: TextOverflow.ellipsis, maxLines: 1),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(right: 24), child: _buildStatusText(doc))),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Text(LocalizationHelper.localizeType1(workType),
                      style: const TextStyle(fontSize: 15, color: _kTextDark, ),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(LocalizationHelper.localizePosition(role),
                    style: const TextStyle(fontSize: 15, color: _kTextDark, ),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              SizedBox(
                width: 48,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAttendancePreview(context, doc),
                    child: const Icon(Icons.visibility, color: Colors.black, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusText(Map<String, dynamic> worker) {
    if (_selectedTimeframe != 'Today') {
      return const Text('******',
          style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600, ),
          maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final status = (worker['status'] ?? '').toString();
    final textColor = switch (status) {
      'Present' => _kGreenPresent,
      'Absent' => _kRedAbsent,
      'Leave' => _kOrangeLeave,
      _ => Colors.grey,
    };

    return Text(
      status.isEmpty ? '-' : status.toLowerCase().tr(),
      style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600, ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _tableHeader(String title) {
    return Text(title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF000000), ));
  }
}

class WorkerAttendancePreviewCard extends StatefulWidget {
  final AttendanceRecord record;
  final int totalWorkingDays;
  final int presents;
  final int absents;
  final int leaves;
  final double percentage;
  final List<Map<String, dynamic>> workerRecords;
  final String period;

  const WorkerAttendancePreviewCard({
    super.key,
    required this.record,
    required this.totalWorkingDays,
    required this.presents,
    required this.absents,
    required this.leaves,
    required this.percentage,
    required this.workerRecords,
    required this.period,
  });

  @override
  State<WorkerAttendancePreviewCard> createState() => _WorkerAttendancePreviewCardState();
}

class _WorkerAttendancePreviewCardState extends State<WorkerAttendancePreviewCard> {
  bool _isExporting = false;

  static const Color _primaryBlue = Color(0xFF0A51D0);
  static const Color _lightGreenBg = Color(0xFFE4F9E8);
  static const Color _darkGreen = Color(0xFF00C853);
  static const Color _lightRedBg = Color(0xFFFCE9EA);
  static const Color _darkRed = Color(0xFFF13E5B);
  static const Color _lightOrangeBg = Color(0xFFFEF0E2);
  static const Color _darkOrange = Color(0xFFFF8A00);

  int get _totalRecords => widget.workerRecords.length;
  int get _presents => widget.workerRecords.where((d) => d['status'] == 'Present').length;
  int get _absents => widget.workerRecords.where((d) => d['status'] == 'Absent').length;
  int get _leaves => widget.workerRecords.where((d) => d['status'] == 'Leave').length;
  double get _percentage => _totalRecords > 0 ? (_presents / _totalRecords) * 100 : 0.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 500,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          boxShadow: [BoxShadow(color: const Color(0xFF000000).withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildBlueHeader(context), _buildMiddleSummary(), _buildBottomDetails()],
        ),
      ),
    );
  }

  Widget _buildBlueHeader(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF004FDE),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Color(0xFFFFFFFF), size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text('worker_attendance_preview'.tr(),
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: _isExporting
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                        : SvgPicture.asset('assets/share1.svg', width: 20, height: 20,
                            colorFilter: const ColorFilter.mode(Color(0xFFFFFFFF), BlendMode.srcIn)),
                    onPressed: _isExporting ? null : () => _exportCsv(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          color: const Color(0xFFFFFFFF),
          padding: const EdgeInsets.fromLTRB(32, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WorkerAvatar(
                imageUrl: widget.record.profileImage, name: widget.record.name, size: 60,
                border: Border.all(color: _primaryBlue, width: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.record.name,
                        style: const TextStyle(color: Color(0xFF333333), fontSize: 16, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SvgPicture.asset('assets/email.svg', height: 12, width: 12,
                            colorFilter: const ColorFilter.mode(Color(0xFF666666), BlendMode.srcIn)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(widget.record.email,
                              style: const TextStyle(color: Color(0xFF666666), fontSize: 13, fontWeight: FontWeight.w400),
                              overflow: TextOverflow.ellipsis, maxLines: 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiddleSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 140, child: _buildStatCard('total_presents'.tr(), '$_presents', _lightGreenBg, _darkGreen, _presentIcon)),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: _buildStatCard('total_absent'.tr(), '$_absents', _lightRedBg, _darkRed, _absentIcon)),
          const SizedBox(width: 10),
          SizedBox(width: 140, child: _buildStatCard('total_leaves'.tr(), '$_leaves', _lightOrangeBg, _darkOrange, _leaveIcon)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color bgColor, Color iconColor, Widget Function(Color) iconBuilder) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF000000).withOpacity(0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconBuilder(iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black)),
                Text('days_label'.tr(), style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _presentIcon(Color color) => _statusIcon(color, Icons.check_circle);
  Widget _absentIcon(Color color) => _statusIcon(color, Icons.cancel);
  Widget _leaveIcon(Color color) => _statusIcon(color, Icons.work, smallSize: 10);

  Widget _statusIcon(Color color, IconData badge, {double smallSize = 14}) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(alignment: Alignment.topLeft, child: Icon(Icons.person, color: color, size: 28)),
          Positioned(bottom: 0, right: 0, child: Icon(badge, color: color, size: smallSize)),
        ],
      ),
    );
  }

  Widget _buildBottomDetails() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      child: IntrinsicHeight(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              child: _buildDetailCard(
                title: 'attendance_label'.tr(),
                rows: [
                  _detailRow('total_working_days'.tr(), '$_totalRecords ${_totalRecords == 1 ? 'day_unit'.tr() : 'days_unit'.tr()}', Colors.black),
                  _detailRow('total_presents'.tr(), '$_presents ${_presents == 1 ? 'day_unit'.tr() : 'days_unit'.tr()}', _darkGreen),
                  _detailRow('total_absents'.tr(), '$_absents ${_absents == 1 ? 'day_unit'.tr() : 'days_unit'.tr()}', _darkRed),
                  _detailRow('total_leaves'.tr(), '$_leaves ${_leaves == 1 ? 'day_unit'.tr() : 'days_unit'.tr()}', _darkOrange),
                  _detailRow('attendance_percentage'.tr(), '${_percentage.toStringAsFixed(1)}%', _primaryBlue),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 205,
              child: _buildDetailCard(
                title: 'worker_information'.tr(),
                rows: [
                  _detailRow('position'.tr(), LocalizationHelper.localizePosition(widget.record.role), Colors.black),
                  _detailRow('work_type'.tr(), widget.record.localizedWorkType, Colors.black),
                  _detailRow('attendance_type'.tr(), widget.record.localizedAttendanceType, Colors.black),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard({required String title, required List<Widget> rows}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _primaryBlue)),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.black, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.w500),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await _exportCsvFile(context);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportCsvFile(BuildContext context) async {
    final rows = <List<dynamic>>[];

    rows.add(['worker_attendance_preview'.tr()]);
    rows.add(['${'report_worker'.tr()}: ${widget.record.name}']);
    rows.add(['${'report_email'.tr()}: ${widget.record.email}']);
    rows.add(['${'report_position'.tr()}: ${LocalizationHelper.localizePosition(widget.record.role)}']);
    rows.add([]);
    rows.add(['total_working_days'.tr(), _totalRecords]);
    rows.add(['total_present'.tr(), _presents]);
    rows.add(['total_absent'.tr(), _absents]);
    rows.add(['total_leave'.tr(), _leaves]);
    rows.add(['attendance_percent'.tr(), _percentage.toStringAsFixed(1)]);
    rows.add([]);
    rows.add(['report_date'.tr(), 'report_status'.tr(), 'work_type'.tr(), 'attendance_type'.tr(), 'report_reason_notes'.tr()]);

    final sortedRecords = List<Map<String, dynamic>>.from(widget.workerRecords)
      ..sort((a, b) {
        final aDate = AttendanceReportService.recordDateForRecord(a);
        final bDate = AttendanceReportService.recordDateForRecord(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });

    for (final att in sortedRecords) {
      rows.add([
        AttendanceReportService.csvTextDate(AttendanceReportService.recordDateForRecord(att)),
        att['status'] ?? '-',
        att['workType'] ?? widget.record.workType,
        att['attendanceType'] ?? widget.record.attendanceType,
        att['desc'] ?? att['reason'] ?? '',
      ]);
    }

    final csvString = await compute(_generateCsvString, rows);

    try {
      final fileName =
          '${widget.record.name.replaceAll(' ', '_')}_${widget.period.replaceAll(' ', '_').toLowerCase()}_attendance.csv';
      final csvBytes = Uint8List.fromList(utf8.encode(csvString));

      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'save_attendance_report'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: csvBytes,
      );

      if (outputFile == null) return;
      await File(outputFile).writeAsBytes(csvBytes);

      if (context.mounted) {
        FlashySnackBar.show(context, message: 'attendance_report_saved'.tr(namedArgs: {'file': fileName}));
        await FileOpener.open(outputFile);
      }
    } catch (e) {
      if (context.mounted) {
        FlashySnackBar.show(context, message: 'error_exporting_csv'.tr(namedArgs: {'error': e.toString()}), isError: true);
      }
    }
  }
}