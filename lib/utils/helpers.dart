import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'utils.dart';

const int _maxCacheBytes = 50 * 1024 * 1024;
int _currentCacheBytes = 0;
final _base64Cache = <String, Uint8List>{};
final _cacheKeys = <String>[];

void _cleanCacheIfNeeded(int neededBytes) {
  while (_currentCacheBytes + neededBytes > _maxCacheBytes &&
      _cacheKeys.isNotEmpty) {
    final oldest = _cacheKeys.removeAt(0);
    final removed = _base64Cache.remove(oldest);
    if (removed != null) _currentCacheBytes -= removed.length;
  }
}

bool isHttpUrl(String value) =>
    value.startsWith('http://') || value.startsWith('https://');

@pragma('vm:entry-point')
Uint8List? _decodeBase64Task(String url) {
  try {
    final base64Content = url.split(',').last;
    return base64Decode(base64Content);
  } catch (_) {
    return null;
  }
}

Uint8List? _getCachedBytes(String url) => _base64Cache[url];

void _cacheBytes(String url, Uint8List bytes) {
  if (_currentCacheBytes + bytes.length > _maxCacheBytes) {
    _cleanCacheIfNeeded(bytes.length);
  }
  _base64Cache[url] = bytes;
  _cacheKeys.add(url);
  _currentCacheBytes += bytes.length;
}

bool _isValidUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  if (lower.contains('example.com')) return false;
  return url.startsWith('http') ||
      url.startsWith('data:image/') ||
      url.startsWith('/') ||
      url.startsWith('file://') ||
      url.startsWith('assets/');
}

