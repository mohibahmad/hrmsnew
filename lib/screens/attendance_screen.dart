import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:easy_localization/easy_localization.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/file_opener.dart';
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/attendance_service.dart';
import '../services/attendance_report_service.dart';
import '../services/time_off_service.dart';
import '../widgets/notification_bell.dart';
import '../widgets/custom_timeframe_dropdown.dart';
import 'workers_attendance_screen.dart';
import '../utils/image_utils.dart';
import '../utils/date_utils.dart';
import '../utils/localization_helper.dart';
import '../utils/snackbar_utils.dart';
import '../utils/guest_restriction.dart';
import 'package:provider/provider.dart';

const Color primaryBlue = Color(0xFF0B51C1);
const Color lightBlueBg = Color(0xFFE8F0FE);
const Color bgGray = Color(0xFFF8FAFC);
const Color textDark = Color(0xFF000000);
const Color textMuted = Color(0xFF64748B);

const Color greenPresent = Color(0xFF00FF2A);
const Color greenPresentBg = Color(0x3300FF2A);
const Color redAbsent = Color(0xFFFF0004);
const Color redAbsentBg = Color(0x33FF0004);
const Color orangeLeave = Color(0xFFFF7B00);
const Color orangeLeaveBg = Color(0x33FF7B00);

class AttendanceRecord {
  final String name;
  final String email;
  final String role;
  final String status;
  final String attendanceType;
  final String workType;
  final String? profileImage;
  final String? phone;

  AttendanceRecord({
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.attendanceType = 'Remote',
    this.workType = 'Full Time',
    this.profileImage,
    this.phone,
  });

  String get localizedWorkType {
    switch (workType) {
      case 'Full Time':
        return 'full_time'.tr();
      case 'Part Time':
        return 'part_time'.tr();
      case 'Contract':
        return 'contract'.tr();
      default:
        return workType;
    }
  }

  String get localizedAttendanceType {
    switch (attendanceType) {
      case 'On-Site':
        return 'on_site'.tr();
      case 'Remote':
        return 'remote'.tr();
      case 'Hybrid':
        return 'hybrid'.tr();
      default:
        return attendanceType;
    }
  }
}

class AttendanceScreen extends StatefulWidget {
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
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late AuthService _authService;
  late FirestoreService _firestore;
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

  int _presentCount = 0;
  int _absentCount = 0;
  int _leaveCount = 0;
  bool _initialized = false;
  StreamSubscription? _attendanceSub;
  StreamSubscription? _workersSub;
  StreamSubscription? _timeOffSub;
  Timer? _searchDebounce;
  List<Map<String, dynamic>>? _cachedFiltered;
  String _filterCacheKey = '';

  String _selectedSharePeriod = 'Today';
  final LayerLink _shareDropdownLink = LayerLink();
  final GlobalKey _shareButtonKey = GlobalKey();
  OverlayEntry? _shareDropdownOverlay;
  bool _isShareDropdownOpen = false;

  static const List<String> _sharePeriodOptions = [
    'Today',
    'Weekly',
    'Monthly',
    '6 Monthly',
    'Yearly',
    'Custom',
  ];

  String _localizeSharePeriod(String period) {
    switch (period) {
      case 'Today':
        return 'today'.tr();
      case 'Weekly':
        return 'weekly'.tr();
      case 'Monthly':
        return 'monthly'.tr();
      case '6 Monthly':
        return '6_month'.tr();
      case 'Yearly':
        return 'yearly'.tr();
      case 'Custom':
        return 'custom'.tr();
      default:
        return period;
    }
  }

  Future<void> _showCustomDateRangePicker() async {
    DateTime calendarDate = DateTime.now();
    final selectedDates = <DateTime>{};
    DateTime? rangeStart;
    DateTime? dragStartDate;
    final dragPreviewDates = <DateTime>{};
    final gridKey = GlobalKey();

    DateTime? _getDateFromPosition(Offset globalPosition) {
      final RenderBox? gridBox =
          gridKey.currentContext?.findRenderObject() as RenderBox?;
      if (gridBox == null) return null;

      final localPosition = gridBox.globalToLocal(globalPosition);

      final gridWidth = gridBox.size.width;
      final cellWidth = (gridWidth - 6 * 8) / 7;
      final cellHeight = cellWidth;

      final col = (localPosition.dx / (cellWidth + 8)).floor();
      final row = (localPosition.dy / (cellHeight + 8)).floor();

      if (col < 0 || col > 6 || row < 0 || row > 5) return null;

      final cellIndex = row * 7 + col;
      int firstWeekday = DateTime(
        calendarDate.year,
        calendarDate.month,
        1,
      ).weekday;
      int startOffset = firstWeekday == 7 ? 0 : firstWeekday;
      int day = cellIndex - startOffset + 1;
      int daysInMonth = DateTime(
        calendarDate.year,
        calendarDate.month + 1,
        0,
      ).day;

      if (day < 1 || day > daysInMonth) return null;
      return DateTime(calendarDate.year, calendarDate.month, day);
    }

    void updateDragPreview(DateTime endDate) {
      if (dragStartDate == null) return;
      dragPreviewDates.clear();
      final start = dragStartDate!.isBefore(endDate) ? dragStartDate! : endDate;
      final end = dragStartDate!.isAfter(endDate) ? dragStartDate! : endDate;
      for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        dragPreviewDates.add(d);
      }
    }