bool _fileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}
String mimeTypeForExtension(String fileName, {String fallback = ''}) {
  final ext = fileName.contains('.')
      ? fileName.split('.').last.toLowerCase()
      : '';
  return switch (ext) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'bmp' => 'image/bmp',
    'webp' => 'image/webp',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => fallback.trim().isEmpty
        ? 'application/octet-stream'
        : fallback.trim().toLowerCase(),
  };
}
@pragma('vm:entry-point')
Uint8List compressImageBytes(
  Uint8List bytes, {
  int maxWidth = 1200,
  int quality = 80,
}) {
  if (bytes.length <= 350 * 1024) {
    return bytes;
  }
  img.Image? image = img.decodeImage(bytes);
  if (image == null) return bytes;
  if (image.width > maxWidth) {
    image = img.copyResize(image, width: maxWidth);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
@pragma('vm:entry-point')
List<Uint8List> compressImagesTask(List<Uint8List> images) {
  return [for (final bytes in images) compressImageBytes(bytes)];
}

String _workerInitial(String? name) {
  final trimmed = (name ?? '').trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

class WorkerAvatar extends StatefulWidget {
  final String? imageUrl;
  final String? name;
  final double size;
  final BoxShape shape;
  final BorderRadiusGeometry? borderRadius;
  final BoxBorder? border;

  const WorkerAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 40,
    this.shape = BoxShape.circle,
    this.borderRadius,
    this.border,
  });

  @override
  State<WorkerAvatar> createState() => _WorkerAvatarState();
}

class _WorkerAvatarState extends State<WorkerAvatar> {
  ImageProvider? _image;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant WorkerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      _resolveImage();
    }
  }

  Future<void> _resolveImage() async {
    final url = widget.imageUrl;
    if (!_isValidUrl(url)) {
      if (mounted) setState(() => _image = null);
      return;
    }

    if (url!.startsWith('data:image/')) {
      final cached = _getCachedBytes(url);
      if (cached != null) {
        if (mounted) setState(() => _image = MemoryImage(cached));
        return;
      }
      if (!_loading) {
        _loading = true;
        final bytes = await compute(_decodeBase64Task, url);
        _loading = false;
        if (bytes != null) {
          _cacheBytes(url, bytes);
        }
        if (mounted) {
          setState(() {
            _image = bytes == null ? null : MemoryImage(bytes);
          });
        }
      }
      return;
    }

    if (url.startsWith('http')) {
      if (mounted) setState(() => _image = CachedNetworkImageProvider(url));
      return;
    }
    if (url.startsWith('assets/')) {
      if (mounted) setState(() => _image = AssetImage(url));
      return;
    }
    if (_fileExists(url)) {
      if (mounted) setState(() => _image = FileImage(File(url)));
      return;
    }
    if (mounted) setState(() => _image = null);
  }

  @override
  Widget build(BuildContext context) {
    final initial = _workerInitial(widget.name);
    const backgroundColors = [
      Color(0xFFE0EAFF),
      Color(0xFFDCFCE7),
      Color(0xFFFCE7F3),
      Color(0xFFFFEDD5),
    ];
    const foregroundColors = [
      Color(0xFF1D4ED8),
      Color(0xFF047857),
      Color(0xFFBE185D),
      Color(0xFFC2410C),
    ];
    final colorIndex = initial.codeUnitAt(0) % backgroundColors.length;

    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColors[colorIndex],
        shape: widget.shape,
        borderRadius: widget.shape == BoxShape.rectangle
            ? widget.borderRadius
            : null,
        border: widget.border,
        image: _image == null
            ? null
            : DecorationImage(image: _image!, fit: BoxFit.cover),
      ),
      child: _image == null
          ? Text(
              initial,
              style: TextStyle(
                color: foregroundColors[colorIndex],
                fontSize: widget.size * 0.4,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

final PdfColor _hrStampColor = PdfColor.fromHex('#0B2A6F');
const String defaultHrStampAssetPath = 'assets/default_hr_stamp.png';

Future<Uint8List?> loadDefaultHrStampBytes() async {
  try {
    final data = await rootBundle.load(defaultHrStampAssetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}

void _drawHrStampStar(
  PdfGraphics canvas,
  double centerX,
  double centerY,
  double size,
  PdfColor color,
) {
  final outerRadius = size;
  final innerRadius = size * 0.42;
  canvas.setFillColor(color);
  for (var index = 0; index < 10; index++) {
    final r = index.isEven ? outerRadius : innerRadius;
    final angle = (index * math.pi / 5) - (math.pi / 2);
    final x = centerX + r * math.cos(angle);
    final y = centerY + r * math.sin(angle);
    if (index == 0) {
      canvas.moveTo(x, y);
    } else {
      canvas.lineTo(x, y);
    }
  }
  canvas
    ..closePath()
    ..fillPath();
}

pw.Widget _buildDefaultHrStamp() {
  return pw.CustomPaint(
    size: const PdfPoint(66, 66),
    painter: (canvas, size) {
      final centerX = size.x / 2;
      final centerY = size.y / 2;
      final radius = size.x / 2;
      final color = _hrStampColor;

      canvas.setStrokeColor(color);
      canvas.setFillColor(color);

      canvas
        ..setLineWidth(radius * 0.009)
        ..drawEllipse(centerX, centerY, radius * 0.95, radius * 0.95)
        ..strokePath()
        ..setLineWidth(radius * 0.022)
        ..drawEllipse(centerX, centerY, radius * 0.92, radius * 0.92)
        ..strokePath()
        ..setLineWidth(radius * 0.018)
        ..drawEllipse(centerX, centerY, radius * 0.59, radius * 0.59)
        ..strokePath();

      _drawHrStampStar(
        canvas,
        centerX - radius * 0.76,
        centerY,
        radius * 0.065,
        color,
      );
      _drawHrStampStar(
        canvas,
        centerX + radius * 0.76,
        centerY,
        radius * 0.065,
        color,
      );
    },
    child: pw.Container(
      width: 66,
      height: 66,
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            'HR',
            style: pw.TextStyle(
              color: _hrStampColor,
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'HUMAN RESOURCES',
            style: pw.TextStyle(
              color: _hrStampColor,
              fontSize: 3.5,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    ),
  );
}

pw.Widget buildCompanyAuthorization({
  required String companyName,
  required String companyId,
  pw.MemoryImage? stampImage,
  required PdfColor accentColor,
  required PdfColor mutedColor,
  String authorizedSignatoryText = 'Authorized Signatory',
  String companyIdLabel = '',
  String? generatedOnText,
  double width = 150,
}) {
  final cleanName = companyName.trim().isEmpty ? 'HRMS' : companyName.trim();

  return pw.Container(
    margin: const pw.EdgeInsets.only(right: 32),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.SizedBox(
          width: 60,
          height: 60,
          child: stampImage != null
              ? pw.Image(stampImage, fit: pw.BoxFit.contain)
              : _buildDefaultHrStamp(),
        ),
        pw.SizedBox(height: 6),

        pw.Text(
          cleanName,
          style: pw.TextStyle(
            color: accentColor,
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),

        pw.Container(width: 60, height: 0.6, color: accentColor),
        pw.SizedBox(height: 3),
        pw.Text(
          authorizedSignatoryText,
          style: pw.TextStyle(color: mutedColor, fontSize: 6.5),
        ),
        if (companyId.trim().isNotEmpty)
          pw.Text(
            '${companyIdLabel.isNotEmpty ? '$companyIdLabel ' : ''}${companyId.trim()}',
            style: pw.TextStyle(color: mutedColor, fontSize: 6),
          ),
        if (generatedOnText != null && generatedOnText.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            generatedOnText,
            style: pw.TextStyle(
              fontSize: 6.5,
              color: PdfColor.fromHex('#9CA3AF'),
            ),
          ),
        ],
      ],
    ),
  );
}

String cleanUploadedDocumentFileName(
  String rawName, {
  String fallback = 'document',
}) {
  if (rawName.trim().isEmpty) return fallback;

  var name = rawName.trim().split('?').first;
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  if (name.contains('/')) {
    name = name.split('/').last;
  }

  name = name.trim().replaceFirst(RegExp(r'^\d+_\d+_'), '');
  return name.isNotEmpty ? name : fallback;
}

class FileOpener {
  static Future<void> open(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final result = await OpenFile.open(filePath);




      if (result.type == ResultType.error ||
          result.type == ResultType.fileNotFound) {
        await _revealInFileManager(file);
      }
    } catch (_) {
      try {
        await _revealInFileManager(File(filePath));
      } catch (_) {}
    }
  }


  static Future<void> _revealInFileManager(File file) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.parent.path]);
    }
  }
}
class LeaveBalanceHelper {
  static const Map<String, String> availKeyForType = {
    'Sick Leave': 'availableSickLeaves',
    'Casual Leave': 'availableCasualLeaves',
    'Annual Leave': 'availableAnnualLeaves',
    'Medical Leave': 'availableMedicalLeaves',
  };

  static const Map<String, String> configKeyForType = {
    'Sick Leave': 'sickLeaves',
    'Casual Leave': 'casualLeaves',
    'Annual Leave': 'annualLeaves',
    'Medical Leave': 'medicalLeaves',
  };

  static int _toInt(dynamic v) => int.tryParse(v?.toString() ?? '0') ?? 0;

  static String leaveDaysText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '';
    final parsed = num.tryParse(text);
    if (parsed == null) return text;
    return parsed.toInt().toString();
  }

  static int remainingForType(Map<String, dynamic> worker, String leaveType) {
    final availKey = availKeyForType[leaveType];
    if (availKey != null) {
      final raw = worker[availKey];
      if (raw != null) {
        final parsed = int.tryParse(raw.toString());
        if (parsed != null) return parsed.clamp(0, 999999);
      }
    }
    final configKey = configKeyForType[leaveType];
    if (configKey != null) return _toInt(worker[configKey]);
    return 0;
  }

}
class LocalizationHelper {
  LocalizationHelper._();

  static const List<String> defaultJobPositions = [
    'Designer',
    'Developer',
    'Software Engineer',
    'Sales',
    'HR',
    'Finance',
    'Marketing',
    'Operations',
    'IT Support',
    'Product',
    'Research',
  ];
  static const List<String> englishMonthNames = [
    '',
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> englishWeekdayNames = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static const Map<int, String> weekdayKeys = {
    DateTime.monday: 'weekday_monday',
    DateTime.tuesday: 'weekday_tuesday',
    DateTime.wednesday: 'weekday_wednesday',
    DateTime.thursday: 'weekday_thursday',
    DateTime.friday: 'weekday_friday',
    DateTime.saturday: 'weekday_saturday',
    DateTime.sunday: 'weekday_sunday',
  };

  static String localizeWeekday(String day) {
    switch (day) {
      case 'Monday':
        return 'weekday_monday'.tr();
      case 'Tuesday':
        return 'weekday_tuesday'.tr();
      case 'Wednesday':
        return 'weekday_wednesday'.tr();
      case 'Thursday':
        return 'weekday_thursday'.tr();
      case 'Friday':
        return 'weekday_friday'.tr();
      case 'Saturday':
        return 'weekday_saturday'.tr();
      case 'Sunday':
        return 'weekday_sunday'.tr();
      default:
        return day;
    }
  }

  static String localizedMonth(int month) {
    switch (month) {
      case 1:  return 'month_january'.tr();
      case 2:  return 'month_february'.tr();
      case 3:  return 'month_march'.tr();
      case 4:  return 'month_april'.tr();
      case 5:  return 'month_may'.tr();
      case 6:  return 'month_june'.tr();
      case 7:  return 'month_july'.tr();
      case 8:  return 'month_august'.tr();
      case 9:  return 'month_september'.tr();
      case 10: return 'month_october'.tr();
      case 11: return 'month_november'.tr();
      case 12: return 'month_december'.tr();
      default: return '';
    }
  }

  static String localizeGender(String value) {
    switch (value) {
      case 'Male':
        return 'male'.tr();
      case 'Female':
        return 'female'.tr();
      case 'Other':
      case 'Others':
        return 'other'.tr();
      default:
        return value;
    }
  }

  static String localizeType1(String value) {
    switch (value) {
      case 'Full-Time':
      case 'full_time':
      case 'Full Time':
      case 'employee':
        return 'full_time'.tr();
      case 'Part-Time':
      case 'part_time':
      case 'Part Time':
        return 'part_time'.tr();
      case 'Contract':
      case 'contract':
        return 'contract'.tr();
      case 'Freelance':
      case 'freelance':
        return 'freelance'.tr();
      default:
        return value;
    }
  }

  static String localizeType2(String value) {
    switch (value) {
      case 'On-Site':
      case 'on_site':
        return 'on_site'.tr();
      case 'Remote':
      case 'remote':
        return 'remote'.tr();
      case 'Hybrid':
      case 'hybrid':
        return 'hybrid'.tr();
      default:
        return value;
    }
  }

  static String localizeExperience(String value) {
    switch (value) {
      case 'Fresher':
      case 'fresher':
        return 'fresher'.tr();
      case 'Junior':
      case 'junior':
        return 'junior'.tr();
      case 'Mid-Level':
      case 'mid_level':
      case 'Mid Level':
        return 'mid_level'.tr();
      case 'Senior':
      case 'senior':
        return 'senior'.tr();
      default:
        return value;
    }
  }

  static String localizeRelationshipStatus(String value) {
    switch (value) {
      case 'Single':
      case 'single':
        return 'single'.tr();
      case 'Married':
      case 'married':
        return 'married'.tr();
      default:
        return value;
    }
  }

  static const Map<String, String> _compoundRoleKeys = {
    'backend developer': 'backend_developer',
    'backend engineer': 'backend_engineer',
    'business analyst': 'business_analyst',
    'cloud architect': 'cloud_architect',
    'content strategist': 'content_strategist',
    'content writer': 'content_writer',
    'cyber security analyst': 'cyber_security_analyst',
    'data analyst': 'data_analyst',
    'data engineer': 'data_engineer',
    'devops engineer': 'devops_engineer',
    'devops lead': 'devops_lead',
    'event coordinator': 'event_coordinator',
    'finance analyst': 'finance_analyst',
    'frontend developer': 'frontend_developer',
    'graphic designer': 'graphic_designer',
    'hr manager': 'hr_manager',
    'it support specialist': 'it_support_specialist',
    'junior developer': 'junior_developer',
    'junior qa tester': 'junior_qa_tester',
    'marketing lead': 'marketing_lead',
    'mobile developer': 'mobile_developer',
    'office manager': 'office_manager',
    'operations manager': 'operations_manager',
    'product manager': 'product_manager',
    'qa engineer': 'qa_engineer',
    'sales executive': 'sales_executive',
    'senior web developer': 'senior_web_developer',
    'social media manager': 'social_media_manager',
    'solutions architect': 'solutions_architect',
    'system administrator': 'system_administrator',
    'technical writer': 'technical_writer',
    'ui designer': 'ui_designer',
    'ux researcher': 'ux_researcher',
  };

  static String localizePosition(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    switch (normalized) {
      case 'designer':
        return 'designer'.tr();
      case 'developer':
        return 'developer'.tr();
      case 'engineering':
        return 'engineering'.tr();
      case 'sales':
        return 'sales'.tr();
      case 'hr':
      case 'human resources':
        return 'hr'.tr();
      case 'finance':
        return 'finance'.tr();
      case 'management':
        return 'management'.tr();
      case 'manager':
        return 'manager'.tr();
      case 'accountant':
        return 'accountant'.tr();
      case 'assistant':
        return 'assistant'.tr();
      case 'director':
        return 'director'.tr();
      case 'lead':
        return 'lead'.tr();
      case 'engineer':
        return 'engineer'.tr();
      case 'analyst':
        return 'analyst'.tr();
      case 'coordinator':
        return 'coordinator'.tr();
      case 'consultant':
        return 'consultant'.tr();
      case 'officer':
        return 'officer'.tr();
      case 'specialist':
        return 'specialist'.tr();
      case 'administrator':
        return 'administrator'.tr();
      case 'researcher':
        return 'researcher'.tr();
      case 'writer':
        return 'writer'.tr();
      case 'tester':
        return 'tester'.tr();
      case 'strategist':
        return 'strategist'.tr();
      case 'architect':
        return 'architect'.tr();
      case 'marketing':
        return 'marketing'.tr();
      case 'operations':
        return 'operations'.tr();
      case 'it support':
        return 'it_support'.tr();
      case 'software engineer':
        return 'software_engineer'.tr();
      case 'quality assurance':
        return 'quality_assurance'.tr();
      case 'product':
        return 'product'.tr();
      case 'research':
        return 'research'.tr();
      case 'legal':
        return 'legal'.tr();
      default:
        final compoundKey = _compoundRoleKeys[normalized];
        if (compoundKey != null) return compoundKey.tr();
        return _localizeCompoundPosition(value.trim());
    }
  }

  static String _localizeCompoundPosition(String value) {
    if (value.isEmpty) return value;
    final words = value.split(' ');
    final parts = words.map((w) {
      if (w.isEmpty) return w;
      final lower = w.toLowerCase();
      if (_jobRoleAcronyms.contains(lower)) return lower.toUpperCase();
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return parts.join(' ');
  }

  static const Set<String> _jobRoleAcronyms = {
    'hr',
    'it',
    'qa',
    'ui',
    'ux',
    'ceo',
    'cto',
    'cfo',
    'coo',
  };

  static String localizeEducation(String value) {
    switch (value) {
      case 'Matric':
      case 'matric':
        return 'matric'.tr();
      case 'Intermediate':
      case 'intermediate':
        return 'intermediate'.tr();
      case 'Bachelor':
      case 'Bachelors':
      case 'bachelor':
      case 'bachelors':
        return 'bachelor'.tr();
      case 'Master':
      case 'master':
        return 'master'.tr();
      case 'Other':
      case 'other':
        return 'other'.tr();
      default:
        return value;
    }
  }

  static String localizeSalaryType(String value) {
    switch (value) {
      case 'Monthly':
      case 'monthly':
      case 'fixed':
        return 'monthly'.tr();
      case 'Hourly':
      case 'hourly':
        return 'hourly'.tr();
      case 'Contract':
      case 'contract':
        return 'contract'.tr();
      default:
        return value;
    }
  }

  static String localizeCurrency(String value) {
    switch (CurrencyUtils.normalize(value)) {
      case 'USD':
        return 'usd_desc'.tr();
      case 'EUR':
        return 'eur_desc'.tr();
      case 'GBP':
        return 'gbp_desc'.tr();
      case 'JPY':
        return 'jpy_desc'.tr();
      case 'INR':
        return 'inr_desc'.tr();
      case 'PKR':
        return 'pkr_desc'.tr();
      case 'RUB':
        return 'rub_desc'.tr();
      case 'BRL':
        return 'brl_desc'.tr();
      case 'SAR':
        return 'sar_desc'.tr();
      case 'AED':
        return 'aed_desc'.tr();
      case 'CAD':
        return 'cad_desc'.tr();
      case 'AUD':
        return 'aud_desc'.tr();
      case 'QAR':
        return 'qar_desc'.tr();
      case 'KWD':
        return 'kwd_desc'.tr();
      case 'OMR':
        return 'omr_desc'.tr();
      default:
        return value;
    }
  }

  static String localizeExpenseCategory(String value) {
    switch (value.trim().toLowerCase()) {
      case 'salary':
        return 'expense_cat_salary'.tr();
      case 'stationery':
        return 'expense_cat_stationery'.tr();
      case 'food & beverage':
      case 'food_and_beverage':
        return 'expense_cat_food_beverage'.tr();
      case 'software & it':
      case 'software_and_it':
        return 'expense_cat_software_it'.tr();
      case 'rent':
        return 'expense_cat_rent'.tr();
      case 'entertainment':
        return 'expense_cat_entertainment'.tr();
      case 'training & development':
      case 'training_and_development':
        return 'expense_cat_training_development'.tr();
      case 'utilities':
        return 'expense_cat_utilities'.tr();
      case 'furniture':
        return 'expense_cat_furniture'.tr();
      case 'professional services':
      case 'professional_services':
        return 'expense_cat_professional_services'.tr();
      default:
        return value;
    }
  }

  static String localizeLeaveType(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      '_',
    );
    switch (normalized) {
      case 'casual_leave':
      case 'casual':
        return 'leave_casual'.tr();
      case 'sick_leave':
      case 'sick':
        return 'leave_sick'.tr();
      case 'medical_leave':
      case 'medical':
        return 'leave_medical'.tr();
      case 'annual_leave':
      case 'annual':
        return 'leave_annual'.tr();
      case 'maternity_leave':
      case 'maternity':
        return 'leave_maternity'.tr();
      case 'paternity_leave':
      case 'paternity':
        return 'leave_paternity'.tr();
      case 'unpaid_leave':
      case 'unpaid':
        return 'leave_unpaid'.tr();
      case 'emergency_leave':
      case 'emergency':
        return 'leave_emergency'.tr();
      case 'study_leave':
      case 'study':
        return 'leave_study'.tr();
      case 'hajj_leave':
      case 'hajj':
        return 'leave_hajj'.tr();
      default:
        return value;
    }
  }

  static String localizeBiometricName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'face id':
        return 'biometric_face_id'.tr();
      case 'touch id':
        return 'biometric_touch_id'.tr();
      case 'fingerprint':
        return 'biometric_fingerprint'.tr();
      case 'iris':
        return 'biometric_iris'.tr();
      default:
        return 'biometric_generic'.tr();
    }
  }