    final result = await showDialog<List<DateTime>?>(
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
                              icon: const Icon(
                                Icons.close,
                                color: Colors.black,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                          Center(
                            child: Text(
                              'Select Dates',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF000000),
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0247C4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: selectedDates.isEmpty
                                  ? null
                                  : () {
                                      final sortedDates = selectedDates.toList()
                                        ..sort();
                                      Navigator.of(context).pop(sortedDates);
                                    },
                              child: Text(
                                'Generate (${selectedDates.length})',
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onPanStart: (details) {
                        final date = _getDateFromPosition(
                          details.globalPosition,
                        );
                        if (date != null) {
                          setModalState(() {
                            dragStartDate = date;
                            dragPreviewDates.clear();
                            dragPreviewDates.add(date);
                          });
                        }
                      },
                      onPanUpdate: (details) {
                        if (dragStartDate != null) {
                          final date = _getDateFromPosition(
                            details.globalPosition,
                          );
                          if (date != null) {
                            setModalState(() {
                              updateDragPreview(date);
                            });
                          }
                        }
                      },
                      onPanEnd: (details) {
                        if (dragStartDate != null &&
                            dragPreviewDates.isNotEmpty) {
                          setModalState(() {
                            selectedDates.addAll(dragPreviewDates);
                            dragStartDate = null;
                            dragPreviewDates.clear();
                          });
                        }
                      },
                      child: _buildCalendarWithWeekdays(
                        calendarDate,
                        selectedDates,
                        (DateTime date) {
                          setModalState(() {
                            final isAlreadySelected = selectedDates.any(
                              (d) =>
                                  d.year == date.year &&
                                  d.month == date.month &&
                                  d.day == date.day,
                            );
                            if (isAlreadySelected) {
                              selectedDates.removeWhere(
                                (d) =>
                                    d.year == date.year &&
                                    d.month == date.month &&
                                    d.day == date.day,
                              );
                              rangeStart = null;
                            } else {
                              if (rangeStart == null) {
                                rangeStart = date;
                                selectedDates.add(date);
                              } else {
                                final start = rangeStart!.isBefore(date)
                                    ? rangeStart!
                                    : date;
                                final end = rangeStart!.isAfter(date)
                                    ? rangeStart!
                                    : date;
                                for (
                                  var d = start;
                                  !d.isAfter(end);
                                  d = d.add(const Duration(days: 1))
                                ) {
                                  selectedDates.add(d);
                                }
                                rangeStart = null;
                              }
                            }
                          });
                        },
                        (DateTime newDate) {
                          setModalState(() {
                            calendarDate = newDate;
                          });
                        },
                        gridKey: gridKey,
                        dragPreviewDates: dragPreviewDates,
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
      await _generateAndShareAttendance(
        'Custom',
        startDate: result.first,
        endDate: result.last,
      );
    }
  }

  void _showShareDropdown() {
    if (!mounted || _shareDropdownOverlay != null) return;

    final buttonContext = _shareButtonKey.currentContext;
    final buttonRenderObject = buttonContext?.findRenderObject();
    final overlayState = Overlay.maybeOf(context);
    if (buttonRenderObject is! RenderBox ||
        !buttonRenderObject.attached ||
        overlayState == null) {
      return;
    }

    final RenderBox buttonRenderBox = buttonRenderObject;
    final size = buttonRenderBox.size;

    _shareDropdownOverlay = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          GestureDetector(
            onTap: _dismissShareDropdown,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.transparent,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Positioned(
            width: size.width,
            child: CompositedTransformFollower(
              link: _shareDropdownLink,
              showWhenUnlinked: false,
              offset: Offset(0, 50),
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
                      final isCustom = option == 'Custom';
                      return GestureDetector(
                        onTap: () {
                          if (isCustom) {
                            _dismissShareDropdown();
                            _showCustomDateRangePicker();
                          } else {
                            _dismissShareDropdown();
                            setState(() => _selectedSharePeriod = option);
                            _generateAndShareAttendance(option);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          color: Colors.transparent,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF0247C4)
                                        : Colors.grey.shade400,
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
                                    color: isSelected
                                        ? const Color(0xFF0247C4)
                                        : Colors.grey.shade400,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: 'SF Pro Display',
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

  Widget _buildCalendarWithWeekdays(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
    ValueChanged<DateTime> onDaySelected,
    ValueChanged<DateTime> onMonthChanged, {
    GlobalKey? gridKey,
    Set<DateTime>? dragPreviewDates,
  }) {
    String monthYearStr =
        '${DateFormat('MMMM', context.locale.toString()).format(calendarDate).toUpperCase()} ${calendarDate.year}';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month - 1, 1),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_left, size: 20, color: Colors.black),
              ),
            ),
            Text(
              monthYearStr,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Pro Display',
              ),
            ),
            GestureDetector(
              onTap: () {
                onMonthChanged(
                  DateTime(calendarDate.year, calendarDate.month + 1, 1),
                );
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, size: 20, color: Colors.black),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildWeekdayLabel('Sun', const Color(0xFFFF0004)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Mon', const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Tue', const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Wed', const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Thu', const Color(0xFF0247C4)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Fri', const Color(0xFF4AC000)),
            const SizedBox(width: 8),
            _buildWeekdayLabel('Sat', const Color(0xFF0247C4)),
          ],
        ),
        const SizedBox(height: 12),
        _buildDaysGridForRange(
          calendarDate,
          selectedDates,
          onDaySelected,
          gridKey: gridKey,
          dragPreviewDates: dragPreviewDates,
        ),
      ],
    );
  }

  Widget _buildWeekdayLabel(String day, Color color) {
    return Expanded(
      child: Container(
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          day.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ),
    );
  }

  Widget _buildDaysGridForRange(
    DateTime calendarDate,
    Set<DateTime> selectedDates,
    ValueChanged<DateTime> onDaySelected, {
    GlobalKey? gridKey,
    Set<DateTime>? dragPreviewDates,
  }) {
    int daysInMonth = DateTime(
      calendarDate.year,
      calendarDate.month + 1,
      0,
    ).day;
    int firstWeekday = DateTime(
      calendarDate.year,
      calendarDate.month,
      1,
    ).weekday;
    int startOffset = firstWeekday == 7 ? 0 : firstWeekday;

    int currentDay = 1;
    List<Widget> rows = [];

    for (int i = 0; i < 6; i++) {
      List<Widget> rowChildren = [];
      for (int j = 0; j < 7; j++) {
        int index = i * 7 + j;
        if (index < startOffset) {
          rowChildren.add(_buildDayCell('', false, false, null, null));
        } else if (currentDay <= daysInMonth) {
          final int tapDay = currentDay;
          final date = DateTime(calendarDate.year, calendarDate.month, tapDay);
          final isDragPreview =
              dragPreviewDates != null &&
              dragPreviewDates.any(
                (d) =>
                    d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day,
              );
          final isSelected =
              !isDragPreview &&
              selectedDates.any(
                (d) =>
                    d.year == date.year &&
                    d.month == date.month &&
                    d.day == date.day,
              );
          rowChildren.add(
            _buildDayCell('$currentDay', isSelected, isDragPreview, () {
              onDaySelected(date);
            }, date),
          );
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
    return Column(key: gridKey, children: rows);
  }

  Widget _buildDayCell(
    String day,
    bool isSelected,
    bool isDragPreview,
    VoidCallback? onTap,
    DateTime? date,
  ) {
    if (day.isEmpty) {
      return const Expanded(
        child: AspectRatio(aspectRatio: 1, child: SizedBox()),
      );
    }
    final isSunday = date?.weekday == 7;
    final isFriday = date?.weekday == 5;
    final dayColor = isSunday
        ? const Color(0xFFFF0004)
        : (isFriday ? const Color(0xFF4AC000) : Colors.black);
    final selectedBg = isFriday
        ? const Color(0xFF4AC000)
        : const Color(0xFFFF0004);
    final dragBg = const Color(0xFF0247C4);

    Color bgColor;
    Color borderColor;

    if (isDragPreview) {
      bgColor = dragBg;
      borderColor = dragBg;
    } else if (isSelected) {
      bgColor = selectedBg;
      borderColor = selectedBg;
    } else {
      bgColor = Colors.transparent;
      if (isSunday) {
        borderColor = const Color(0xFFFF0004).withValues(alpha: 0.4);
      } else if (isFriday) {
        borderColor = const Color(0xFF4AC000).withValues(alpha: 0.4);
      } else {
        borderColor = Colors.grey.shade300;
      }
    }

    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border.all(color: borderColor, width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              day,
              style: TextStyle(
                color: (isSelected || isDragPreview)
                    ? const Color(0xFFFFFFFF)
                    : dayColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _removeShareDropdownOverlay() {
    final overlay = _shareDropdownOverlay;
    _shareDropdownOverlay = null;
    if (overlay != null && overlay.mounted) {
      overlay.remove();
    }
  }

  void _dismissShareDropdown() {
    _removeShareDropdownOverlay();
    if (mounted && _isShareDropdownOpen) {
      setState(() => _isShareDropdownOpen = false);
    }
  }

  String _formatAttendanceDate(DateTime date) =>
      AttendanceReportService.csvDate(date);

  void _appendWorkerAttendanceRows(
    List<List<dynamic>> rows,
    Map<String, dynamic> worker,
    WorkerAttendanceSnapshot snapshot,
  ) {
    final firstRecord = snapshot.records.isEmpty
        ? const <String, dynamic>{}
        : snapshot.records.first;
    final name = (worker['name'] ?? worker['workerName'] ?? 'Worker')
        .toString();
    final email = (worker['email'] ?? '').toString();
    final phone = (worker['phone'] ?? worker['contact'] ?? '').toString();
    final position =
        (worker['position'] ?? worker['role'] ?? firstRecord['role'] ?? '')
            .toString();
    final workType =
        (worker['type1'] ??
                worker['workType'] ??
                firstRecord['workType'] ??
                'Full Time')
            .toString();
    final attendanceType =
        (worker['type2'] ??
                worker['attendanceType'] ??
                firstRecord['attendanceType'] ??
                'On-Site')
            .toString();

    rows.add(['Worker Attendance Summary']);
    rows.add(['Name', name]);
    rows.add(['Email', email]);
    rows.add(['Phone', phone]);
    rows.add(['Position', position]);
    rows.add(['Work Type', workType]);
    rows.add(['Attendance Type', attendanceType]);
    rows.add(['Total Working Days', snapshot.totalWorkingDays]);
    rows.add(['Total Presents', snapshot.presents]);
    rows.add(['Total Absents', snapshot.absents]);
    rows.add(['Total Leaves', snapshot.leaves]);
    rows.add([
      'Attendance Percentage',
      '${snapshot.percentage.toStringAsFixed(1)}%',
    ]);
    rows.add([]);
    rows.add(['Daily Attendance Logs']);
    rows.add([
      'Date',
      'Status',
      'Work Model',
      'Attendance Type',
      'Reason/Notes',
    ]);

    if (snapshot.records.isEmpty) {
      rows.add(['', 'No Record', workType, attendanceType, '']);
    } else {
      for (final record in snapshot.records) {
        final date = AttendanceReportService.recordDateForRecord(record);
        rows.add([
          AttendanceReportService.csvDate(date),
          record['status'] ?? '-',
          record['workType'] ?? workType,
          record['attendanceType'] ?? attendanceType,
          record['desc'] ?? record['reason'] ?? '-',
        ]);
      }
    }
    rows.add([]);
  }

  Future<void> _generateAndShareAttendance(
    String period, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      late final AttendanceDateRange range;
      if (period == 'Custom') {
        if (startDate == null || endDate == null) {
          FlashySnackBar.show(
            context,
            message: 'Please select a date range',
            isError: true,
          );
          return;
        }
        range = AttendanceDateRange(
          start: DateTime(startDate.year, startDate.month, startDate.day),
          end: DateTime(endDate.year, endDate.month, endDate.day),
        );
      } else {
        range = AttendanceReportService.rangeForPeriod(period);
      }

      final rows = <List<dynamic>>[];
      rows.add(['All Workers Attendance Report']);
      rows.add(['Period', _localizeSharePeriod(period)]);
      rows.add([
        'Date Range',
        '${_formatAttendanceDate(range.start)} to ${_formatAttendanceDate(range.end)}',
      ]);
      rows.add([]);

      for (final worker in _workersList) {
        final snapshot = AttendanceReportService.snapshotForWorker(
          worker: worker,
          attendanceRecords: _rawAttendanceDocs,
          timeOffRecords: _timeOffRecords,
          range: range,
        );
        _appendWorkerAttendanceRows(rows, worker, snapshot);
      }

      final csvString = '\ufeff${const CsvEncoder().convert(rows)}';
      final csvBytes = Uint8List.fromList(utf8.encode(csvString));

      final fileName =
          'attendance_${period.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.csv';

      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'save_attendance_report'.tr(),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: csvBytes,
      );

      if (outputFile == null) return;

      final file = File(outputFile);
      await file.writeAsBytes(csvBytes);

      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'attendance_report_saved'.tr(namedArgs: {'file': fileName}),
        );
        await FileOpener.open(outputFile);
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_generating_report'.tr(namedArgs: {'error': '$e'}),
          isError: true,
        );
      }
    }
  }

  @override
  void deactivate() {
    // Remove the route-owned overlay while its OverlayState is still active.
    _removeShareDropdownOverlay();
    _isShareDropdownOpen = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _removeShareDropdownOverlay();
    _attendanceSub?.cancel();
    _workersSub?.cancel();
    _timeOffSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _attendancePreviewNotifier?.dispose();
    super.dispose();
  }

  void _combineAttendance() {
    _cachedFiltered = null;
    _filterCacheKey = '';

    final periodAttendance = _rawAttendanceDocs
        .where(
          (record) => AppDateUtils.isAttendanceRecordWithinPeriod(
            record,
            _selectedTimeframe,
          ),
        )
        .toList();
    periodAttendance.sort((a, b) {
      final aDate = AppDateUtils.attendanceRecordDate(a);
      final bDate = AppDateUtils.attendanceRecordDate(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final byDate = bDate.compareTo(aDate);
      if (byDate != 0) return byDate;
      return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
    });
    _attendanceDocs =
        AttendanceService.combineAttendance(
          workersList: _workersList,
          rawAttendanceDocs: periodAttendance,
        ).map((record) {
          final isOnLeave = TimeOffService.isWorkerOnLeave(
            record,
            _timeOffRecords,
          );
          if (isOnLeave) {
            return {...record, 'status': 'Leave'};
          }
          return record;
        }).toList();

    if (_workersLoaded && _attendanceLoaded) {
      _isLoading = false;
    }

    int present = 0;
    int absent = 0;
    int leave = 0;

    if (_selectedTimeframe == 'Today') {
      // Today: count from collapsed list (one entry per worker)
      for (final record in _attendanceDocs) {
        final status = record['status'];
        if (status == 'Present') {
          present++;
        } else if (status == 'Absent') {
          absent++;
        } else if (status == 'Leave') {
          leave++;
        }
      }
    } else {
      // Week/Month/6 Month/Yearly: count ALL individual day records
      for (final record in periodAttendance) {
        final status = (record['status'] ?? '').toString();
        if (status == 'Present') {
          present++;
        } else if (status == 'Absent') {
          absent++;
        } else if (status == 'Leave') {
          leave++;
        }
      }
    }

    _presentCount = present;
    _absentCount = absent;
    _leaveCount = leave;
  }

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
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest) {
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _workersList = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _workersLoaded = true;
              _combineAttendance();
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _workersLoaded = true;
              _isLoading = false;
            });
          }
        },
      );
      _attendanceSub = _firestore.attendanceStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _rawAttendanceDocs = snapshot.docs
                  .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
                  .toList();
              _attendanceLoaded = true;
              _combineAttendance();
            });
            _refreshAttendancePreview();
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _attendanceLoaded = true;
              _isLoading = false;
            });
          }
        },
      );
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
    } else {
      _workersList = List<Map<String, dynamic>>.from(DummyData.workers);
      _rawAttendanceDocs = List<Map<String, dynamic>>.from(
        DummyData.attendance,
      );
      _timeOffRecords = List<Map<String, dynamic>>.from(DummyData.timeoff);
      _workersLoaded = true;
      _attendanceLoaded = true;
      _combineAttendance();
    }
  }

  String _getTimeframeTitle() {
    switch (_selectedTimeframe) {
      case 'Today':
        return 'today_attendance'.tr();
      case 'Week':
        return 'weekly_attendance'.tr();
      case 'Month':
        return 'monthly_attendance'.tr();
      case '6 Month':
        return 'six_month_attendance'.tr();
      case 'Yearly':
        return 'yearly_attendance'.tr();
      default:
        return 'today_attendance'.tr();
    }
  }

  bool _matchesPeriod(Map<String, dynamic> doc) {
    return AppDateUtils.isAttendanceRecordWithinPeriod(doc, _selectedTimeframe);
  }

  List<Map<String, dynamic>> get _filteredRecords {
    final key =
        '${_attendanceDocs.length}_$_searchQuery$_selectedTab$_selectedTimeframe';
    if (_cachedFiltered != null && _filterCacheKey == key) {
      return _cachedFiltered!;
    }
    _filterCacheKey = key;
    final query = _searchQuery.toLowerCase();
    _cachedFiltered = _attendanceDocs.where((doc) {
      if (!_matchesPeriod(doc)) return false;
      if (query.isNotEmpty) {
        final name = (doc['name'] ?? '').toString().toLowerCase();
        final role = (doc['role'] ?? '').toString().toLowerCase();
        if (!name.contains(query) && !role.contains(query)) return false;
      }
      final status = (doc['status'] ?? '').toString();
      if (_selectedTab == 'All') return true;
      if (_selectedTab == 'Present') return status == 'Present';
      if (_selectedTab == 'Absent') return status == 'Absent';
      if (_selectedTab == 'Leaves') return status == 'Leave';
      return false;
    }).toList();
    return _cachedFiltered!;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: bgGray,
      body: Column(
        children: [
          _buildHeader(context),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 40.0,
                vertical: 24.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchAndActionRow(),
                  const SizedBox(height: 24),
                  _buildSummaryCardsRow(),
                  const SizedBox(height: 24),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _getTimeframeTitle(),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textDark,
                                    fontFamily: 'SF Pro Display',
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
                                      _combineAttendance();
                                    });
                                    _refreshAttendancePreview();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (_isLoading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 80),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (filtered.isEmpty)
                              _buildEmptyState()
                            else
                              _buildAttendanceTable(filtered),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
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
                style: TextStyle(
                  color: textDark,
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

  Widget _buildSearchAndActionRow() {
    return Row(
      children: [
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
                    controller: _searchController,
                    onChanged: (val) {
                      _searchQuery = val;
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 250),
                        () {
                          if (mounted) setState(() {});
                        },
                      );
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
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
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
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (isGuest) {
                showGuestRestrictionDialog(context);
                return;
              }
              if (widget.onWorkersAttendanceTap != null) {
                widget.onWorkersAttendanceTap!();
              } else {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (_, __, ___) => WorkersAttendanceScreen(
                      onNotificationTap: widget.onNotificationTap,
                      onProfileTap: widget.onProfileTap,
                    ),
                    transitionsBuilder: (_, __, ___, child) => child,
                    transitionDuration: Duration.zero,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Text(
              'workers_attendance'.tr(),
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 15,
                fontWeight: FontWeight.w500,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        CompositedTransformTarget(
          link: _shareDropdownLink,
          child: GestureDetector(
            key: _shareButtonKey,
            onTap: () {
              final isGuest = _authService.currentUser?.isAnonymous ?? false;
              if (isGuest) {
                showGuestRestrictionDialog(context);
                return;
              }
              if (_isShareDropdownOpen) {
                _dismissShareDropdown();
              } else {
                _showShareDropdown();
              }
            },
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: primaryBlue,
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
                        fontFamily: 'SF Pro Display',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: Color(0xFFFFFFFF),
                    size: 30,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCardsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            title: 'total_workers'.tr(),
            count: "${_workersList.length}",
            iconAsset: 'assets/total_workers.svg',
            countColor: const Color(0xFF0247C4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'Present'.tr(),
            count: "$_presentCount",
            iconAsset: 'assets/present_worker.svg',
            countColor: const Color(0xFF00FF2A),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'Absent'.tr(),
            count: "$_absentCount",
            iconAsset: 'assets/absent.svg',
            countColor: const Color(0xFFFF0004),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSummaryCard(
            title: 'On leave'.tr(),
            count: "$_leaveCount",
            iconAsset: 'assets/leave.svg',
            countColor: const Color(0xFFFF7B00),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String count,
    required String iconAsset,
    required Color countColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF000000).withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textDark,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 12),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: countColor,
                    fontFamily: 'SF Pro Display',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
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
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTab('All', 'all_tab'.tr()),
            _buildTab('Present', 'present_tab'.tr()),
            _buildTab('Absent', 'absent_tab'.tr()),
            _buildTab('Leaves', 'leaves_tab'.tr()),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String filterKey, String displayLabel) {
    final bool isActive = _selectedTab == filterKey;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = filterKey;
            _cachedFiltered = null;
            _filterCacheKey = '';
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isActive ? 8 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isActive ? primaryBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            displayLabel,
            style: TextStyle(
              color: isActive ? Color(0xFFFFFFFF) : textDark,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
              fontFamily: 'SF Pro Display',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    double dynamicHeight = MediaQuery.of(context).size.height - 520;
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
              isSearchEmpty
                  ? 'no_search_results'.tr()
                  : 'no_attendance_records'.tr(),
              style: TextStyle(
                color: Color(0xFF0247C4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'SF Pro Display',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterWorkerRecords(
    Map<String, dynamic> doc,
    List<Map<String, dynamic>> rawDocs,
    List<Map<String, dynamic>> timeOffRecords, {
    String? periodOverride,
  }) {
    return AttendanceReportService.recordsForWorker(
      worker: doc,
      attendanceRecords: rawDocs,
      timeOffRecords: timeOffRecords,
      range: AttendanceReportService.rangeForPeriod(
        periodOverride ?? _selectedTimeframe,
      ),
    );
  }

  void _showAttendancePreview(BuildContext context, Map<String, dynamic> doc) {
    // Always show the current calendar month's attendance in the preview card
    // so users can see complete monthly stats regardless of screen timeframe.
    const previewPeriod = 'Month';
    final filteredRecordsNotifier = ValueNotifier<List<Map<String, dynamic>>>(
      _filterWorkerRecords(
        doc,
        _rawAttendanceDocs,
        _timeOffRecords,
        periodOverride: previewPeriod,
      ),
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
      barrierColor: const Color(0xFF0247C4).withValues(alpha: 0.5),
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: filteredRecordsNotifier,
          builder: (context, filteredRecords, _) {
            int totalWorkingDays = filteredRecords.length;
            int absents = filteredRecords
                .where((d) => d['status'] == 'Absent')
                .length;
            int leaves = filteredRecords
                .where((d) => d['status'] == 'Leave')
                .length;
            int presents = filteredRecords
                .where((d) => d['status'] == 'Present')
                .length;
            double percentage = totalWorkingDays > 0
                ? (presents / totalWorkingDays) * 100
                : 0.0;
            return WorkerAttendancePreviewCard(
              record: record,
              totalWorkingDays: totalWorkingDays,
              presents: presents,
              absents: absents,
              leaves: leaves,
              percentage: percentage,
              workerRecords: filteredRecords,
              period: previewPeriod,
            );
          },
        ),
      ),
    );

    _attendancePreviewNotifier = filteredRecordsNotifier;
    _attendancePreviewWorkerDoc = doc;
  }

  ValueNotifier<List<Map<String, dynamic>>>? _attendancePreviewNotifier;
  Map<String, dynamic>? _attendancePreviewWorkerDoc;

  void _refreshAttendancePreview() {
    final notifier = _attendancePreviewNotifier;
    final workerDoc = _attendancePreviewWorkerDoc;
    if (notifier != null && workerDoc != null) {
      notifier.value = _filterWorkerRecords(
        workerDoc,
        _rawAttendanceDocs,
        _timeOffRecords,
        periodOverride: 'Month',
      );
    }
  }

  Widget _buildAttendanceTable(List<Map<String, dynamic>> records) {
    final double tableHeight = (MediaQuery.of(context).size.height - 465).clamp(
      480.0,
      1200.0,
    );

    return Container(
      height: tableHeight,
      decoration: BoxDecoration(
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
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
                    child: _tableHeader('worker_name_header'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('status_header'.tr()),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: _tableHeader('work_type'.tr()),
                  ),
                ),
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
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = records[index];
                final name = (doc['name'] ?? '').toString();
                final email = (doc['email'] ?? '').toString();
                final role = (doc['role'] ?? '').toString();
                (doc['status'] ?? '').toString();
                final workType = (doc['workType'] ?? 'Full Time').toString();

                final localizeWorkType = LocalizationHelper.localizeWorkType;

                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _showAttendancePreview(context, doc),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6F8FA),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24.0),
                              child: Row(
                                children: [
                                  WorkerAvatar(
                                    imageUrl: doc['profileImage']?.toString(),
                                    name: name,
                                    size: 40,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: textDark,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          email,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Colors.black,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24.0),
                              child: _buildStatusText(doc),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 24.0),
                              child: Text(
                                localizeWorkType(workType),
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: textDark,
                                  fontFamily: 'SF Pro Display',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              role,
                              style: const TextStyle(
                                fontSize: 15,
                                color: textDark,
                                fontFamily: 'SF Pro Display',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () =>
                                    _showAttendancePreview(context, doc),
                                child: const Icon(
                                  Icons.visibility,
                                  color: Colors.black,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusText(Map<String, dynamic> worker) {
    final status = (worker['status'] ?? '').toString();

    // Today shows the worker's current attendance status.
    if (_selectedTimeframe == 'Today') {
      Color textColor;
      if (status == 'Present') {
        textColor = greenPresent;
      } else if (status == 'Absent') {
        textColor = redAbsent;
      } else if (status == 'Leave') {
        textColor = orangeLeave;
      } else {
        textColor = Colors.grey;
      }

      return Text(
        status.isEmpty ? '-' : status.toLowerCase().tr(),
        style: TextStyle(
          color: textColor,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'SF Pro Display',
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Week, Month, 6 Month and Yearly show masked status
    return const Text(
      '*****',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E293B),
        letterSpacing: 4,
        fontFamily: 'SF Pro Display',
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
    );
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
  State<WorkerAttendancePreviewCard> createState() =>
      _WorkerAttendancePreviewCardState();
}

class _WorkerAttendancePreviewCardState
    extends State<WorkerAttendancePreviewCard> {
  int get _totalRecords => widget.workerRecords.length;
  int get _presents =>
      widget.workerRecords.where((d) => d['status'] == 'Present').length;
  int get _absents =>
      widget.workerRecords.where((d) => d['status'] == 'Absent').length;
  int get _leaves =>
      widget.workerRecords.where((d) => d['status'] == 'Leave').length;
  double get _percentage =>
      _totalRecords > 0 ? (_presents / _totalRecords) * 100 : 0.0;

  static const Color primaryBlue = Color(0xFF0A51D0);

  static const Color lightGreenBg = Color(0xFFE4F9E8);
  static const Color darkGreen = Color(0xFF00C853);

  static const Color lightRedBg = Color(0xFFFCE9EA);
  static const Color darkRed = Color(0xFFFF1717);

  static const Color lightOrangeBg = Color(0xFFFEF0E2);
  static const Color darkOrange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 500,
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
            _buildBlueHeader(context),
            _buildMiddleSummary(),
            _buildBottomDetails(),
          ],
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
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFFFFFFFF),
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              Text(
                'worker_attendance_preview'.tr(),
                style: TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    icon: SvgPicture.asset(
                      'assets/share1.svg',
                      width: 20,
                      height: 20,
                      colorFilter: const ColorFilter.mode(
                        Color(0xFFFFFFFF),
                        BlendMode.srcIn,
                      ),
                    ),
                    onPressed: () => _exportCsv(context),
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
                imageUrl: widget.record.profileImage,
                name: widget.record.name,
                size: 60,
                border: Border.all(color: const Color(0xFF0A51D0), width: 2),
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.record.name,
                      style: const TextStyle(
                        color: Color(0xFF333333),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SvgPicture.asset(
                          'assets/email.svg',
                          height: 12,
                          width: 12,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF666666),
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.record.email,
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
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
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_presents'.tr(),
              value: '$_presents',
              bgColor: lightGreenBg,
              iconColor: darkGreen,
              iconBuilder: (color) => _buildPresentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_absent'.tr(),
              value: '$_absents',
              bgColor: lightRedBg,
              iconColor: darkRed,
              iconBuilder: (color) => _buildAbsentIcon(color),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: _buildSummaryCard(
              title: 'total_leaves'.tr(),
              value: '$_leaves',
              bgColor: lightOrangeBg,
              iconColor: darkOrange,
              iconBuilder: (color) => _buildLeaveIcon(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color bgColor,
    required Color iconColor,
    required Widget Function(Color) iconBuilder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Color(0xFF000000).withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconBuilder(iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                Text(
                  'days_label'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Icon(Icons.check_circle, color: color, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAbsentIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Icon(Icons.cancel, color: color, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveIcon(Color color) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Icon(Icons.person, color: color, size: 28),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Icon(Icons.work, color: color, size: 10),
          ),
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
                  _buildDetailRow(
                    'total_working_days'.tr(),
                    '$_totalRecords ${'days_unit'.tr()}',
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'total_presents'.tr(),
                    '$_presents ${'days_unit'.tr()}',
                    darkGreen,
                  ),
                  _buildDetailRow(
                    'total_absents'.tr(),
                    '$_absents ${'days_unit'.tr()}',
                    darkRed,
                  ),
                  _buildDetailRow(
                    'total_leaves'.tr(),
                    '$_leaves ${'days_unit'.tr()}',
                    darkOrange,
                  ),
                  _buildDetailRow(
                    'attendance_percentage'.tr(),
                    '${_percentage.toStringAsFixed(1)}%',
                    primaryBlue,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 205,
              child: _buildDetailCard(
                title: 'worker_information'.tr(),
                rows: [
                  _buildDetailRow(
                    'position'.tr(),
                    widget.record.role,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'work_type'.tr(),
                    widget.record.localizedWorkType,
                    Color(0xFF000000),
                  ),
                  _buildDetailRow(
                    'attendance_type'.tr(),
                    widget.record.localizedAttendanceType,
                    Color(0xFF000000),
                  ),
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
        color: Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: primaryBlue,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final List<List<dynamic>> rows = [];

    rows.add(['Worker Attendance Summary']);
    rows.add(['Name', widget.record.name]);
    rows.add(['Email', widget.record.email]);
    rows.add(['Position', widget.record.role]);
    rows.add(['Work Type', widget.record.workType]);
    rows.add(['Attendance Type', widget.record.attendanceType]);
    rows.add(['Period', CustomTimeframeDropdown.localizePeriod(widget.period)]);
    rows.add([]);
    rows.add(['Total Working Days', '$_totalRecords ${'days_unit'.tr()}']);
    rows.add(['Total Presents', '$_presents ${'days_unit'.tr()}']);
    rows.add(['Total Absents', '$_absents ${'days_unit'.tr()}']);
    rows.add(['Total Leaves', '$_leaves ${'days_unit'.tr()}']);
    rows.add(['Attendance Percentage', '${_percentage.toStringAsFixed(1)}%']);
    rows.add([]);

    rows.add(['Daily Attendance Logs']);
    rows.add([
      'Date',
      'Status',
      'Work Model',
      'Attendance Type',
      'Reason/Notes',
    ]);

    final sortedRecords = List<Map<String, dynamic>>.from(widget.workerRecords);
    sortedRecords.sort((a, b) {
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

    for (var att in sortedRecords) {
      final dateStr = AttendanceReportService.csvDate(
        AttendanceReportService.recordDateForRecord(att),
      );
      final status = att['status'] ?? '-';
      final model = att['workType'] ?? '-';
      final type = att['attendanceType'] ?? '-';
      final notes = att['desc'] ?? att['reason'] ?? '-';
      rows.add([dateStr, status, model, type, notes]);
    }

    final csvString = '\ufeff${const CsvEncoder().convert(rows)}';

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
        FlashySnackBar.show(
          context,
          message: 'attendance_report_saved'.tr(namedArgs: {'file': fileName}),
        );
        await FileOpener.open(outputFile);
      }
    } catch (e) {
      if (context.mounted) {
        FlashySnackBar.show(
          context,
          message: 'error_exporting_csv'.tr(namedArgs: {'error': e.toString()}),
          isError: true,
        );
      }
    }
  }
}