  static String localizeHolidayName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    switch (normalized) {
      case 'new_years_day':
        return 'holiday_name_new_years_day'.tr();
      case 'martin_luther_king_jr_day':
        return 'holiday_name_mlk_day'.tr();
      case 'valentines_day':
        return 'holiday_name_valentines_day'.tr();
      case 'presidents_day':
        return 'holiday_name_presidents_day'.tr();
      case 'spring_equinox':
        return 'holiday_name_spring_equinox'.tr();
      case 'easter_sunday':
        return 'holiday_name_easter_sunday'.tr();
      case 'earth_day':
        return 'holiday_name_earth_day'.tr();
      case 'memorial_day':
        return 'holiday_name_memorial_day'.tr();
      case 'juneteenth':
        return 'holiday_name_juneteenth'.tr();
      case 'independence_day':
        return 'holiday_name_independence_day'.tr();
      case 'national_intern_day':
        return 'holiday_name_national_intern_day'.tr();
      case 'international_cat_day':
        return 'holiday_name_international_cat_day'.tr();
      case 'summer_picnic':
        return 'holiday_name_summer_picnic'.tr();
      case 'world_photography_day':
        return 'holiday_name_world_photography_day'.tr();
      case 'womens_equality_day':
        return 'holiday_name_womens_equality_day'.tr();
      case 'labor_day':
        return 'holiday_name_labor_day'.tr();
      case 'patriot_day':
        return 'holiday_name_patriot_day'.tr();
      case 'international_day_of_peace':
        return 'holiday_name_international_day_of_peace'.tr();
      case 'world_teachers_day':
        return 'holiday_name_world_teachers_day'.tr();
      case 'columbus_day':
        return 'holiday_name_columbus_day'.tr();
      case 'united_nations_day':
        return 'holiday_name_united_nations_day'.tr();
      case 'halloween':
        return 'holiday_name_halloween'.tr();
      case 'veterans_day':
        return 'holiday_name_veterans_day'.tr();
      case 'world_kindness_day':
        return 'holiday_name_world_kindness_day'.tr();
      case 'thanksgiving_day':
        return 'holiday_name_thanksgiving_day'.tr();
      case 'black_friday':
        return 'holiday_name_black_friday'.tr();
      case 'human_rights_day':
        return 'holiday_name_human_rights_day'.tr();
      case 'winter_solstice':
        return 'holiday_name_winter_solstice'.tr();
      case 'christmas_eve':
        return 'holiday_name_christmas_eve'.tr();
      case 'christmas_day':
        return 'holiday_name_christmas_day'.tr();
      case 'boxing_day':
        return 'holiday_name_boxing_day'.tr();
      case 'new_years_eve':
        return 'holiday_name_new_years_eve'.tr();
      default:
        return value;
    }
  }
}
class ValidationException implements Exception {
  final String message;
  final String? field;

  const ValidationException(this.message, {this.field});

  @override
  String toString() => field == null
      ? 'ValidationException: $message'
      : 'ValidationException($field): $message';
}

class Validators {
  Validators._();

  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?"
    r"(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$",
  );

  static bool isValidPhone(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;

    if (RegExp(r'[^\d+\-\s()]').hasMatch(trimmed)) return false;
    final digits = trimmed.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return false;
    if (digits.split('').every((d) => d == digits[0])) return false;
    return true;
  }

  static bool isValidEmail(String? value) {
    if (value == null) return false;
    return _email.hasMatch(value.trim());
  }

  static const Set<String> placeholderEmailDomains = {'example.com'};

  static bool isPlaceholderEmailDomain(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    final atIndex = trimmed.lastIndexOf('@');
    if (atIndex < 0 || atIndex == trimmed.length - 1) return false;
    final domain = trimmed.substring(atIndex + 1).toLowerCase();
    return placeholderEmailDomains.contains(domain);
  }

  static bool hasWhitespace(String? value) {
    if (value == null) return false;
    return value.contains(RegExp(r'\s'));
  }

  static String titleCase(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return trimmed;
    final cleaned = trimmed.replaceAll(RegExp(r'[\._\-]'), ' ');
    return cleaned
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          if (word.length > 1 && word == word.toUpperCase()) {
            return word;
          }
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

            static String nameFromEmail(String? email) {
    final value = email?.trim() ?? '';
    final atIndex = value.indexOf('@');
    if (atIndex <= 0) return '';
    return titleCase(value.substring(0, atIndex));
  }

  static bool isAtLeast18(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age >= 18;
  }

  static String capitalizeFirst(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return trimmed;
    return trimmed[0].toUpperCase() + trimmed.substring(1).toLowerCase();
  }

  static final RegExp _companyId = RegExp(r'^[A-Z0-9-]+$');
  static final RegExp _nationalIdSeparators = RegExp(r'[\s-]');

  static bool isValidCompanyId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    return _companyId.hasMatch(trimmed);
  }

  static String? companyId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!isValidCompanyId(trimmed)) return 'invalid_company_id_format'.tr();
    return null;
  }

  static bool isValidNationalId(String? value) {
    final cleaned = (value ?? '').replaceAll(_nationalIdSeparators, '');
    if (cleaned.isEmpty || cleaned.length < 6) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleaned);
  }

  static String? email(String? value, {bool required = false}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return required ? 'email_is_required'.tr() : null;
    if (!isValidEmail(trimmed)) return 'enter_valid_email'.tr();

    if (isPlaceholderEmailDomain(trimmed)) return 'enter_valid_email'.tr();
    return null;
  }

  static double? parseAmount(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final cleaned = raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  static String _readStringField(Map<String, dynamic> record, String key) =>
      (record[key] ?? '').toString().trim();

  static void validateWorker(Map<String, dynamic> worker) {
    if (_readStringField(worker, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    final emailErr = email(worker['email']?.toString());
    if (emailErr != null) {
      throw ValidationException(emailErr, field: 'email');
    }

    final dobValue = worker['dob'];
    final dobText = (dobValue?.toString() ?? '').trim();
    if (dobText.isNotEmpty) {
      final dob = AppDateUtils.dateFromValue(dobValue);
      if (dob == null) {
        throw ValidationException(
          '${'date_of_birth'.tr()}: ${'invalid_date_format'.tr()}',
          field: 'dob',
        );
      }
      if (!isAtLeast18(dob)) {
        throw ValidationException('worker_must_be_18'.tr(), field: 'dob');
      }
    }

    final gender = _readStringField(worker, 'gender').toLowerCase();
    if (gender.isNotEmpty &&
        gender != 'male' &&
        gender != 'female' &&
        gender != 'other' &&
        gender != 'others') {
      throw ValidationException('invalid_gender_value'.tr(), field: 'gender');
    }

    final currency = _readStringField(worker, 'currency');
    if (currency.isNotEmpty && !CurrencyUtils.isSupported(currency)) {
      throw ValidationException(
        'invalid_currency_value'.tr(),
        field: 'currency',
      );
    }

    final salary = parseAmount(worker['salaryAmount']);
    if (salary == null || !salary.isFinite || salary <= 0) {
      throw ValidationException(
        'please_enter_salary_amount'.tr(),
        field: 'salaryAmount',
      );
    }
  }

  static void validateExpense(Map<String, dynamic> expense) {
    if (_readStringField(expense, 'name').isEmpty) {
      throw ValidationException('expense_name_required'.tr(), field: 'name');
    }
    if (_readStringField(expense, 'category').isEmpty) {
      throw ValidationException(
        'expense_category_required'.tr(),
        field: 'category',
      );
    }
    final amount = parseAmount(expense['amount']);
    if (amount == null) {
      throw ValidationException('valid_amount_required'.tr(), field: 'amount');
    }
    if (amount <= 0) {
      throw ValidationException(
        'amount_must_be_positive'.tr(),
        field: 'amount',
      );
    }
    if (amount > 999999999) {
      throw ValidationException(
        'amount_cannot_exceed_max'.tr(),
        field: 'amount',
      );
    }
  }

  static void validateAttendance(Map<String, dynamic> attendance) {
    if (_readStringField(attendance, 'workerId').isEmpty) {
      throw ValidationException('worker_id_required'.tr(), field: 'workerId');
    }
    if (_readStringField(attendance, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_readStringField(attendance, 'status').isEmpty) {
      throw ValidationException('status_required'.tr(), field: 'status');
    }
  }

  static void validatePayroll(Map<String, dynamic> payroll) {
    if (_readStringField(payroll, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_readStringField(payroll, 'status').isEmpty) {
      throw ValidationException(
        'payment_status_required'.tr(),
        field: 'status',
      );
    }
  }

  static void validateTimeOff(Map<String, dynamic> timeOff) {
    if (_readStringField(timeOff, 'workerId').isEmpty) {
      throw ValidationException('worker_id_required'.tr(), field: 'workerId');
    }
    if (_readStringField(timeOff, 'name').isEmpty) {
      throw ValidationException('worker_name_required'.tr(), field: 'name');
    }
    if (_readStringField(timeOff, 'action').isEmpty) {
      throw ValidationException('leave_type_required'.tr(), field: 'action');
    }
    if (_readStringField(timeOff, 'startDate').isEmpty) {
      throw ValidationException('start_date_required'.tr(), field: 'startDate');
    }
    if (_readStringField(timeOff, 'endDate').isEmpty) {
      throw ValidationException('end_date_required'.tr(), field: 'endDate');
    }
  }

  static void validateAsset(Map<String, dynamic> asset) {
    if (_readStringField(asset, 'name').isEmpty) {
      throw ValidationException('name_required'.tr(), field: 'name');
    }
    if (_readStringField(asset, 'type').isEmpty) {
      throw ValidationException('asset_type_required'.tr(), field: 'type');
    }
  }

  static void validateHoliday(Map<String, dynamic> holiday) {
    if (_readStringField(holiday, 'name').isEmpty) {
      throw ValidationException('holiday_name_required'.tr(), field: 'name');
    }
  }
}
enum DuplicateWorkerField { name, email, nationalId }

class DuplicateWorkerException implements Exception {
  final DuplicateWorkerField field;

  const DuplicateWorkerException(this.field);

  @override
  String toString() => 'DuplicateWorkerException: ${field.name}';
}

class WorkerIdentity {
  WorkerIdentity._();

  static String normalizeName(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');

  static String normalizeEmail(dynamic value) {
    final email = (value ?? '').toString().trim().toLowerCase();

    return email == 'worker@email.com' ? '' : email;
  }

  static String normalizeNationalId(dynamic value) => (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s-]+'), '');

  static DuplicateWorkerField? duplicateField(
    Map<String, dynamic> candidate,
    Iterable<Map<String, dynamic>> existingWorkers, {
    String? excludeId,
  }) {
    final candidateEmail = normalizeEmail(candidate['email']);
    final candidateNationalId = normalizeNationalId(candidate['nationalId']);

    for (final existing in existingWorkers) {
      final existingId = (existing['id'] ?? '').toString();
      if (excludeId != null && existingId == excludeId) continue;

      if (candidateEmail.isNotEmpty &&
          candidateEmail == normalizeEmail(existing['email'])) {
        return DuplicateWorkerField.email;
      }
      if (candidateNationalId.isNotEmpty &&
          candidateNationalId == normalizeNationalId(existing['nationalId'])) {
        return DuplicateWorkerField.nationalId;
      }
    }
    return null;
  }

    static String normalizeId(Map<String, dynamic> value) {
    final workerId = (value['workerId'] ?? '').toString().trim();
    return workerId.isNotEmpty
        ? workerId
        : (value['id'] ?? '').toString().trim();
  }

          static bool recordsMatch(
    Map<String, dynamic> record,
    Map<String, dynamic> worker, {
    bool allowName = true,
  }) {
    final recordWorkerId = (record['workerId'] ?? '').toString().trim();
    final workerId = normalizeId(worker);
    if (recordWorkerId.isNotEmpty) {
      return workerId.isNotEmpty && recordWorkerId == workerId;
    }

    final recordEmail = normalizeEmail(record['email']);
    final workerEmail = normalizeEmail(worker['email']);
    if (recordEmail.isNotEmpty) {
      return workerEmail.isNotEmpty && recordEmail == workerEmail;
    }

    if (!allowName) return false;

    final recordName = normalizeName(record['name'] ?? record['workerName']);
    final workerName = normalizeName(worker['name']);
    return recordName.isNotEmpty && recordName == workerName;
  }

      static bool matchesByIdOrEmail(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final recordWorkerId = (first['workerId'] ?? '').toString().trim();
    final workerId = normalizeId(second);
    if (recordWorkerId.isNotEmpty &&
        workerId.isNotEmpty &&
        recordWorkerId == workerId) {
      return true;
    }

    final recordEmail = normalizeEmail(first['email']);
    final workerEmail = normalizeEmail(second['email']);
    return recordEmail.isNotEmpty &&
        workerEmail.isNotEmpty &&
        recordEmail == workerEmail;
  }

      static bool samePerson(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstId = normalizeId(first);
    final secondId = normalizeId(second);
    if (firstId.isNotEmpty && secondId.isNotEmpty) return firstId == secondId;

    final firstEmail = normalizeEmail(first['email']);
    final secondEmail = normalizeEmail(second['email']);
    return firstEmail.isNotEmpty && firstEmail == secondEmail;
  }

    static Map<String, dynamic>? findMatchingWorker(
    Map<String, dynamic> target,
    Iterable<Map<String, dynamic>> workers,
  ) {
    for (final worker in workers) {
      if (matchesByIdOrEmail(target, worker)) return worker;
    }
    return null;
  }

      static bool recordsMatchByUniqueName(
    Map<String, dynamic> record,
    Map<String, dynamic> worker,
    Iterable<Map<String, dynamic>> candidates,
  ) {
    final recordName = normalizeName(record['name'] ?? record['workerName']);
    final workerName = normalizeName(worker['name']);
    if (recordName.isEmpty || workerName.isEmpty || recordName != workerName) {
      return false;
    }
    return candidates
            .where((candidate) => normalizeName(candidate['name']) == workerName)
            .length ==
        1;
  }
}

ImageProvider resolveImageProvider(String? url, {ImageProvider fallback = const AssetImage('assets/profileimage.png')}) {
  if (url == null || url.isEmpty) return fallback;
  if (url.startsWith('data:image/')) {
    return MemoryImage(base64Decode(url.split(',').last));
  }
  if (url.startsWith('http')) {
    return CachedNetworkImageProvider(url);
  }
  return AssetImage(url);
}
