import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:easy_localization/src/localization.dart' show Localization;

import 'package:easy_localization/src/translations.dart' show Translations;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hrms/riverpod_providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hrms/core/utils/utils.dart';
import 'package:hrms/core/utils/image_loader.dart';
import 'dart:io';
import 'dart:isolate';
import 'package:hrms/services/core/firestore_service.dart';
import 'package:hrms/services/payroll/payroll_service.dart';
import 'package:hrms/services/core/preferences_service.dart';
import 'package:hrms/services/core/dummy_data.dart';
import 'package:hrms/services/payroll/invoice_service.dart';
import 'package:hrms/services/core/error_reporter.dart';
import 'package:hrms/widgets/common/amount_text.dart';
import 'package:hrms/main.dart';

Uint8List _encodePayrollInvoiceZip(List<Map<String, Object>> files) {
  final archive = Archive();
  for (final file in files) {
    final name = file['name']! as String;
    final bytes = file['bytes']! as Uint8List;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive, level: 0);
  if (encoded.isEmpty) throw StateError('ZIP encoding failed');
  return Uint8List.fromList(encoded);
}

String _formatDayCount(num value) {
  final numeric = value.toDouble();
  return numeric == numeric.roundToDouble()
      ? numeric.toStringAsFixed(0)
      : numeric.toStringAsFixed(1);
}

String _invoiceMoney(double amount, String currency) {
  if (!amount.isFinite || amount <= 0) return '0';
  final value = PayrollService.formatFullNumber(amount);
  return currency.trim().isEmpty ? value : '${currency.trim()} $value';
}

class DialogController {
  FlashySnackBarProgressController? _snackBarController;
  double _progress = 0;
  String _label = '';
  DateTime _lastLabelChangeAt = DateTime.fromMillisecondsSinceEpoch(0);
  BuildContext? _context;
  bool _closed = false;
  bool _userDismissed = false;

  static const Duration minLabelDwell = Duration(milliseconds: 100);

  double get progress => _progress;
  String get label => _label;

  DialogController(
    BuildContext context, {
    double initialProgress = 0,
    String initialLabel = '',
  }) {
    _context = context;
    _progress = initialProgress;
    _label = initialLabel;
    _createSnackBar();
  }

  void _createSnackBar() {
    final ctx = _context;
    if (ctx == null || !ctx.mounted || _closed || _userDismissed) return;
    _snackBarController = FlashySnackBar.showProgress(
      ctx,
      message: _label,
      progress: _progress,
      subtitle: 'creating_payroll_pdfs'.tr(),
      onUserDismiss: () {
        _userDismissed = true;
      },
    );
  }

  void update({
    required double progress,
    required String label,
    bool forceLabel = false,
  }) {
    if (_closed || _userDismissed) return;
    final isCompletion = progress >= 1.0;
    final requestedProgress = progress.clamp(0.0, 1.0);
    // Parallel payroll stages may finish out of order. Keep the visible bar
    // strictly monotonic while still allowing their forced labels to update.
    if (requestedProgress > _progress || isCompletion) {
      _progress = requestedProgress;
    }
    if (label != _label) {
      final elapsed = DateTime.now().difference(_lastLabelChangeAt);
      if (isCompletion || forceLabel || elapsed >= minLabelDwell) {
        _label = label;
        _lastLabelChangeAt = DateTime.now();
      }
    }
    _refreshSnackBar();
  }

  void reset({required double progress, required String label}) {
    if (_closed || _userDismissed) return;
    _progress = progress;
    _label = label;
    _refreshSnackBar();
  }

  void _refreshSnackBar() {
    if (_closed || _userDismissed) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    final existing = _snackBarController;

    if (existing != null) {
      if (existing.isActive) {
        existing.update(progress: _progress, label: _label);
      }
      return;
    }

    _createSnackBar();
  }

  void dismiss() {
    if (_closed) return;
    _closed = true;
    _snackBarController?.dismiss();
    _snackBarController = null;
  }
}

final Map<String, Map<String, dynamic>> _translationsCache = {};

// Scales the invoice PDF batch deadline with worker count so large runs do not
// silently time out. Formula: 30 s base + 100 ms per worker (capped at 300 s).
Duration _pdfBatchTimeout(int workerCount) {
  final extraMs = (workerCount * 100).clamp(0, 270000);
  return const Duration(seconds: 30) + Duration(milliseconds: extraMs);
}

Future<Uint8List?> _loadCompanyImageDeviceFirst({
  required Iterable<String?> localCandidates,
  required String remoteSource,
  required bool isStamp,
}) async {
  final visited = <String>{};
  for (final candidate in localCandidates) {
    final source = (candidate ?? '').trim();
    if (source.isEmpty || !visited.add(source)) continue;

    // 1. Check if it's base64
    if (source.startsWith('data:image/')) {
      final bytes = await ImageLoader.load(
        source: source,
        maxSizeBytes: 5 * 1024 * 1024,
      );
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }

    // 2. Check if it's a remote URL
    final uri = Uri.tryParse(source);
    final isRemote =
        uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https');

    if (isRemote) {
      // Try to load from Cache Manager
      try {
        final cacheManager = DefaultCacheManager();
        final fileInfo = await cacheManager.getFileFromCache(source);
        if (fileInfo != null) {
          final bytes = await fileInfo.file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    } else {
      // 3. It's a local file path candidate
      try {
        final cleanedPath = source.startsWith('file://')
            ? Uri.parse(source).toFilePath()
            : source;
        final file = File(cleanedPath);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }
  }

  // 4. Try remoteSource in cache or local
  final rSource = remoteSource.trim();
  if (rSource.isNotEmpty) {
    final uri = Uri.tryParse(rSource);
    final isRemote =
        uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https');
    if (isRemote) {
      try {
        final cacheManager = DefaultCacheManager();
        final fileInfo = await cacheManager.getFileFromCache(rSource);
        if (fileInfo != null) {
          final bytes = await fileInfo.file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    } else {
      try {
        final file = File(rSource);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }
  }

  // 5. Fallback: download remoteSource and cache it in Cache Manager with 1.5s timeout
  try {
    final bytes =
        await (isStamp
                ? InvoiceService.resolveCompanyStampBytes(remoteSource)
                : InvoiceService.resolveCompanyLogoBytes(remoteSource))
            .timeout(const Duration(milliseconds: 1500), onTimeout: () => null);
    if (bytes != null && bytes.isNotEmpty && rSource.isNotEmpty) {
      final uri = Uri.tryParse(rSource);
      if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
        unawaited(
          DefaultCacheManager()
              .putFile(rSource, bytes)
              .then<void>((_) {})
              .catchError((_) {}),
        );
      }
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

Future<Map<String, dynamic>> _loadLocaleTranslations(
  String languageCode,
) async {
  final cached = _translationsCache[languageCode];
  if (cached != null) return cached;
  try {
    final jsonStr = await rootBundle.loadString(
      'assets/translations/$languageCode.json',
    );
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      _translationsCache[languageCode] = decoded;
      return decoded;
    }
    return const {};
  } catch (_) {
    return const {};
  }
}

void _configurePayrollInvoiceIsolate(Map<String, Object?> sharedAssets) {
  final locale = (sharedAssets['locale'] ?? 'en') as String;
  final translations =
      (sharedAssets['translations'] ?? const <String, dynamic>{})
          as Map<String, dynamic>;
  PdfHelpers.setIsolateTranslations(translations);
  try {
    Localization.load(
      Locale(locale),
      translations: Translations({locale: translations}),
      useFallbackTranslationsForEmptyResources: true,
    );
  } catch (_) {}

  try {
    InvoiceService.warmupCache(
      fontBytes: sharedAssets['fontBytes'] as Uint8List?,
      logoBytes: sharedAssets['companyLogoBytes'] as Uint8List?,
      stampBytes: sharedAssets['companyStampBytes'] as Uint8List?,
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void _payrollInvoiceIsolateMain(List<Object?> bootstrap) {
  final readyPort = bootstrap[0] as SendPort;
  try {
    final sharedAssets = Map<String, Object?>.from(bootstrap[1] as Map);
    _configurePayrollInvoiceIsolate(sharedAssets);

    final commandPort = ReceivePort();
    readyPort.send(commandPort.sendPort);
    commandPort.listen((dynamic rawMessage) async {
      if (rawMessage is! Map) return;
      final message = Map<String, Object?>.from(rawMessage);
      if (message['type'] == 'close') {
        commandPort.close();
        return;
      }

      final replyPort = message['replyPort'] as SendPort?;
      if (replyPort == null) return;
      try {
        final rawArgs = message['args'];
        if (message['type'] != 'generateBatch' || rawArgs is! List) {
          throw StateError('Invalid payroll PDF batch request');
        }
        final files = <Map<String, Object>>[];
        for (final rawWorkerArgs in rawArgs) {
          final workerArgs = Map<String, Object?>.from(rawWorkerArgs as Map);
          final file = await _generatePayrollInvoiceFile(<String, Object?>{
            ...sharedAssets,
            ...workerArgs,
            'invoiceIsolateReady': true,
          });
          final pdfBytes = file['bytes']! as Uint8List;
          final result = <String, Object>{
            ...file,
            'bytes': TransferableTypedData.fromList(<Uint8List>[pdfBytes]),
          };
          files.add(result);
          replyPort.send(const <String, Object?>{'progress': 1});
        }
        replyPort.send(<String, Object?>{'files': files});
      } catch (error) {
        replyPort.send(<String, Object?>{'error': error.toString()});
      }
    });
  } catch (error) {
    try {
      readyPort.send(error.toString());
    } catch (_) {}
  }
}

class _PayrollInvoiceIsolateWorker {
  final Isolate _isolate;
  final SendPort _commandPort;
  final Set<ReceivePort> _pendingResponses = <ReceivePort>{};
  bool _closed = false;

  _PayrollInvoiceIsolateWorker(this._isolate, this._commandPort);

  static Future<_PayrollInvoiceIsolateWorker> spawn(
    Map<String, Object?> sharedAssets,
    int workerNumber,
  ) async {
    final readyPort = ReceivePort();
    try {
      final isolate = await Isolate.spawn<List<Object?>>(
        _payrollInvoiceIsolateMain,
        <Object?>[readyPort.sendPort, sharedAssets],
        debugName: 'payroll-pdf-$workerNumber',
      );
      final received = await readyPort.first.timeout(
        const Duration(seconds: 4),
        onTimeout: () => throw TimeoutException('Payroll PDF isolate startup timed out'),
      );
      if (received is! SendPort) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('Failed to initialize payroll PDF worker: $received');
      }
      return _PayrollInvoiceIsolateWorker(isolate, received);
    } finally {
      readyPort.close();
    }
  }

  Future<List<Map<String, Object>>> generateBatch(
    List<Map<String, Object?>> workerArgs,
    void Function(int completed) onProgress,
  ) async {
    if (_closed || workerArgs.isEmpty) return const <Map<String, Object>>[];
    final responsePort = ReceivePort();
    _pendingResponses.add(responsePort);
    try {
      _commandPort.send(<String, Object?>{
        'type': 'generateBatch',
        'replyPort': responsePort.sendPort,
        'args': workerArgs,
      });
      await for (final rawResponse in responsePort) {
        if (rawResponse is! Map) continue;
        final response = Map<String, Object?>.from(rawResponse);
        final progress = response['progress'];
        if (progress is int && progress > 0) {
          onProgress(progress);
          continue;
        }
        final rawFiles = response['files'];
        if (rawFiles is List) {
          final files = <Map<String, Object>>[];
          for (final rawFile in rawFiles) {
            final file = Map<String, Object>.from(rawFile as Map);
            final transferredBytes = file['bytes'];
            if (transferredBytes is TransferableTypedData) {
              file['bytes'] = transferredBytes.materialize().asUint8List();
            }
            files.add(file);
          }
          return files;
        }
        final error = (response['error'] ?? '').toString();
        if (error.isNotEmpty) throw StateError(error);
      }
      return const <Map<String, Object>>[];
    } finally {
      _pendingResponses.remove(responsePort);
      responsePort.close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _commandPort.send(const <String, Object?>{'type': 'close'});
    for (final port in _pendingResponses.toList()) {
      port.close();
    }
    _pendingResponses.clear();
    _isolate.kill(priority: Isolate.immediate);
  }
}

Future<Map<String, Object>> _generatePayrollInvoiceFile(
  Map<String, Object?> args,
) async {
  final index = args['index']! as int;
  final workerId = (args['workerId'] ?? '') as String;
  final workerName = (args['workerName'] ?? '') as String;
  final email = (args['email'] ?? '') as String;
  final position = (args['position'] ?? '') as String;
  final salary = (args['salary'] ?? '') as String;
  final salaryType = (args['salaryType'] ?? 'Monthly') as String;
  final totalWorkDays = (args['totalWorkDays'] ?? '') as String;
  final absents = args['absents']! as int;
  final halfDays = args['halfDays']! as int;
  final leaves = args['leaves']! as int;
  final paidLeaves = args['paidLeaves']! as int;
  final unpaidLeaves = args['unpaidLeaves']! as int;
  final overtimeAmount = (args['overtimeAmount'] ?? '0') as String;
  final prorationFactor = (args['prorationFactor'] ?? 1.0) as double;
  final absentDeduction = (args['absentDeduction'] ?? '') as String;
  final leaveDeduction = (args['leaveDeduction'] ?? '') as String;
  final customDeduction = (args['customDeduction'] ?? '') as String;
  final currency = (args['currency'] ?? CurrencyUtils.defaultCode) as String;
  final periodDisplay = (args['periodDisplay'] ?? '') as String;
  final payPeriod = (args['payPeriod'] ?? '') as String;
  final fontBytes = args['fontBytes'] as Uint8List?;
  final companyLogoBytes = args['companyLogoBytes'] as Uint8List?;
  final companyStampBytes = args['companyStampBytes'] as Uint8List?;
  final companyName = (args['companyName'] ?? 'HRMS') as String;
  final companyAddress = (args['companyAddress'] ?? '') as String;
  final companyEmail = (args['companyEmail'] ?? '') as String;
  final companyPhone = (args['companyPhone'] ?? '') as String;
  final companyId = (args['companyId'] ?? '') as String;
  final locale = (args['locale'] ?? 'en') as String;
  final translations =
      (args['translations'] ?? const <String, dynamic>{})
          as Map<String, dynamic>;
  final employeeImageBytes = args['employeeImageBytes'] as Uint8List?;

  if (args['invoiceIsolateReady'] != true) {
    PdfHelpers.setIsolateTranslations(translations);
    try {
      Localization.load(
        Locale(locale),
        translations: Translations({locale: translations}),
        useFallbackTranslationsForEmptyResources: true,
      );
    } catch (_) {}
  }

  final enteredSalary = PayrollService.extractSalary(salary);
  final rawSalary = salaryType.trim().toLowerCase() == 'annual'
      ? enteredSalary / 12
      : enteredSalary;
  final workDays = int.tryParse(totalWorkDays) ?? 30;
  final absentEquivalent = absents + (halfDays * 0.5);
  final overtimeAmt = PayrollService.extractSalary(overtimeAmount);

  final grossSalary = rawSalary * prorationFactor;
  final absentDeductionTotal = PayrollService.extractSalary(absentDeduction);
  final leaveDeductionTotal = PayrollService.extractSalary(leaveDeduction);
  final totalDeductions =
      PayrollService.extractSalary(customDeduction) +
      absentDeductionTotal +
      leaveDeductionTotal;
  final netSalary = (grossSalary + overtimeAmt - totalDeductions).clamp(
    0.0,
    double.infinity,
  );
  final currencySymbol = PayrollService.getCurrencySymbol(currency);

  final pdfBytes = await InvoiceService.generatePayrollInvoice(
    employeeName: workerName,
    email: email,
    position: position,
    payPeriod: periodDisplay,
    totalWorkDays: totalWorkDays,
    absents: _formatDayCount(absentEquivalent),
    leaves: leaves.toString(),
    paidLeaves: paidLeaves.toString(),
    unpaidLeaves: unpaidLeaves.toString(),
    overtimeAmount: _invoiceMoney(overtimeAmt, currencySymbol),
    salary: salary,
    dailyRate: _invoiceMoney(
      workDays > 0 ? grossSalary / workDays : 0.0,
      currencySymbol,
    ),
    grossPay: _invoiceMoney(grossSalary, currencySymbol),
    overtimePay: _invoiceMoney(overtimeAmt, currencySymbol),
    absentDeduction: _invoiceMoney(absentDeductionTotal, currencySymbol),
    leaveDeduction: _invoiceMoney(leaveDeductionTotal, currencySymbol),
    totalDeductions: _invoiceMoney(totalDeductions, currencySymbol),
    netSalary: _invoiceMoney(netSalary, currencySymbol),
    currency: currencySymbol,
    companyName: companyName,
    companyAddress: companyAddress,
    companyEmail: companyEmail,
    companyPhone: companyPhone,
    companyId: companyId,
    companyLogoBytes: companyLogoBytes,
    companyStampBytes: companyStampBytes,
    workerId: workerId,
    fontBytes: fontBytes,
    employeeImageBytes: employeeImageBytes,
  );

  final sanitizedName = workerName
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  final safeName = sanitizedName.isNotEmpty
      ? sanitizedName
      : 'worker_${index + 1}';
  return <String, Object>{
    'name': '${safeName}_${index + 1}_invoice_$payPeriod.pdf',
    'bytes': pdfBytes,
    'sortIndex': index,
  };
}

class AutoPayrollResult {
  final String workerId;
  final String workerName;
  final String email;
  String netSalary;
  final bool success;
  final bool isPaid;
  final String? error;
  final int absents;
  final int halfDays;
  final int leaves;
  final int paidLeaves;
  final int unpaidLeaves;
  String absentDeduction;
  String leaveDeduction;
  bool deductionsAreTotals;
  String overtimeAmount;
  String customDeduction;
  double rawNetSalaryValue;
  final String salary;
  final String currency;
  final String totalWorkDays;
  final String position;
  final String employmentType;
  final String salaryType;
  final String? imageUrl;
  double prorationFactor;

  AutoPayrollResult({
    this.workerId = '',
    required this.workerName,
    required this.email,
    required this.netSalary,
    required this.success,
    this.isPaid = false,
    this.error,
    this.absents = 0,
    this.halfDays = 0,
    this.leaves = 0,
    this.paidLeaves = 0,
    this.unpaidLeaves = 0,
    this.absentDeduction = '',
    this.leaveDeduction = '',
    this.deductionsAreTotals = false,
    this.overtimeAmount = '',
    this.customDeduction = '',
    this.rawNetSalaryValue = 0,
    this.salary = '',
    this.currency = CurrencyUtils.defaultCode,
    this.totalWorkDays = '',
    this.position = '',
    this.employmentType = '',
    this.salaryType = 'Monthly',
    this.imageUrl,
    this.prorationFactor = 1.0,
  });

  AutoPayrollResult copy() => AutoPayrollResult(
    workerId: workerId,
    workerName: workerName,
    email: email,
    netSalary: netSalary,
    success: success,
    isPaid: isPaid,
    error: error,
    absents: absents,
    halfDays: halfDays,
    leaves: leaves,
    paidLeaves: paidLeaves,
    unpaidLeaves: unpaidLeaves,
    absentDeduction: absentDeduction,
    leaveDeduction: leaveDeduction,
    deductionsAreTotals: deductionsAreTotals,
    overtimeAmount: overtimeAmount,
    customDeduction: customDeduction,
    rawNetSalaryValue: rawNetSalaryValue,
    salary: salary,
    currency: currency,
    totalWorkDays: totalWorkDays,
    position: position,
    employmentType: employmentType,
    salaryType: salaryType,
    imageUrl: imageUrl,
    prorationFactor: prorationFactor,
  );

  Map<String, dynamic> toCanonicalPayrollRecord({
    required String payrollKey,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime runDate,
  }) {
    final effectiveName = workerName.trim().isNotEmpty
        ? workerName.trim()
        : (email.trim().isNotEmpty ? email.trim() : 'Worker');
    return {
      'workerId': workerId,
      'name': effectiveName,
      'email': email,
      'position': position,
      if (employmentType.trim().isNotEmpty) 'workType': employmentType.trim(),
      if (imageUrl?.trim().isNotEmpty ?? false) 'profileImage': imageUrl,
      'status': 'Paid',
      'totalWorkDays': int.tryParse(totalWorkDays) ?? 0,
      'absents': absents,
      'halfDays': halfDays,
      'paidLeaves': paidLeaves,
      'unpaidLeaves': unpaidLeaves,
      'leaves': leaves,
      'overtimeAmount': PayrollService.extractSalary(overtimeAmount),
      'absentDeduction': PayrollService.extractSalary(absentDeduction),
      'leaveDeduction': PayrollService.extractSalary(leaveDeduction),
      'customDeduction': PayrollService.extractSalary(customDeduction),
      'deductionsAreTotals': true,
      'salary': salary,
      'currency': currency,
      'salaryType': salaryType,
      'netSalary': netSalary,
      'netSalaryAmount': rawNetSalaryValue,
      'netSalaryFormatted': netSalary,
      'prorationFactor': prorationFactor,
      'payrollKey': payrollKey,
      'payPeriod': periodEnd,
      'payPeriodStart': periodStart,
      'payPeriodEnd': periodEnd,
      'dueDate': periodEnd,
      'cancelledAt': null,
      'lastModified': runDate,
      'payrollDate': runDate,
      'paidAt': runDate,
    };
  }
}

class PayrollRunSummary {
  final DateTime runDate;
  final int totalWorkers;
  final int successCount;
  final int failCount;
  final List<AutoPayrollResult> results;
  final String periodLabel;

  PayrollRunSummary({
    required this.runDate,
    required this.totalWorkers,
    required this.successCount,
    required this.failCount,
    required this.results,
    required this.periodLabel,
  });
}

class PayrollRunner {
  static final PayrollRunner _instance = PayrollRunner._();
  factory PayrollRunner() => _instance;
  PayrollRunner._();

  bool _runInProgress = false;

  Future<PayrollRunSummary?> runPayroll(
    BuildContext context, {
    bool autoMode = false,
    DateTime? payrollMonth,
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
    VoidCallback? onBeforeReviewDialog,
  }) async {
    final isGuest =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(authServiceProvider).currentUser?.isAnonymous ??
        false;
    if (isGuest) {
      return _runPayrollInternal(
        context,
        autoMode: autoMode,
        payrollMonth: payrollMonth,
        payPeriodStart: payPeriodStart,
        payPeriodEnd: payPeriodEnd,
        positionFilter: positionFilter,
        onBeforeReviewDialog: onBeforeReviewDialog,
      );
    }
    if (_runInProgress) return null;
    _runInProgress = true;
    try {
      return await _runPayrollInternal(
        context,
        autoMode: autoMode,
        payrollMonth: payrollMonth,
        payPeriodStart: payPeriodStart,
        payPeriodEnd: payPeriodEnd,
        positionFilter: positionFilter,
        onBeforeReviewDialog: onBeforeReviewDialog,
      );
    } finally {
      _runInProgress = false;
    }
  }

  Future<PayrollRunSummary?> _runPayrollInternal(
    BuildContext context, {
    required bool autoMode,
    DateTime? payrollMonth,
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
    VoidCallback? onBeforeReviewDialog,
  }) async {
    final authService = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(authServiceProvider);
    final isGuest = authService.currentUser?.isAnonymous ?? false;
    final firestoreService = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(firestoreServiceProvider);

    List<Map<String, dynamic>> workers = await _loadWorkers(
      context,
      isGuest,
      firestoreService,
    );
    if (workers.isEmpty) return null;

    workers = _filterByPosition(workers, positionFilter);
    if (workers.isEmpty) {
      _showError(context, 'no_workers_found');
      return null;
    }

    final now = DateTime.now();
    final effectivePayrollMonth =
        payrollMonth ?? PayrollService.currentPayrollMonth(referenceDate: now);
    final periodLabel = PayrollService.payrollPeriodLabel(
      effectivePayrollMonth,
    );
    final effectivePeriodStart =
        payPeriodStart ?? PayrollService.payPeriodStart(effectivePayrollMonth);
    final effectivePeriodEnd =
        payPeriodEnd ?? PayrollService.payPeriodEnd(effectivePayrollMonth);

    final data = await _fetchRequiredData(
      context,
      isGuest,
      firestoreService,
      effectivePayrollMonth,
      effectivePeriodStart,
      effectivePeriodEnd,
    );
    if (data == null) return null;

    final (
      companyProfile,
      existingPayroll,
      autoWorkDays,
      preFetchedAttendance,
    ) = data;

    if (autoWorkDays <= 0) {
      _showError(
        context,
        'invalid_working_days',
        namedArgs: {'days': '$autoWorkDays'},
      );
      return null;
    }

    final companyCurrency = CurrencyUtils.normalize(
      companyProfile?['currency'],
    );
    final payrollCheckResult = await _checkExistingPayroll(
      context,
      workers,
      existingPayroll,
      effectivePayrollMonth,
      effectivePeriodStart,
      effectivePeriodEnd,
      companyCurrency,
      isGuest,
    );
    if (payrollCheckResult == null) return null;
    workers = payrollCheckResult;

    final prevPayroll = _buildPrevPayrollMap(
      existingPayroll,
      effectivePayrollMonth,
    );
    final attendanceResults = await _fetchAttendance(
      context,
      isGuest,
      firestoreService,
      workers,
      effectivePayrollMonth,
      effectivePeriodStart,
      effectivePeriodEnd,
      preFetchedAttendance,
    );

    final results = await _calculateResults(
      workers: workers,
      attendanceResults: attendanceResults,
      autoWorkDays: autoWorkDays,
      effectivePeriodStart: effectivePeriodStart,
      effectivePeriodEnd: effectivePeriodEnd,
      companyCurrency: companyCurrency,
      isGuest: isGuest,
      prevPayrollByWorkerId: prevPayroll.$1,
      prevPayrollByEmail: prevPayroll.$2,
    );

    final summary = PayrollRunSummary(
      runDate: now,
      totalWorkers: workers.length,
      successCount: results.where((r) => r.success).length,
      failCount: results.where((r) => !r.success).length,
      results: results,
      periodLabel: periodLabel,
    );

    final preloadedAssetsFuture = _preloadInvoiceAssets(
      companyProfile,
      isGuest,
      firestore: firestoreService,
    );

    final result = await _handleSummaryCommit(
      context,
      summary,
      autoMode,
      isGuest,
      effectivePeriodStart,
      effectivePeriodEnd,
      companyProfile ?? {},
      preloadedAssetsFuture: preloadedAssetsFuture,
      onBeforeReviewDialog: onBeforeReviewDialog,
    );
    return result;
  }

  Future<Map<String, dynamic>?> _preloadInvoiceAssets(
    Map<String, dynamic>? companyProfile,
    bool isGuest, {
    FirestoreService? firestore,
  }) async {
    try {
      final locale = Intl.defaultLocale ?? 'en';
      // The profile screen persists local copies of the company logo/stamp.
      // Resolve those alongside Firestore and prefer them for PDF generation,
      // so Pay All does not download the same company images again.
      final profileSources = await Future.wait<Object?>([
        CompanyProfileHelper.getCompanyProfileWithFirestore(firestore),
        PreferencesService.getProfilePicLocalPath(),
        PreferencesService.getProfilePicUrl(),
        PreferencesService.getCompanyStampUrl(),
      ]);
      final resolved = profileSources[0] as Map<String, dynamic>;
      final localCompanyLogoPath = (profileSources[1] ?? '').toString().trim();
      final cachedCompanyLogo = (profileSources[2] ?? '').toString().trim();
      final cachedCompanyStamp = (profileSources[3] ?? '').toString().trim();
      final remoteCompanyLogo =
          (resolved['profilePicUrl'] ??
                  companyProfile?['profilePic'] ??
                  companyProfile?['profilePicUrl'] ??
                  companyProfile?['photoUrl'] ??
                  companyProfile?['companyLogoUrl'] ??
                  '')
              .toString()
              .trim();
      final remoteCompanyStamp =
          (resolved['companyStampUrl'] ??
                  companyProfile?['companyStampUrl'] ??
                  companyProfile?['stampUrl'] ??
                  companyProfile?['companyStamp'] ??
                  '')
              .toString()
              .trim();
      final results = await Future.wait([
        _loadCompanyImageDeviceFirst(
          localCandidates: [localCompanyLogoPath, cachedCompanyLogo],
          remoteSource: remoteCompanyLogo,
          isStamp: false,
        ),
        _loadCompanyImageDeviceFirst(
          localCandidates: [cachedCompanyStamp],
          remoteSource: remoteCompanyStamp,
          isStamp: true,
        ),
        PdfHelpers.loadFontBytes(),
        _loadLocaleTranslations(locale),
      ]);

      Uint8List? rawLogo = results[0] as Uint8List?;
      Uint8List? rawStamp = results[1] as Uint8List?;

      if (rawLogo == null || rawLogo.isEmpty) {
        try {
          final data = await rootBundle.load('assets/app_icon.png');
          rawLogo = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } catch (_) {}
      }
      if (rawStamp == null || rawStamp.isEmpty) {
        try {
          rawStamp = await loadDefaultHrStampBytes();
        } catch (_) {}
      }

      final logoBytes = rawLogo != null && rawLogo.isNotEmpty
          ? compressImageBytes(rawLogo, maxWidth: 256, quality: 75, force: true)
          : null;
      final stampBytes = rawStamp != null && rawStamp.isNotEmpty
          ? compressImageBytes(
              rawStamp,
              maxWidth: 256,
              quality: 75,
              force: true,
            )
          : null;

      return {
        'logoBytes': logoBytes,
        'stampBytes': stampBytes,
        'fontBytes': results[2],
        'translations': results[3],
        'resolvedProfile': resolved,
      };
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _loadWorkers(
    BuildContext context,
    bool isGuest,
    FirestoreService firestoreService,
  ) async {
    List<Map<String, dynamic>> workers;
    if (isGuest) {
      workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      try {
        final workerSnap = await firestoreService.getWorkersOnce();
        workers = workerSnap.docs
            .map((d) => {...d.data() as Map<String, dynamic>, 'id': d.id})
            .where((w) {
              final name = (w['name'] ?? '').toString().trim();
              final workerId = (w['id'] ?? '').toString().trim();
              final email = (w['email'] ?? '').toString().trim();
              return name.isNotEmpty &&
                  (workerId.isNotEmpty || email.isNotEmpty) &&
                  PayrollService.isWorkerEligibleForPayroll(w);
            })
            .toList();
      } catch (e) {
        _showError(
          context,
          'failed_to_load_worker_data',
          namedArgs: {'error': '$e'},
        );
        return [];
      }
    }
    return workers;
  }

  List<Map<String, dynamic>> _filterByPosition(
    List<Map<String, dynamic>> workers,
    String? positionFilter,
  ) {
    if (positionFilter == null || positionFilter.trim().isEmpty) return workers;
    final filter = positionFilter.trim();
    final filtered = workers.where((worker) {
      final position = (worker['position'] ?? '').toString().trim();
      return position.isNotEmpty &&
          position.toLowerCase().contains(filter.toLowerCase());
    }).toList();
    return filtered;
  }

  Future<
    (
      Map<String, dynamic>?,
      List<Map<String, dynamic>>,
      int,
      List<Map<String, dynamic>>?,
    )?
  >
  _fetchRequiredData(
    BuildContext context,
    bool isGuest,
    FirestoreService firestoreService,
    DateTime effectivePayrollMonth,
    DateTime effectivePeriodStart,
    DateTime effectivePeriodEnd,
  ) async {
    Map<String, dynamic>? companyProfile;
    List<Map<String, dynamic>> existingPayroll = const [];
    int autoWorkDays = 0;
    List<Map<String, dynamic>>? preFetchedAttendance;

    try {
      if (isGuest) {
        companyProfile = await PreferencesService.getGuestProfileData();
        existingPayroll = List<Map<String, dynamic>>.from(DummyData.payroll);
        autoWorkDays = await firestoreService.getMonthlyWorkingDays(
          month: effectivePayrollMonth,
          startDate: effectivePeriodStart,
          endDate: effectivePeriodEnd,
        );
      } else {
        final results = await Future.wait([
          firestoreService.getUserProfile().catchError((e, st) {
            ErrorReporter.report(
              e,
              st,
              context: 'PayrollRunnerCompanyCurrency',
            );
            return <String, dynamic>{};
          }),
          () async {
            try {
              return await firestoreService.getPayrollOnce();
            } catch (error, stackTrace) {
              ErrorReporter.report(
                error,
                stackTrace,
                context: 'PayrollRunnerPayrollOnce',
              );
              return null;
            }
          }(),
          firestoreService
              .getMonthlyWorkingDays(
                month: effectivePayrollMonth,
                startDate: effectivePeriodStart,
                endDate: effectivePeriodEnd,
              )
              .then((v) => {'_days': v}),
          firestoreService
              .getAttendanceForPeriod(effectivePeriodStart, effectivePeriodEnd)
              .then(
                (snapshot) => {
                  '_attendance': snapshot.docs
                      .map(
                        (doc) => {
                          ...doc.data() as Map<String, dynamic>,
                          'id': doc.id,
                        },
                      )
                      .toList(),
                },
              ),
        ]);
        companyProfile = results[0] as Map<String, dynamic>?;
        final payrollResult = results[1] as dynamic;
        final payrollDocs = payrollResult == null
            ? const <dynamic>[]
            : (payrollResult.docs as List<dynamic>);
        existingPayroll = payrollDocs
            .map(
              (doc) => {
                ...doc.data() as Map<String, dynamic>,
                'id': doc.id as String,
              },
            )
            .toList();
        final daysMap = results[2] as Map<String, dynamic>;
        autoWorkDays = (daysMap['_days'] as int?) ?? 0;
        final attendanceMap = results[3] as Map<String, dynamic>;
        preFetchedAttendance =
            (attendanceMap['_attendance'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollRunnerParallelFetch',
      );
      _showError(
        context,
        'error_occurred',
        namedArgs: {'error': error.toString()},
      );
      return null;
    }
    return (
      companyProfile,
      existingPayroll,
      autoWorkDays,
      preFetchedAttendance,
    );
  }

  Future<List<Map<String, dynamic>>?> _checkExistingPayroll(
    BuildContext context,
    List<Map<String, dynamic>> workers,
    List<Map<String, dynamic>> existingPayroll,
    DateTime effectivePayrollMonth,
    DateTime effectivePeriodStart,
    DateTime effectivePeriodEnd,
    String companyCurrency,
    bool isGuest,
  ) async {
    try {
      final payableWorkers = PayrollService.payableWorkersForPeriod(
        workers,
        existingPayroll,
        month: effectivePayrollMonth,
        allowUndatedRecords: isGuest,
        companyCurrency: companyCurrency,
        periodStart: effectivePeriodStart,
        periodEnd: effectivePeriodEnd,
      );
      return payableWorkers;
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollRunnerExistingPayrollCheck',
      );
      _showError(
        context,
        'error_occurred',
        namedArgs: {'error': error.toString()},
      );
      return null;
    }
  }

  (Map<String, Map<String, dynamic>>, Map<String, Map<String, dynamic>>)
  _buildPrevPayrollMap(
    List<Map<String, dynamic>> existingPayroll,
    DateTime effectivePayrollMonth,
  ) {
    final byWorkerId = <String, Map<String, dynamic>>{};
    final byEmail = <String, Map<String, dynamic>>{};
    for (final record in existingPayroll) {
      if (!PayrollService.isRecordInMonth(record, effectivePayrollMonth)) {
        continue;
      }
      final rWorkerId = (record['workerId'] ?? '').toString().trim();
      final rEmail = (record['email'] ?? record['workerEmail'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (rWorkerId.isNotEmpty) byWorkerId[rWorkerId] = record;
      if (rEmail.isNotEmpty) byEmail[rEmail] = record;
    }
    return (byWorkerId, byEmail);
  }

  Future<List<Map<String, dynamic>>> _fetchAttendance(
    BuildContext context,
    bool isGuest,
    FirestoreService firestoreService,
    List<Map<String, dynamic>> workers,
    DateTime effectivePayrollMonth,
    DateTime effectivePeriodStart,
    DateTime effectivePeriodEnd,
    List<Map<String, dynamic>>? preFetchedAttendance,
  ) async {
    if (isGuest) {
      return workers.map((worker) {
        final att = PayrollService.attendanceCounts(worker);
        return <String, dynamic>{
          'absents': att['absents'] ?? 0,
          'paidLeaves': att['paidLeaves'] ?? 0,
          'unpaidLeaves': att['unpaidLeaves'] ?? 0,
          'leaves': att['leaves'] ?? 0,
        };
      }).toList();
    }

    // Time-off records and holiday dates are identical for every worker, so we
    // fetch them ONCE here and share them across all workers. Previously each
    // worker call re-queried both collections over the network, which made the
    // review dialog slow to open as the number of payable workers grew.
    List<Map<String, dynamic>>? timeOffRecords;
    Set<DateTime>? holidayDates;
    try {
      final shared = await Future.wait<Object>([
        firestoreService.getTimeOffRecords(),
        firestoreService.getHolidayDatesForRange(
          effectivePeriodStart,
          effectivePeriodEnd,
        ),
      ]);
      timeOffRecords = shared[0] as List<Map<String, dynamic>>;
      holidayDates = shared[1] as Set<DateTime>;
    } catch (_) {
      // Fall back to per-worker fetching inside getWorkerMonthlyAttendance.
      timeOffRecords = null;
      holidayDates = null;
    }

    final attendanceFutures = workers.map((worker) async {
      final email = (worker['email'] ?? '').toString();
      final workerId = (worker['workerId'] ?? worker['id'] ?? '')
          .toString()
          .trim();
      try {
        final attendance = await firestoreService.getWorkerMonthlyAttendance(
          email,
          workerId: workerId,
          month: effectivePayrollMonth,
          startDate: effectivePeriodStart,
          endDate: effectivePeriodEnd,
          preFetchedRecords: preFetchedAttendance,
          preFetchedTimeOffRecords: timeOffRecords,
          preFetchedHolidayDates: holidayDates,
        );
        return <String, dynamic>{...attendance};
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'PayrollRunnerAttendanceFetch:$workerId',
        );
        return <String, dynamic>{'_error': error.toString()};
      }
    });
    return await Future.wait(attendanceFutures);
  }

  Future<List<AutoPayrollResult>> _calculateResults({
    required List<Map<String, dynamic>> workers,
    required List<Map<String, dynamic>> attendanceResults,
    required int autoWorkDays,
    required DateTime effectivePeriodStart,
    required DateTime effectivePeriodEnd,
    required String companyCurrency,
    required bool isGuest,
    required Map<String, Map<String, dynamic>> prevPayrollByWorkerId,
    required Map<String, Map<String, dynamic>> prevPayrollByEmail,
  }) async {
    final results = <AutoPayrollResult>[];
    for (int i = 0; i < workers.length; i++) {
      final worker = workers[i];
      final workerId = isGuest
          ? (worker['id'] ?? '').toString()
          : (worker['workerId'] ?? worker['id'] ?? '').toString().trim();
      final name = (worker['name'] ?? '').toString();
      final email = (worker['email'] ?? '').toString();
      final salaryStr = PayrollService.currentSalaryDisplay(
        worker,
        companyCurrency: companyCurrency,
      );
      final totalWorkDays = (worker['totalWorkDays'] ?? '').toString();
      final workDays =
          int.tryParse(totalWorkDays) ?? (autoWorkDays > 0 ? autoWorkDays : 30);
      final attendance = attendanceResults[i];
      final attendanceError = (attendance['_error'] ?? '').toString();

      if (PayrollService.extractSalary(salaryStr) <= 0) {
        results.add(
          _createErrorResult(
            worker,
            workerId,
            name,
            email,
            salaryStr,
            companyCurrency,
            totalWorkDays,
            'please_enter_salary'.tr(),
          ),
        );
        continue;
      }

      final prorationFactor = _calculateProrationFactor(
        worker,
        effectivePeriodStart,
        effectivePeriodEnd,
      );

      if (!isGuest && attendanceError.isNotEmpty) {
        results.add(
          _createErrorResult(
            worker,
            workerId,
            name,
            email,
            salaryStr,
            companyCurrency,
            totalWorkDays,
            attendanceError,
            prorationFactor: prorationFactor,
          ),
        );
        continue;
      }

      final absents = _intValue(attendance['absents']);
      final halfDays = _intValue(attendance['halfDays']);
      final paidLeaves = _intValue(attendance['paidLeaves']);
      final unpaidLeaves = _intValue(attendance['unpaidLeaves']);
      final leaves = _intValue(attendance['leaves']);

      Map<String, dynamic>? prevRecord;
      if (workerId.isNotEmpty) prevRecord = prevPayrollByWorkerId[workerId];
      if (prevRecord == null && email.isNotEmpty) {
        prevRecord = prevPayrollByEmail[email.toLowerCase()];
      }

      final workerOvertime = (worker['overtimeAmount'] ?? '').toString().trim();
      final salaryType = (worker['salaryType'] ?? 'Monthly').toString();
      final prevCustomDeduction = PayrollService.extractSalary(
        (prevRecord?['customDeduction'] ?? '0').toString(),
      );

      try {
        final rawNetVal = PayrollService.calculateNetFromTotals(
          salary: salaryStr,
          overtimeAmount: workerOvertime,
          absentDeduction: '0',
          leaveDeduction: '0',
          customDeduction: prevCustomDeduction.toString(),
          salaryType: salaryType,
          prorationFactor: prorationFactor,
        );
        final currency = PayrollService.getCurrencyPrefix(salaryStr);
        final prefix = currency.isNotEmpty ? '$currency ' : '';
        final netSalary =
            '$prefix${PayrollService.formatFullNumber(rawNetVal)}';

        final isWorkerPaid =
            worker['isPaid'] == true ||
            worker['hasPaidPayrollRecord'] == true ||
            (worker['status'] ?? '').toString().toLowerCase() == 'paid' ||
            (prevRecord != null &&
                PayrollService.isPayrollRecordPaid(prevRecord));

        results.add(
          AutoPayrollResult(
            workerId: workerId,
            workerName: name,
            email: email,
            netSalary: netSalary,
            rawNetSalaryValue: rawNetVal,
            success: true,
            isPaid: isWorkerPaid,
            absents: absents,
            halfDays: halfDays,
            leaves: leaves,
            paidLeaves: paidLeaves,
            unpaidLeaves: unpaidLeaves,
            absentDeduction: _editableAmount(0),
            leaveDeduction: _editableAmount(0),
            customDeduction: _editableAmount(prevCustomDeduction),
            deductionsAreTotals: true,
            overtimeAmount: workerOvertime,
            salary: salaryStr,
            currency: companyCurrency,
            totalWorkDays: workDays.toString(),
            position: (worker['position'] ?? '').toString(),
            employmentType: PayrollService.workerEmploymentType(worker),
            salaryType: salaryType,
            prorationFactor: prorationFactor,
            imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
                ? (worker['profileImage'] ?? '').toString()
                : null,
          ),
        );
      } catch (error, stackTrace) {
        if (!isGuest) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollRunnerCalculation:$workerId',
          );
        }
        results.add(
          _createErrorResult(
            worker,
            workerId,
            name,
            email,
            salaryStr,
            companyCurrency,
            totalWorkDays,
            error.toString(),
            absents: absents,
            halfDays: halfDays,
            leaves: leaves,
            paidLeaves: paidLeaves,
            unpaidLeaves: unpaidLeaves,
            prorationFactor: prorationFactor,
          ),
        );
      }
    }
    return results;
  }

  double _calculateProrationFactor(
    Map<String, dynamic> worker,
    DateTime periodStart,
    DateTime periodEnd,
  ) {
    return 1.0;
  }

  AutoPayrollResult _createErrorResult(
    Map<String, dynamic> worker,
    String workerId,
    String name,
    String email,
    String salaryStr,
    String currency,
    String totalWorkDays,
    String error, {
    int absents = 0,
    int halfDays = 0,
    int leaves = 0,
    int paidLeaves = 0,
    int unpaidLeaves = 0,
    double prorationFactor = 1.0,
  }) {
    return AutoPayrollResult(
      workerId: workerId,
      workerName: name,
      email: email,
      netSalary: '0',
      success: false,
      error: error,
      absents: absents,
      halfDays: halfDays,
      leaves: leaves,
      paidLeaves: paidLeaves,
      unpaidLeaves: unpaidLeaves,
      salary: salaryStr,
      currency: currency,
      totalWorkDays: totalWorkDays,
      position: (worker['position'] ?? '').toString(),
      employmentType: PayrollService.workerEmploymentType(worker),
      salaryType: (worker['salaryType'] ?? 'Monthly').toString(),
      prorationFactor: prorationFactor,
      imageUrl: (worker['profileImage'] ?? '').toString().isNotEmpty
          ? (worker['profileImage'] ?? '').toString()
          : null,
    );
  }

  String _reviewWorkerKey(AutoPayrollResult r) {
    final id = r.workerId.trim();
    if (id.isNotEmpty) return 'id:$id';
    final email = r.email.trim().toLowerCase();
    if (email.isNotEmpty) return 'email:$email';
    return 'name:${r.workerName.trim().toLowerCase()}';
  }

  bool _sameReviewResults(
    List<AutoPayrollResult> a,
    List<AutoPayrollResult> b,
  ) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (_reviewWorkerKey(a[i]) != _reviewWorkerKey(b[i])) return false;
      if (a[i].netSalary != b[i].netSalary) return false;
      if (a[i].success != b[i].success) return false;
    }
    return true;
  }

  Future<PayrollRunSummary> _recomputeLiveSummary({
    required BuildContext context,
    required PayrollRunSummary summary,
    required bool isGuest,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      final firestoreService = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(firestoreServiceProvider);
      final workers = await _loadWorkers(context, isGuest, firestoreService);
      if (workers.isEmpty) return summary;

      final month = DateTime(periodEnd.year, periodEnd.month, 1);
      final data = await _fetchRequiredData(
        context,
        isGuest,
        firestoreService,
        month,
        periodStart,
        periodEnd,
      );
      if (data == null) return summary;

      final (
        companyProfile,
        existingPayroll,
        autoWorkDays,
        preFetchedAttendance,
      ) = data;
      if (autoWorkDays <= 0) return summary;

      final companyCurrency = CurrencyUtils.normalize(
        companyProfile?['currency'],
      );
      final prevPayroll = _buildPrevPayrollMap(existingPayroll, month);
      final attendanceResults = await _fetchAttendance(
        context,
        isGuest,
        firestoreService,
        workers,
        month,
        periodStart,
        periodEnd,
        preFetchedAttendance,
      );

      final results = await _calculateResults(
        workers: workers,
        attendanceResults: attendanceResults,
        autoWorkDays: autoWorkDays,
        effectivePeriodStart: periodStart,
        effectivePeriodEnd: periodEnd,
        companyCurrency: companyCurrency,
        isGuest: isGuest,
        prevPayrollByWorkerId: prevPayroll.$1,
        prevPayrollByEmail: prevPayroll.$2,
      );

      return PayrollRunSummary(
        runDate: summary.runDate,
        totalWorkers: workers.length,
        successCount: results.where((r) => r.success).length,
        failCount: results.where((r) => !r.success).length,
        results: results,
        periodLabel: summary.periodLabel,
      );
    } catch (_) {
      return summary;
    }
  }

  Future<DialogController> _showProgressDialog(BuildContext context) async {
    final controller = DialogController(
      context,
      initialProgress: 0.05,
      initialLabel: 'generating_invoices'.tr(),
    );
    return controller;
  }

  Future<PayrollRunSummary?> _handleSummaryCommit(
    BuildContext context,
    PayrollRunSummary summary,
    bool autoMode,
    bool isGuest,
    DateTime periodStart,
    DateTime periodEnd,
    Map<String, dynamic> companyProfile, {
    Future<Map<String, dynamic>?>? preloadedAssetsFuture,
    VoidCallback? onBeforeReviewDialog,
  }) async {
    var committedSummary = summary;

    if (!autoMode) {
      if (!context.mounted) return null;
      final selectedResults = await _showReviewDialog(
        context,
        summary,
        periodStart: periodStart,
        periodEnd: periodEnd,
        onReviewDialogOpen: onBeforeReviewDialog,
      );
      if (selectedResults == null) return null;

      // One frame is enough for the dialog route to begin closing. The heavy
      // PDF work remains isolated from the UI thread below.
      await WidgetsBinding.instance.endOfFrame;

      committedSummary = PayrollRunSummary(
        runDate: summary.runDate,
        totalWorkers: selectedResults.length,
        successCount: selectedResults.where((r) => r.success).length,
        failCount: selectedResults.where((r) => !r.success).length,
        results: selectedResults,
        periodLabel: summary.periodLabel,
      );
    }

    if (!context.mounted) return null;
    final controller = await _showProgressDialog(context);
    controller.update(
      progress: 0.05,
      label: 'saving_payroll_records'.tr(
        namedArgs: {'saved': '0', 'total': '${committedSummary.totalWorkers}'},
      ),
      forceLabel: true,
    );

    await WidgetsBinding.instance.endOfFrame;

    try {
      final paidResults = committedSummary.successCount >= 1
          ? committedSummary.results.where((r) => r.success).toList()
          : const <AutoPayrollResult>[];

      // 1. Commit database records snappy (~0.8s)
      await _commitPayrollRun(
        committedSummary,
        isGuest,
        context,
        periodStart: periodStart,
        periodEnd: periodEnd,
        controller: controller,
      );

      // 2. Generate PDFs & ZIP — awaited so the share sheet opens before
      // the caller shows "Payroll run complete" and the context may go stale.
      if (paidResults.isNotEmpty) {
        final preloadedAssets = preloadedAssetsFuture == null
            ? null
            : await preloadedAssetsFuture;
        await _generateAndSaveZipSafe(
          context,
          paidResults,
          committedSummary.periodLabel,
          companyProfile,
          controller,
          periodStart: periodStart,
          periodEnd: periodEnd,
          preloadedAssets: preloadedAssets,
        );
      } else {
        controller.dismiss();
      }


      unawaited(
        _sendNotificationsInBackground(
          committedSummary,
          isGuest,
          context,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
      );

      return committedSummary;
    } catch (error, stackTrace) {
      if (!isGuest) {
        ErrorReporter.report(error, stackTrace, context: 'PayrollRunnerCommit');
      }
      if (context.mounted) {
        controller.reset(
          progress: 0,
          label: error.toString().isNotEmpty
              ? error.toString()
              : 'failed_to_save_record'.tr(),
        );
        await Future.delayed(const Duration(seconds: 2));
      }
      controller.dismiss();
      return null;
    }
  }

  Future<void> _sendNotificationsInBackground(
    PayrollRunSummary summary,
    bool isGuest,
    BuildContext context, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    try {
      if (isGuest) return;
      final firestoreService = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(firestoreServiceProvider);
      final notifications = <Map<String, dynamic>>[];
      for (final r in summary.results.where((r) => r.success)) {
        final payrollIdentity = r.workerId.isNotEmpty
            ? r.workerId
            : r.email.trim().toLowerCase();
        if (payrollIdentity.isEmpty) continue;
        final payrollKey = PayrollService.payrollKeyForPeriod(
          payrollIdentity,
          periodStart,
          periodEnd,
        );
        final effectiveWorkerName = r.workerName.trim().isNotEmpty
            ? r.workerName.trim()
            : (r.email.trim().isNotEmpty ? r.email.trim() : 'Worker');
        final amount = r.netSalary;
        notifications.add({
          'notificationKey': 'payroll_$payrollKey',
          'type': 'payroll_added',
          'title': 'notif_title_payroll'.tr(
            namedArgs: {'name': effectiveWorkerName},
          ),
          'message': amount.isNotEmpty
              ? 'notif_msg_payroll_amount'.tr(
                  namedArgs: {'amount': amount, 'name': effectiveWorkerName},
                )
              : 'notif_msg_payroll'.tr(
                  namedArgs: {'name': effectiveWorkerName},
                ),
          'data': {'name': effectiveWorkerName, 'amount': amount},
        });
      }
      if (notifications.isNotEmpty) {
        await firestoreService.addBulkNotifications(notifications);
      }
    } catch (error, stackTrace) {
      ErrorReporter.report(
        error,
        stackTrace,
        context: 'PayrollRunnerNotifications',
      );
    }
  }

  void _showError(
    BuildContext context,
    String key, {
    Map<String, String>? namedArgs,
  }) {
    if (context.mounted) {
      FlashySnackBar.show(
        context,
        message: key.tr(namedArgs: namedArgs ?? const {}),
        isError: true,
      );
    }
  }

  Future<PayrollRunSummary?> payAll(
    BuildContext context, {
    DateTime? payrollMonth,
    DateTime? payPeriodStart,
    DateTime? payPeriodEnd,
    String? positionFilter,
    VoidCallback? onBeforeReviewDialog,
  }) async {
    final result = await runPayroll(
      context,
      autoMode: false,
      payrollMonth: payrollMonth,
      payPeriodStart: payPeriodStart,
      payPeriodEnd: payPeriodEnd,
      positionFilter: positionFilter,
      onBeforeReviewDialog: onBeforeReviewDialog,
    );
    return result;
  }

  Future<int> _commitPayrollRun(
    PayrollRunSummary summary,
    bool isGuest,
    BuildContext context, {
    required DateTime periodStart,
    required DateTime periodEnd,
    DialogController? controller,
  }) async {
    if (isGuest) {
      return await _commitGuestPayroll(summary, periodStart, periodEnd);
    }

    controller?.update(
      progress: 0.08,
      label: 'saving_payroll_records'.tr(
        namedArgs: {'saved': '0', 'total': '${summary.totalWorkers}'},
      ),
      forceLabel: true,
    );

    final firestoreService = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(firestoreServiceProvider);
    final successfulResults = summary.results.where((r) => r.success).toList();
    final payrollKeyByResult = Map<AutoPayrollResult, String>.identity();
    for (final result in successfulResults) {
      final payrollIdentity = result.workerId.isNotEmpty
          ? result.workerId
          : result.email.trim().toLowerCase();
      if (payrollIdentity.isEmpty) continue;
      payrollKeyByResult[result] = PayrollService.payrollKeyForPeriod(
        payrollIdentity,
        periodStart,
        periodEnd,
      );
    }
    final latestPayrollRecords = await firestoreService.getPayrollRecordsByKeys(
      payrollKeyByResult.values,
    );
    final paidPayrollKeys = latestPayrollRecords
        .where(
          (record) =>
              (record['status'] ?? '').toString().trim().toLowerCase() ==
              'paid',
        )
        .map((record) => (record['payrollKey'] ?? '').toString().trim())
        .where((key) => key.isNotEmpty)
        .toSet();

    final unpaidResults = successfulResults.where((result) {
      final expectedPayrollKey = payrollKeyByResult[result];
      return expectedPayrollKey == null ||
          !paidPayrollKeys.contains(expectedPayrollKey);
    }).toList();

    if (unpaidResults.isEmpty) {
      throw StateError(
        'selected_workers_already_paid'.tr().isNotEmpty
            ? 'selected_workers_already_paid'.tr()
            : 'Selected workers are already paid for this period',
      );
    }

    final payrollRecords = <Map<String, dynamic>>[];
    final expenseRecords = <Map<String, dynamic>>[];

    for (final r in unpaidResults) {
      final payrollIdentity = r.workerId.isNotEmpty
          ? r.workerId
          : r.email.trim().toLowerCase();
      if (payrollIdentity.isEmpty) continue;
      final payrollKey =
          payrollKeyByResult[r] ??
          PayrollService.payrollKeyForPeriod(
            payrollIdentity,
            periodStart,
            periodEnd,
          );
      final record = r.toCanonicalPayrollRecord(
        payrollKey: payrollKey,
        periodStart: periodStart,
        periodEnd: periodEnd,
        runDate: summary.runDate,
      );
      payrollRecords.add(record);

      final effectiveWorkerName = r.workerName.trim().isNotEmpty
          ? r.workerName.trim()
          : (r.email.trim().isNotEmpty ? r.email.trim() : 'Worker');
      final netAmount = r.rawNetSalaryValue;
      if (netAmount > 0) {
        expenseRecords.add({
          'workerId': r.workerId,
          'workerEmail': r.email.trim().toLowerCase(),
          'name': effectiveWorkerName,
          'date': summary.runDate,
          'paidAt': summary.runDate,
          'payPeriod': periodEnd,
          'payPeriodStart': periodStart,
          'payPeriodEnd': periodEnd,
          'category': 'Salary',
          'amount': netAmount,
          'description':
              'Salary payment for $effectiveWorkerName (${summary.periodLabel})',
          'payrollKey': payrollKey,
        });
      }
    }

    if (payrollRecords.isEmpty) return 0;

    final payrollCount = await firestoreService
        .addBulkPayrollRecordsAndExpenses(
          payrollRecords: payrollRecords,
          expenseRecords: expenseRecords,
        );
    if (payrollCount != payrollRecords.length) {
      await _rollbackPayrollRecords(firestoreService, payrollRecords);
      throw StateError('Not all payroll records could be saved');
    }

    return payrollCount;
  }

  Future<int> _commitGuestPayroll(
    PayrollRunSummary summary,
    DateTime periodStart,
    DateTime periodEnd,
  ) async {
    final savedPayroll = DummyData.payroll.toList();
    final savedExpenses = DummyData.expenses.toList();
    try {
      for (final r in summary.results) {
        if (!r.success) continue;
        final payrollIdentity = r.workerId.isNotEmpty
            ? r.workerId
            : r.email.trim().toLowerCase();
        final payrollKey = PayrollService.payrollKeyForPeriod(
          payrollIdentity,
          periodStart,
          periodEnd,
        );
        final nowIso = DateTime.now().toIso8601String();
        final canonicalRecord = r.toCanonicalPayrollRecord(
          payrollKey: payrollKey,
          periodStart: periodStart,
          periodEnd: periodEnd,
          runDate: summary.runDate,
        );
        final record = {
          ...canonicalRecord,
          'payPeriod': periodEnd.toIso8601String(),
          'payPeriodStart': periodStart.toIso8601String(),
          'payPeriodEnd': periodEnd.toIso8601String(),
          'dueDate': periodEnd.toIso8601String(),
          'lastModified': summary.runDate.toIso8601String(),
          'createdAt': nowIso,
          'payrollDate': summary.runDate.toIso8601String(),
          'paidAt': summary.runDate.toIso8601String(),
        };
        final existingPayrollIndex = DummyData.payroll.indexWhere(
          (payroll) => (payroll['payrollKey'] ?? '').toString() == payrollKey,
        );
        if (existingPayrollIndex == -1) {
          DummyData.payroll.add({
            ...record,
            'id': DateTime.now().microsecondsSinceEpoch.toString(),
          });
        } else {
          DummyData.payroll[existingPayrollIndex] = {
            ...DummyData.payroll[existingPayrollIndex],
            ...record,
          };
        }
        final netAmount = r.rawNetSalaryValue;
        if (netAmount > 0) {
          final expenseRecord = {
            'name': r.workerName,
            'date': summary.runDate.toIso8601String(),
            'category': 'Salary',
            'amount': netAmount,
            'description':
                'Salary payment for ${r.workerName} (${summary.periodLabel})',
            'payrollKey': payrollKey,
          };
          final expenseId =
              'dummy_e${DateTime.now().microsecondsSinceEpoch}_${r.email.hashCode}';
          final expenseIndex = DummyData.expenses.indexWhere(
            (expense) => (expense['payrollKey'] ?? '').toString() == payrollKey,
          );
          if (expenseIndex == -1) {
            DummyData.expenses.insert(0, {...expenseRecord, 'id': expenseId});
          } else {
            DummyData.expenses[expenseIndex] = {
              ...DummyData.expenses[expenseIndex],
              ...expenseRecord,
            };
          }
        }
      }
      await DummyData.saveToPrefs();
    } catch (_) {
      DummyData.payroll
        ..clear()
        ..addAll(savedPayroll);
      DummyData.expenses
        ..clear()
        ..addAll(savedExpenses);
      rethrow;
    }
    return summary.results.where((result) => result.success).length;
  }

  Future<void> _rollbackPayrollRecords(
    FirestoreService firestoreService,
    List<Map<String, dynamic>> payrollRecords,
  ) async {
    for (final record in payrollRecords) {
      final payrollKey = (record['payrollKey'] ?? '').toString().trim();
      if (payrollKey.isEmpty) continue;
      try {
        await firestoreService.cancelPayrollRecord(
          payrollId: payrollKey.replaceAll('/', '_'),
          payrollKey: payrollKey,
        );
      } catch (error, stackTrace) {
        ErrorReporter.report(
          error,
          stackTrace,
          context: 'PayrollRunnerRollback:$payrollKey',
        );
      }
    }
  }

  Future<void> _generateAndSaveZipSafe(
    BuildContext context,
    List<AutoPayrollResult> paidResults,
    String periodLabel,
    Map<String, dynamic> companyProfile,
    DialogController? controller, {
    required DateTime periodStart,
    required DateTime periodEnd,
    Map<String, dynamic>? preloadedAssets,
    Future<bool>? savePermission,
  }) async {
    try {
      await _generateAndSaveZipWithProgress(
        context,
        paidResults,
        periodLabel,
        companyProfile,
        controller,
        periodStart: periodStart,
        periodEnd: periodEnd,
        preloadedAssets: preloadedAssets,
        savePermission: savePermission,
      );
    } catch (error, stackTrace) {
      ErrorReporter.report(error, stackTrace, context: 'PayrollInvoiceZip');
      final overlayCtx = rootNavigatorKey.currentState?.overlay?.context;
      final errCtx = overlayCtx ?? (context.mounted ? context : null);
      if (errCtx != null) {
        FlashySnackBar.show(
          errCtx,
          message: 'failed_to_generate_zip'.tr(namedArgs: {'error': '$error'}),
          isError: true,
        );
      }
    }
  }

  Future<void> _generateAndSaveZipWithProgress(
    BuildContext context,
    List<AutoPayrollResult> selected,
    String periodLabel,
    Map<String, dynamic> companyProfile,
    DialogController? controller, {
    required DateTime periodStart,
    required DateTime periodEnd,
    Map<String, dynamic>? preloadedAssets,
    Future<bool>? savePermission,
  }) async {
    if (selected.isEmpty) return;

    final locale = context.locale.languageCode;

    try {
      final now = DateTime.now();
      final payPeriod = periodLabel.isNotEmpty
          ? periodLabel
          : '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final periodDisplay = PayrollService.formatPayPeriodRange(
        periodStart,
        periodEnd,
      );

      FirestoreService? firestore;
      try {
        if (context.mounted) {
          firestore = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(firestoreServiceProvider);
        }
      } catch (_) {}
      final resolvedProfile =
          (preloadedAssets?['resolvedProfile'] as Map<String, dynamic>?) ??
          (firestore != null
              ? await CompanyProfileHelper.getCompanyProfileWithFirestore(
                  firestore,
                )
              : companyProfile);

      final Uint8List? companyLogoBytes;
      final Uint8List? companyStampBytes;
      final Uint8List? fontBytes;
      final Map<String, dynamic> translations;

      final companyLogoUrl =
          (resolvedProfile['profilePicUrl'] ??
                  companyProfile['profilePic'] ??
                  companyProfile['profilePicUrl'] ??
                  companyProfile['photoUrl'] ??
                  companyProfile['companyLogoUrl'] ??
                  '')
              .toString()
              .trim();
      final companyStampUrl =
          (resolvedProfile['companyStampUrl'] ??
                  companyProfile['companyStampUrl'] ??
                  companyProfile['stampUrl'] ??
                  companyProfile['companyStamp'] ??
                  '')
              .toString()
              .trim();

      if (preloadedAssets != null &&
          preloadedAssets['fontBytes'] is Uint8List &&
          preloadedAssets['translations'] is Map<String, dynamic>) {
        companyLogoBytes = preloadedAssets['logoBytes'] as Uint8List?;
        companyStampBytes = preloadedAssets['stampBytes'] as Uint8List?;
        fontBytes = preloadedAssets['fontBytes'] as Uint8List?;
        translations = preloadedAssets['translations'] as Map<String, dynamic>;
      } else {
        controller?.update(
          progress: 0.10,
          label: 'generating_invoices'.tr(),
          forceLabel: true,
        );
        final cachedSources = await Future.wait<String?>([
          PreferencesService.getProfilePicLocalPath(),
          PreferencesService.getProfilePicUrl(),
          PreferencesService.getCompanyStampUrl(),
        ]);
        final allAssets = await Future.wait<Object?>([
          _loadCompanyImageDeviceFirst(
            localCandidates: [cachedSources[0], cachedSources[1]],
            remoteSource: companyLogoUrl,
            isStamp: false,
          ),
          _loadCompanyImageDeviceFirst(
            localCandidates: [cachedSources[2]],
            remoteSource: companyStampUrl,
            isStamp: true,
          ),
          PdfHelpers.loadFontBytes(),
          _loadLocaleTranslations(locale),
        ]);
        Uint8List? rawLogo = allAssets[0] as Uint8List?;
        Uint8List? rawStamp = allAssets[1] as Uint8List?;
        if (rawLogo == null || rawLogo.isEmpty) {
          try {
            final data = await rootBundle.load('assets/app_icon.png');
            rawLogo = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
          } catch (_) {}
        }
        if (rawStamp == null || rawStamp.isEmpty) {
          try {
            rawStamp = await loadDefaultHrStampBytes();
          } catch (_) {}
        }
        companyLogoBytes = rawLogo != null && rawLogo.isNotEmpty
            ? compressImageBytes(
                rawLogo,
                maxWidth: 256,
                quality: 75,
                force: true,
              )
            : null;
        companyStampBytes = rawStamp != null && rawStamp.isNotEmpty
            ? compressImageBytes(
                rawStamp,
                maxWidth: 256,
                quality: 75,
                force: true,
              )
            : null;
        fontBytes = allAssets[2] as Uint8List?;
        translations = allAssets[3] as Map<String, dynamic>;
      }

      final companyName = CompanyProfileHelper.companyNameOrFallback(
        resolvedProfile['companyName'] ??
            companyProfile['businessName'] ??
            companyProfile['companyName'],
      );
      final companyAddress =
          (resolvedProfile['address'] ?? companyProfile['address'] ?? '')
              .toString();
      final companyEmail =
          (resolvedProfile['email'] ?? companyProfile['email'] ?? '')
              .toString();
      final companyPhone =
          (resolvedProfile['phone'] ??
                  companyProfile['contact1'] ??
                  companyProfile['phone'] ??
                  '')
              .toString();
      final companyId =
          (resolvedProfile['companyId'] ??
                  companyProfile['companyId'] ??
                  companyProfile['businessId'] ??
                  '')
              .toString();

      final successful = selected.where((result) => result.success).toList();
      if (successful.isEmpty) return;
      final invoiceFiles = <Map<String, Object>>[];

      final maxParallel = Platform.numberOfProcessors.clamp(4, 16);
      final poolSize = successful.length < maxParallel
          ? successful.length
          : maxParallel;


      // Shared assets are the same for every worker, but dart isolate calls are
      // self-contained, so they are carried in each worker arg map directly.
      final sharedAssets = <String, Object?>{
        'fontBytes': fontBytes,
        'companyLogoBytes': companyLogoBytes,
        'companyStampBytes': companyStampBytes,
        'companyName': companyName,
        'companyAddress': companyAddress,
        'companyEmail': companyEmail,
        'companyPhone': companyPhone,
        'companyId': companyId,
        'locale': locale,
        'translations': translations,
        'periodDisplay': periodDisplay,
        'payPeriod': payPeriod,
      };

      final workerArgs = <Map<String, Object?>>[];
      for (var index = 0; index < successful.length; index++) {
        final r = successful[index];
        workerArgs.add(<String, Object?>{
          'index': index,
          'workerId': r.workerId,
          'workerName': r.workerName,
          'email': r.email,
          'position': r.position,
          'salary': r.salary,
          'salaryType': r.salaryType,
          'totalWorkDays': r.totalWorkDays,
          'absents': r.absents,
          'halfDays': r.halfDays,
          'leaves': r.leaves,
          'paidLeaves': r.paidLeaves,
          'unpaidLeaves': r.unpaidLeaves,
          'overtimeAmount': r.overtimeAmount,
          'prorationFactor': r.prorationFactor,
          'absentDeduction': r.absentDeduction,
          'leaveDeduction': r.leaveDeduction,
          'customDeduction': r.customDeduction,
          'currency': r.currency,
        });
      }
      controller?.update(
        progress: 0.10,
        label: 'generating_invoices_progress'.tr(
          namedArgs: {'done': '0', 'total': '${successful.length}'},
        ),
        forceLabel: true,
      );

      final deadline = DateTime.now().add(_pdfBatchTimeout(successful.length));
      final t0 = DateTime.now();
      final spawnStartedAt = DateTime.now();

      Future<_PayrollInvoiceIsolateWorker?> spawnWorker(int index) async {
        try {
          return await _PayrollInvoiceIsolateWorker.spawn(
            sharedAssets,
            index + 1,
          );
        } catch (error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'PayrollInvoiceWorkerSpawn',
          );
          return null;
        }
      }

      final pool = (await Future.wait(
        List.generate(poolSize, spawnWorker),
      )).whereType<_PayrollInvoiceIsolateWorker>().toList();
      final spawnMs = DateTime.now().difference(spawnStartedAt).inMilliseconds;

      var pdfDone = 0;
      Object? firstPdfError;
      StackTrace? firstPdfStack;
      DateTime lastProgressReport = DateTime.now();

      void reportPdfProgress({bool force = false}) {
        final now = DateTime.now();
        if (!force &&
            pdfDone != successful.length &&
            now.difference(lastProgressReport).inMilliseconds < 100) {
          return;
        }
        lastProgressReport = now;
        controller?.update(
          progress: 0.15 + (0.75 * pdfDone / successful.length),
          label: 'generating_invoices_progress'.tr(
            namedArgs: {'done': '$pdfDone', 'total': '${successful.length}'},
          ),
          forceLabel: true,
        );
      }

      var timedOut = false;

      if (pool.isEmpty) {
        for (var index = 0; index < workerArgs.length; index++) {
          try {
            final file = await _generatePayrollInvoiceFile(<String, Object?>{
              ...sharedAssets,
              ...workerArgs[index],
              'invoiceIsolateReady': false,
            });
            invoiceFiles.add(file);
          } catch (error, stackTrace) {
            firstPdfError ??= error;
            firstPdfStack ??= stackTrace;
          }
          pdfDone++;
          reportPdfProgress(force: pdfDone == successful.length);
        }
      } else {
        final workerBatches = List.generate(
          pool.length,
          (_) => <Map<String, Object?>>[],
        );
        for (var index = 0; index < workerArgs.length; index++) {
          workerBatches[index % pool.length].add(workerArgs[index]);
        }

        Future<void> generateBatch(int workerIndex) async {
          try {
            final files = await pool[workerIndex].generateBatch(
              workerBatches[workerIndex],
              (completed) {
                pdfDone += completed;
                reportPdfProgress(force: pdfDone == successful.length);
              },
            );
            invoiceFiles.addAll(files);
          } catch (error, stackTrace) {
            firstPdfError ??= error;
            firstPdfStack ??= stackTrace;
          }
        }

        try {
          await Future.wait(
            List.generate(pool.length, generateBatch),
          ).timeout(deadline.difference(DateTime.now()));
        } on TimeoutException {
          timedOut = true;
        } finally {
          for (final worker in pool) {
            worker.close();
          }
        }
      }

      if (timedOut || invoiceFiles.length != successful.length) {
        if (firstPdfError != null && firstPdfStack != null) {
          ErrorReporter.report(
            firstPdfError!,
            firstPdfStack!,
            context: 'PayrollInvoiceGeneration',
          );
        }
        throw TimeoutException(
          timedOut
              ? 'Invoice generation timed out at ${invoiceFiles.length}/${successful.length}'
              : 'Generated only ${invoiceFiles.length}/${successful.length} invoices',
          _pdfBatchTimeout(successful.length),
        );
      }

      invoiceFiles.sort(
        (a, b) => ((a['sortIndex'] as int?) ?? 0).compareTo(
          (b['sortIndex'] as int?) ?? 0,
        ),
      );

      final pdfMs = DateTime.now().difference(t0).inMilliseconds;
      final averagePdfMs = pdfMs / successful.length;
      debugPrint(
        'PayrollInvoicePerf: workers=${successful.length} pool=${pool.length} '
        'spawnMs=$spawnMs pdfMs=$pdfMs '
        'avgPdfMs=${averagePdfMs.toStringAsFixed(1)}',
      );

      controller?.update(
        progress: 0.90,
        label: 'preparing_zip'.tr(),
        forceLabel: true,
      );

      // PDF rendering can overlap the network commit, but no invoice archive
      // is persisted unless the payroll transaction completed successfully.
      if (savePermission != null && !await savePermission) return;

      final filesForZip = List<Map<String, Object>>.from(invoiceFiles);
      final zipData = await compute(_encodePayrollInvoiceZip, filesForZip);
      final fileName = 'payroll_invoices_$payPeriod.zip';

      controller?.update(progress: 0.95, label: 'preparing_zip'.tr());

      File zipFile;
      try {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          throw StateError('No downloads directory available');
        }
        final candidate = File('${downloadsDir.path}/$fileName');
        await candidate.writeAsBytes(zipData, flush: true);
        zipFile = candidate;
      } catch (_) {
        // Save instantly to writable documents directory to avoid a blocking system FilePicker dialog
        zipFile = await _writeZipToWritableDir(fileName, zipData);
      }

      controller?.update(
        progress: 1.0,
        label: 'payroll_completed'.tr(),
        forceLabel: true,
      );
      await Future.delayed(const Duration(milliseconds: 350));
      controller?.dismiss();

      // rootNavigatorKey.currentContext is the Navigator itself, which has no
      // Overlay ancestor. Use the Navigator's internal overlay context instead,
      // which is always valid while the app is running.
      final overlayCtx = rootNavigatorKey.currentState?.overlay?.context;
      final targetContext =
          overlayCtx ??
          (context.mounted ? context : null);
      if (targetContext != null) {
        FlashySnackBar.show(
          targetContext,
          message: 'zip_saved'.tr(namedArgs: {'fileName': fileName}),
        );
      }
      await FileOpener.open(zipFile.path);
    } catch (e) {
      controller?.dismiss();
      rethrow;
    }
  }

  Future<File> _writeZipToWritableDir(
    String fileName,
    Uint8List zipData,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final file = File('${docsDir.path}/$fileName');
    await file.writeAsBytes(zipData, flush: true);
    return file;
  }

  Future<List<AutoPayrollResult>?> _showReviewDialog(
    BuildContext context,
    PayrollRunSummary summary, {
    DateTime? periodStart,
    DateTime? periodEnd,
    VoidCallback? onReviewDialogOpen,
  }) async {
    final isGuest =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(authServiceProvider).currentUser?.isAnonymous ??
        false;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth < 600 ? screenWidth * 0.95 : 560.0;
    final dialogHeight = screenHeight < 640 ? screenHeight * 0.90 : 580.0;

    String searchQuery = '';
    String positionFilter = 'All';
    bool showOnlyAbsences = false;
    Set<int> selectedIndices = {};
    int? activeDetailIndex;
    final Map<int, TextEditingController> overtimeControllers = {};

    for (int i = 0; i < summary.results.length; i++) {
      if (summary.results[i].success && !summary.results[i].isPaid) {
        selectedIndices.add(i);
      }
    }

    final positionNormalizer = <String, String>{};
    for (final r in summary.results) {
      final pos = r.position.trim();
      if (pos.isNotEmpty) {
        final key = pos.toLowerCase();
        if (!positionNormalizer.containsKey(key)) {
          positionNormalizer[key] = pos
              .split(' ')
              .map((word) {
                if (word.isEmpty) return word;
                return word[0].toUpperCase() + word.substring(1);
              })
              .join(' ');
        }
      }
    }
    final allPositions = positionNormalizer.values.toList()..sort();
    final reviewBackdropFilter = ImageFilter.blur(sigmaX: 2, sigmaY: 2);

    final firestoreService = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(firestoreServiceProvider);
    final reviewedStart =
        periodStart ?? PayrollService.payPeriodStart(DateTime.now());
    final reviewedEnd =
        periodEnd ?? PayrollService.payPeriodEnd(DateTime.now());
    final liveStart = DateTime(
      reviewedStart.year,
      reviewedStart.month,
      reviewedStart.day,
    );
    final liveEnd = DateTime(
      reviewedEnd.year,
      reviewedEnd.month,
      reviewedEnd.day,
    );

    var liveAlive = true;
    Timer? liveRefreshTimer;
    Timer? liveAttachTimer;
    Timer? avatarRevealTimer;
    var liveRefreshAttached = false;
    var revealReviewAvatars = false;
    final liveSubscriptions = <StreamSubscription<dynamic>>[];
    void Function(void Function())? dialogSetState;

    void scheduleLiveRefresh() {
      if (!liveAlive) return;
      liveRefreshTimer?.cancel();
      liveRefreshTimer = Timer(const Duration(milliseconds: 350), () async {
        if (!liveAlive) return;
        final refreshed = await _recomputeLiveSummary(
          context: context,
          summary: summary,
          isGuest: isGuest,
          periodStart: liveStart,
          periodEnd: liveEnd,
        );
        if (!liveAlive) return;
        dialogSetState?.call(() {
          if (refreshed.results.length != summary.results.length ||
              !_sameReviewResults(refreshed.results, summary.results)) {
            final previousSelected = selectedIndices
                .map(
                  (i) => i >= 0 && i < summary.results.length
                      ? _reviewWorkerKey(summary.results[i])
                      : '',
                )
                .where((k) => k.isNotEmpty)
                .toSet();
            final activeKey =
                activeDetailIndex != null &&
                    activeDetailIndex! >= 0 &&
                    activeDetailIndex! < summary.results.length
                ? _reviewWorkerKey(summary.results[activeDetailIndex!])
                : null;

            summary = refreshed;
            selectedIndices.clear();
            for (int i = 0; i < refreshed.results.length; i++) {
              if (refreshed.results[i].success &&
                  previousSelected.contains(
                    _reviewWorkerKey(refreshed.results[i]),
                  )) {
                selectedIndices.add(i);
              }
            }
            if (activeKey != null) {
              final idx = refreshed.results.indexWhere(
                (r) => _reviewWorkerKey(r) == activeKey,
              );
              activeDetailIndex = idx >= 0 ? idx : null;
            } else if (activeDetailIndex != null &&
                activeDetailIndex! >= refreshed.results.length) {
              activeDetailIndex = null;
            }
            overtimeControllers.clear();
          }
        });
      });
    }

    void attachLiveRefresh() {
      if (!liveAlive || liveRefreshAttached) return;
      liveRefreshAttached = true;

      var receivedInitialWorkers = false;
      var receivedInitialTimeOff = false;
      var receivedInitialAttendance = false;
      liveSubscriptions.add(
        firestoreService.workersStream.listen((_) {
          if (!receivedInitialWorkers) {
            receivedInitialWorkers = true;
            return;
          }
          scheduleLiveRefresh();
        }, onError: (_) {}),
      );
      liveSubscriptions.add(
        firestoreService.timeoffStream.listen((_) {
          if (!receivedInitialTimeOff) {
            receivedInitialTimeOff = true;
            return;
          }
          scheduleLiveRefresh();
        }, onError: (_) {}),
      );
      liveSubscriptions.add(
        firestoreService
            .attendanceStreamForPeriod(start: liveStart, end: liveEnd)
            .listen((_) {
              if (!receivedInitialAttendance) {
                receivedInitialAttendance = true;
                return;
              }
              scheduleLiveRefresh();
            }, onError: (_) {}),
      );
    }

    void detachLiveRefresh() {
      liveAlive = false;
      liveAttachTimer?.cancel();
      avatarRevealTimer?.cancel();
      liveRefreshTimer?.cancel();
      for (final sub in liveSubscriptions) {
        sub.cancel();
      }
      liveSubscriptions.clear();
    }

    final dialogResult = await showGeneralDialog<List<AutoPayrollResult>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'PayrollReviewDialog',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onReviewDialogOpen?.call();
          avatarRevealTimer ??= Timer(const Duration(milliseconds: 260), () {
            if (!liveAlive) return;
            dialogSetState?.call(() => revealReviewAvatars = true);
          });
          liveAttachTimer ??= Timer(
            const Duration(milliseconds: 450),
            attachLiveRefresh,
          );
        });
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState;
            final unpaidResults = summary.results
                .where((r) => !r.isPaid)
                .toList();
            final resultIndexByIdentity =
                Map<AutoPayrollResult, int>.identity();
            for (var i = 0; i < summary.results.length; i++) {
              resultIndexByIdentity[summary.results[i]] = i;
            }
            int resultIndexOf(AutoPayrollResult result) =>
                resultIndexByIdentity[result] ?? -1;

            List<AutoPayrollResult> posFiltered;
            if (positionFilter == 'All') {
              posFiltered = List<AutoPayrollResult>.from(unpaidResults)
                ..sort(
                  (a, b) => a.workerName.trim().toLowerCase().compareTo(
                    b.workerName.trim().toLowerCase(),
                  ),
                );
            } else {
              posFiltered = unpaidResults
                  .where(
                    (r) =>
                        r.position.toLowerCase().trim() ==
                        positionFilter.toLowerCase().trim(),
                  )
                  .toList();
            }

            if (showOnlyAbsences) {
              posFiltered = posFiltered.where((r) => r.absents > 0).toList();
            }

            final filteredResults = searchQuery.isEmpty
                ? posFiltered
                : posFiltered
                      .where(
                        (r) =>
                            r.workerName.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ) ||
                            r.email.toLowerCase().contains(
                              searchQuery.toLowerCase(),
                            ),
                      )
                      .toList();

            final filteredSelectedCount = filteredResults
                .where((r) => selectedIndices.contains(resultIndexOf(r)))
                .length;
            final filteredPayCount = filteredResults
                .where(
                  (r) =>
                      r.success && selectedIndices.contains(resultIndexOf(r)),
                )
                .length;
            final allFilteredSelected = filteredResults.every(
              (r) => selectedIndices.contains(resultIndexOf(r)),
            );

            return PopScope(
              canPop: true,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Container(
                    width: dialogWidth,
                    height: dialogHeight,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.12),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: const Color(
                            0xFF0F172A,
                          ).withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 48,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: const Color(0xFF004FDE),
                          child: Row(
                            children: [
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    if (activeDetailIndex != null) {
                                      setDialogState(
                                        () => activeDetailIndex = null,
                                      );
                                    } else {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: Icon(
                                      activeDetailIndex != null
                                          ? Icons.arrow_back_rounded
                                          : Icons.close_rounded,
                                      color: const Color(0xFFFFFFFF),
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Text(
                                    activeDetailIndex != null
                                        ? 'payroll_details_title'
                                              .tr(
                                                namedArgs: {
                                                  'name': summary
                                                      .results[activeDetailIndex!]
                                                      .workerName,
                                                },
                                              )
                                              .trim()
                                        : 'payroll_run_review'.tr(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFFFFFFF),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 32),
                            ],
                          ),
                        ),
                        if (activeDetailIndex != null)
                          Expanded(
                            child: _buildInlineWorkerDetailView(
                              context: context,
                              result: summary.results[activeDetailIndex!],
                              originalIndex: activeDetailIndex!,
                              overtimeControllers: overtimeControllers,
                              onBack: () => setDialogState(
                                () => activeDetailIndex = null,
                              ),
                              isGuest: isGuest,
                              setDialogState: setDialogState,
                            ),
                          )
                        else ...[
                          const SizedBox(height: 12),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                onChanged: (val) {
                                  setDialogState(() => searchQuery = val);
                                },
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'search_workers_hint'.tr(),
                                  hintStyle: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFBDBDBD),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    size: 18,
                                    color: Color(0xFF6B7280),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFFF9FAFB),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF0F70FF),
                                      width: 1.5,
                                    ),
                                  ),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ),

                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                              itemCount: allPositions.length + 1,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final isAll = index == 0;
                                final position = isAll
                                    ? 'All'
                                    : allPositions[index - 1];
                                final isSelected = positionFilter == position;
                                return ChoiceChip(
                                  label: Text(
                                    isAll
                                        ? 'all_filter'.tr()
                                        : LocalizationHelper.localizePosition(
                                            position,
                                          ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    setDialogState(() {
                                      positionFilter = position;
                                      showOnlyAbsences = false;
                                    });
                                  },
                                  selectedColor: const Color(0xFF0C51C1),
                                  backgroundColor: Colors.white,
                                  checkmarkColor: Colors.transparent,
                                  showCheckmark: false,
                                  side: isSelected
                                      ? null
                                      : const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                        ),
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF111827),
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                );
                              },
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 14, 24, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '$filteredSelectedCount ${'selected'.tr()}',
                                          style: const TextStyle(
                                            color: Color(0xFF0247C4),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          'processing_for_cycle'.tr(
                                            namedArgs: {
                                              'period': summary.periodLabel,
                                            },
                                          ),
                                          style: const TextStyle(
                                            color: Color(0xFF6B7280),
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          showOnlyAbsences = !showOnlyAbsences;
                                          if (showOnlyAbsences) {
                                            positionFilter = 'All';
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: showOnlyAbsences
                                              ? const Color(0xFF0C51C1)
                                              : const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              showOnlyAbsences
                                                  ? Icons.filter_alt
                                                  : Icons.filter_alt_off,
                                              size: 14,
                                              color: showOnlyAbsences
                                                  ? const Color(0xFFFFFFFF)
                                                  : const Color(0xFF0247C4),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'with_absences'.tr(),
                                              style: TextStyle(
                                                color: showOnlyAbsences
                                                    ? const Color(0xFFFFFFFF)
                                                    : const Color(0xFF0247C4),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    GestureDetector(
                                      onTap: () {
                                        setDialogState(() {
                                          final filteredIndices =
                                              filteredResults
                                                  .map(resultIndexOf)
                                                  .toSet();
                                          if (allFilteredSelected) {
                                            selectedIndices.removeAll(
                                              filteredIndices,
                                            );
                                          } else {
                                            selectedIndices.addAll(
                                              filteredIndices,
                                            );
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: allFilteredSelected
                                              ? const Color(0xFFFEE2E2)
                                              : const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              allFilteredSelected
                                                  ? Icons.deselect
                                                  : Icons.select_all,
                                              size: 14,
                                              color: allFilteredSelected
                                                  ? const Color(0xFFEF4444)
                                                  : const Color(0xFF0247C4),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              allFilteredSelected
                                                  ? 'deselect_all'.tr()
                                                  : 'select_all'.tr(),
                                              style: TextStyle(
                                                color: allFilteredSelected
                                                    ? const Color(0xFFEF4444)
                                                    : const Color(0xFF0247C4),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 24),
                            height: 1,
                            color: const Color(0xFFE5E7EB),
                          ),

                          Expanded(
                            child: filteredResults.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.search_off_rounded,
                                          size: 48,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'no_results'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      10,
                                      24,
                                      10,
                                    ),
                                    itemCount: filteredResults.length,
                                    itemBuilder: (_, i) {
                                      final r = filteredResults[i];
                                      final originalIndex = resultIndexOf(r);
                                      final isSelected = selectedIndices
                                          .contains(originalIndex);

                                      final avatarColors = [
                                        const Color(0xFFE4F0FF),
                                        const Color(0xFFEFE4FF),
                                        const Color(0xFFE4FFE8),
                                        const Color(0xFFFFE4E4),
                                        const Color(0xFFFFF0E4),
                                      ];
                                      final avatarTextColors = [
                                        const Color(0xFF0F70FF),
                                        const Color(0xFF6A00FF),
                                        const Color(0xFF22C55E),
                                        const Color(0xFFEF4444),
                                        const Color(0xFFF97316),
                                      ];
                                      final colorIdx =
                                          r.workerName.hashCode.abs() % 5;

                                      final posLower = r.position
                                          .toLowerCase()
                                          .trim();
                                      final stLower = r.salaryType
                                          .toLowerCase()
                                          .trim();
                                      final isContractorWorker =
                                          posLower.contains('contract') ||
                                          posLower.contains('freelance') ||
                                          stLower.contains('contract') ||
                                          stLower.contains('freelance') ||
                                          (stLower != 'monthly' &&
                                              stLower.isNotEmpty);
                                      final storedEmploymentType = r
                                          .employmentType
                                          .trim();
                                      final typeLabel =
                                          storedEmploymentType.isNotEmpty
                                          ? LocalizationHelper.localizeType1(
                                              storedEmploymentType,
                                            ).toUpperCase()
                                          : isContractorWorker
                                          ? 'type_contractor'.tr()
                                          : 'type_full_time'.tr();

                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(
                                                      0xFF0F70FF,
                                                    ).withValues(alpha: 0.3)
                                                  : const Color(0xFFE5E7EB),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: InkWell(
                                            onTap: () {
                                              setDialogState(() {
                                                activeDetailIndex =
                                                    originalIndex;
                                              });
                                            },
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                    horizontal: 14,
                                                  ),
                                              child: Row(
                                                children: [
                                                  GestureDetector(
                                                    onTap: () {
                                                      setDialogState(() {
                                                        if (isSelected) {
                                                          selectedIndices
                                                              .remove(
                                                                originalIndex,
                                                              );
                                                        } else {
                                                          selectedIndices.add(
                                                            originalIndex,
                                                          );
                                                        }
                                                      });
                                                    },
                                                    child: Container(
                                                      width: 12,
                                                      height: 12,
                                                      decoration: BoxDecoration(
                                                        border: Border.all(
                                                          color: isSelected
                                                              ? const Color(
                                                                  0xFF0F70FF,
                                                                )
                                                              : const Color(
                                                                  0xFFD1D5DB,
                                                                ),
                                                          width: 1,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              2,
                                                            ),
                                                        color: isSelected
                                                            ? const Color(
                                                                0xFF0F70FF,
                                                              )
                                                            : Colors
                                                                  .transparent,
                                                      ),
                                                      child: isSelected
                                                          ? const Icon(
                                                              Icons.check,
                                                              size: 8,
                                                              color:
                                                                  Colors.white,
                                                            )
                                                          : null,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 14),

                                                  _workerAvatar(
                                                    imageUrl:
                                                        revealReviewAvatars
                                                        ? r.imageUrl
                                                        : null,
                                                    name: r.workerName,
                                                    size: 44,
                                                    backgroundColor:
                                                        avatarColors[colorIdx
                                                                .abs() %
                                                            5],
                                                    textColor:
                                                        avatarTextColors[colorIdx
                                                                .abs() %
                                                            5],
                                                    fontSize: 18,
                                                    allowExtendedSources:
                                                        !isGuest,
                                                  ),
                                                  const SizedBox(width: 14),

                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Flexible(
                                                              child: Text(
                                                                r.workerName,
                                                                style: const TextStyle(
                                                                  fontSize: 15,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  color: Color(
                                                                    0xFF111827,
                                                                  ),
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        7,
                                                                    vertical: 2,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    const Color(
                                                                      0xFFF3F4F6,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                typeLabel,
                                                                style: const TextStyle(
                                                                  fontSize: 10,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color: Color(
                                                                    0xFF4B5563,
                                                                  ),
                                                                  letterSpacing:
                                                                      0.5,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Row(
                                                          children: [
                                                            Icon(
                                                              Icons
                                                                  .mail_outline_rounded,
                                                              size: 13,
                                                              color: Colors
                                                                  .grey
                                                                  .shade400,
                                                            ),
                                                            const SizedBox(
                                                              width: 4,
                                                            ),
                                                            Flexible(
                                                              child: Text(
                                                                r.email.isNotEmpty
                                                                    ? r.email
                                                                    : 'no_email'
                                                                          .tr(),
                                                                style: const TextStyle(
                                                                  fontSize: 13,
                                                                  color: Color(
                                                                    0xFF6B7280,
                                                                  ),
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),

                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                        'net_salary'.tr(),
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Color(
                                                            0xFF6B7280,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 14,
                                                              vertical: 6,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: r.success
                                                              ? const Color(
                                                                  0xFFF0F6FF,
                                                                )
                                                              : const Color(
                                                                  0xFFFEE2E2,
                                                                ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          AmountText.formatCompact(
                                                            r.netSalary,
                                                            locale: context
                                                                .locale
                                                                .toString(),
                                                          ),
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: r.success
                                                                ? const Color(
                                                                    0xFF0F70FF,
                                                                  )
                                                                : const Color(
                                                                    0xFFEF4444,
                                                                  ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(width: 6),

                                                  const Icon(
                                                    Icons.chevron_right_rounded,
                                                    size: 22,
                                                    color: Color(0xFF9CA3AF),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              border: Border(
                                top: BorderSide(
                                  color: Color(0xFFE5E7EB),
                                  width: 1,
                                ),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'total_disbursement'.tr(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6B7280),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      () {
                                        double total = 0;
                                        String prefix = '';
                                        for (final r in filteredResults) {
                                          final idx = resultIndexOf(r);
                                          if (selectedIndices.contains(idx) &&
                                              r.success &&
                                              r.rawNetSalaryValue.isFinite) {
                                            total += r.rawNetSalaryValue;
                                            if (prefix.isEmpty) {
                                              prefix =
                                                  PayrollService.getCurrencyPrefix(
                                                    r.netSalary,
                                                  );
                                            }
                                          }
                                        }
                                        final value =
                                            PayrollService.formatNumber(
                                              total,
                                              locale: context.locale.toString(),
                                            );
                                        return prefix.isEmpty
                                            ? value
                                            : '$prefix $value';
                                      }(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => Navigator.of(context).pop(),
                                      child: Container(
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'cancel'.tr(),
                                          style: const TextStyle(
                                            color: Color(0xFF000000),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    GestureDetector(
                                      onTap: filteredPayCount == 0
                                          ? null
                                          : () {
                                              final selected = filteredResults
                                                  .where(
                                                    (r) =>
                                                        r.success &&
                                                        selectedIndices
                                                            .contains(
                                                              resultIndexOf(r),
                                                            ),
                                                  )
                                                  .toList();
                                              Navigator.of(
                                                context,
                                              ).pop(selected);
                                            },
                                      child: Container(
                                        height: 48,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 22,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: filteredPayCount == 0
                                              ? const Color(
                                                  0xFF0247C4,
                                                ).withValues(alpha: 0.4)
                                              : const Color(0xFF0247C4),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: filteredPayCount > 0
                                              ? [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF0247C4,
                                                    ).withValues(alpha: 0.2),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.check_circle_outline,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'pay_all_count'.tr(
                                                namedArgs: {
                                                  'count': '$filteredPayCount',
                                                },
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        final scale = Tween<double>(begin: 0.985, end: 1).animate(curve);
        return Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: reviewBackdropFilter,
              child: FadeTransition(
                opacity: animation,
                child: const ColoredBox(color: Color(0x730F172A)),
              ),
            ),
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: scale, child: child),
            ),
          ],
        );
      },
    );

    detachLiveRefresh();
    return dialogResult;
  }

  Widget _buildInlineWorkerDetailView({
    required BuildContext context,
    required AutoPayrollResult result,
    required int originalIndex,
    required Map<int, TextEditingController> overtimeControllers,
    required VoidCallback onBack,
    required bool isGuest,
    required StateSetter setDialogState,
  }) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _workerAvatar(
                          imageUrl: result.imageUrl,
                          name: result.workerName,
                          size: 52,
                          backgroundColor: const Color(0xFF0F70FF),
                          textColor: Colors.white,
                          fontSize: 24,
                          allowExtendedSources: !isGuest,
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.workerName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              result.email.isNotEmpty
                                  ? result.email
                                  : 'no_email'.tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'net_pay'.tr(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6B7280),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AmountText.formatCompact(
                            result.netSalary,
                            locale: context.locale.toString(),
                          ),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0247C4),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _metricColumn(
                        title: 'attendance'.tr(),
                        icon: Icons.calendar_today_outlined,
                        iconColor: const Color(0xFF3B82F6),
                        rows: [
                          _metricRow(
                            'absents'.tr(),
                            '${result.absents}',
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                          _metricRow(
                            'leaves_label'.tr(),
                            '${result.paidLeaves}',
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _metricColumn(
                        title: 'earnings'.tr(),
                        icon: Icons.payments_outlined,
                        iconColor: const Color(0xFF10B981),
                        rows: [
                          _metricRow(
                            'base_salary'.tr(),
                            result.salary.isNotEmpty
                                ? AmountText.formatCompact(
                                    result.salary,
                                    locale: context.locale.toString(),
                                  )
                                : _zeroAmount(result.salary),
                            const Color(0xFFF9FAFB),
                            const Color(0xFF6B7280),
                            const Color(0xFF111827),
                          ),
                          _metricRow(
                            'overtime_amount'.tr(),
                            AmountText.formatCompact(
                              '${CurrencyUtils.symbolFor(result.currency)} '
                              '${PayrollService.extractSalary(result.overtimeAmount)}',
                              locale: context.locale.toString(),
                            ),
                            const Color(0xFFECFDF5),
                            const Color(0xFF10B981),
                            const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _metricColumn(
                        title: 'deductions'.tr(),
                        icon: Icons.remove_circle_outline,
                        iconColor: const Color(0xFFEF4444),
                        rows: [
                          _editableDeductionRow(
                            label: 'absent_deduction'.tr(),
                            value: result.absentDeduction,
                            controllerKey: originalIndex * 10 + 1,
                            controllers: overtimeControllers,
                            currencySymbol: CurrencyUtils.symbolFor(
                              result.currency,
                            ),
                            enabled:
                                (result.absents > 0 || result.halfDays > 0) &&
                                _maximumAbsentDeduction(result) > 0,
                            maximumValue: _maximumAbsentDeduction(result),
                            onChanged: (val) {
                              result.absentDeduction = val;
                              _recalcWithDeductions(
                                result,
                                result.customDeduction,
                                () => setDialogState(() {}),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFF3F4F6),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.01),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.more_time,
                          color: Color(0xFF0F70FF),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'adjust_overtime'.tr(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'apply_additional_hours'.tr(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildOvertimeInlineField(
                        result,
                        originalIndex,
                        setDialogState,
                        overtimeControllers,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GestureDetector(
                onTap: () {
                  final controllerKey = originalIndex * 10;
                  final controller = overtimeControllers[controllerKey];
                  if (controller != null) {
                    final clean = controller.text.replaceAll(
                      RegExp(r'[^0-9.]'),
                      '',
                    );
                    _recalcOvertime(result, clean, () {});
                  }
                  onBack();
                },
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0247C4),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0247C4).withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'confirm_review'.tr(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricColumn({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6B7280),
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...rows.map(
          (row) =>
              Padding(padding: const EdgeInsets.only(bottom: 12), child: row),
        ),
      ],
    );
  }

  Widget _metricRow(
    String label,
    String value,
    Color bgColor,
    Color labelColor,
    Color valueColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableDeductionRow({
    required String label,
    required String value,
    required int controllerKey,
    required Map<int, TextEditingController> controllers,
    required String currencySymbol,
    required bool enabled,
    required double maximumValue,
    required void Function(String) onChanged,
  }) {
    if (!controllers.containsKey(controllerKey)) {
      final initialValue = PayrollService.extractSalary(value);
      controllers[controllerKey] = TextEditingController(
        text: enabled && initialValue > 0
            ? value.replaceAll(RegExp(r'[^0-9.]'), '')
            : '',
      );
    }
    final controller = controllers[controllerKey]!;
    final currentValue = PayrollService.extractSalary(controller.text);
    if (!enabled || currentValue > maximumValue) {
      final normalizedValue = enabled ? maximumValue : 0.0;
      final normalizedText = _editableAmount(normalizedValue);
      controller.value = TextEditingValue(
        text: normalizedText,
        selection: TextSelection.collapsed(offset: normalizedText.length),
      );
    }
    final accentColor = enabled
        ? const Color(0xFFEF4444)
        : const Color(0xFF9CA3AF);
    final borderColor = enabled
        ? const Color(0xFFFECACA)
        : const Color(0xFFE5E7EB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                CommaCurrencyFormatter(),
                LengthLimitingTextInputFormatter(14),
              ],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                prefixText: '$currencySymbol ',
                prefixStyle: TextStyle(
                  color: accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                hintText: '0',
                hintStyle: TextStyle(
                  color: accentColor.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(
                    color: Color(0xFFEF4444),
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: (rawValue) {
                final requested = PayrollService.extractSalary(rawValue);
                final capped = requested.clamp(0.0, maximumValue).toDouble();
                if (capped != requested) {
                  final cappedText = _editableAmount(capped);
                  controller.value = TextEditingValue(
                    text: cappedText,
                    selection: TextSelection.collapsed(
                      offset: cappedText.length,
                    ),
                  );
                }
                onChanged(_editableAmount(capped));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOvertimeInlineField(
    AutoPayrollResult r,
    int index,
    void Function(VoidCallback) setDialogState,
    Map<int, TextEditingController> controllers,
  ) {
    final controllerKey = index * 10;
    if (!controllers.containsKey(controllerKey)) {
      final cleanText = r.overtimeAmount.replaceAll(RegExp(r'[^0-9.]'), '');
      controllers[controllerKey] = TextEditingController(text: cleanText);
    }
    final controller = controllers[controllerKey]!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 250,
          height: 44,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              CommaCurrencyFormatter(),
              LengthLimitingTextInputFormatter(14),
            ],
            onChanged: (val) {
              final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
              _recalcOvertime(r, clean, () => setDialogState(() {}));
            },
            onSubmitted: (val) {
              final clean = val.replaceAll(RegExp(r'[^0-9.]'), '');
              _recalcOvertime(r, clean, () => setDialogState(() {}));
            },
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
            decoration: InputDecoration(
              prefixText: '${CurrencyUtils.symbolFor(r.currency)} ',
              prefixStyle: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              hintText: 'amount_hint'.tr(),
              hintStyle: TextStyle(
                color: const Color(0xFF6B7280).withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFE5E7EB),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFE5E7EB),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF0F70FF),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: () {
              final clean = controller.text.replaceAll(RegExp(r'[^0-9.]'), '');
              _recalcOvertime(r, clean, () => setDialogState(() {}));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0247C4),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            child: Text(
              'apply'.tr(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  void _recalcWithDeductions(
    AutoPayrollResult r,
    String deductionVal,
    VoidCallback onUpdated,
  ) {
    r.customDeduction = deductionVal;
    try {
      final absentDeduction = PayrollService.cappedAbsentDeduction(
        hasAbsences: r.absents > 0 || r.halfDays > 0,
        requestedDeduction: PayrollService.extractSalary(r.absentDeduction),
        salary: r.salary,
        overtimeAmount: r.overtimeAmount,
        leaveDeduction: r.leaveDeduction,
        customDeduction: deductionVal,
        salaryType: r.salaryType,
        prorationFactor: r.prorationFactor,
      );
      r.absentDeduction = _editableAmount(absentDeduction);
      final netPayment = PayrollService.calculateNetFromTotals(
        salary: r.salary,
        overtimeAmount: r.overtimeAmount,
        absentDeduction: r.absentDeduction,
        leaveDeduction: r.leaveDeduction,
        customDeduction: deductionVal,
        salaryType: r.salaryType,
        prorationFactor: r.prorationFactor,
      );
      final currency = PayrollService.getCurrencyPrefix(r.salary);
      final p = currency.isNotEmpty ? '$currency ' : '';
      r.netSalary = '$p${PayrollService.formatFullNumber(netPayment)}';
      r.rawNetSalaryValue = netPayment;
      r.deductionsAreTotals = true;
    } catch (e) {
      debugPrint('_recalcWithDeductions error: $e');
    }
    onUpdated();
  }

  double _maximumAbsentDeduction(AutoPayrollResult r) {
    if (r.absents <= 0 && r.halfDays <= 0) return 0.0;
    return PayrollService.maximumAbsentDeduction(
      salary: r.salary,
      overtimeAmount: r.overtimeAmount,
      leaveDeduction: r.leaveDeduction,
      customDeduction: r.customDeduction,
      salaryType: r.salaryType,
      prorationFactor: r.prorationFactor,
    );
  }

  void _recalcOvertime(
    AutoPayrollResult r,
    String overtimeVal,
    VoidCallback onUpdated,
  ) {
    r.overtimeAmount = overtimeVal.trim().isEmpty ? '0' : overtimeVal.trim();
    _recalcWithDeductions(r, r.customDeduction, onUpdated);
  }

  int _intValue(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '0').toString()) ?? 0;
  }

  String _zeroAmount(String salary) {
    final currency = PayrollService.getCurrencyPrefix(salary);
    return currency.isEmpty ? '0' : '$currency 0';
  }

  Widget _workerAvatar({
    required String? imageUrl,
    required String name,
    required double size,
    required Color backgroundColor,
    required Color textColor,
    required double fontSize,
    required bool allowExtendedSources,
  }) {
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        color: backgroundColor,
        alignment: Alignment.center,
        child: Text(
          name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final value = (imageUrl ?? '').trim();
    if (value.isEmpty) return ClipOval(child: fallback());

    Widget image;
    if (isHttpUrl(value)) {
      image = CachedNetworkImage(
        imageUrl: value,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 128,
        memCacheHeight: 128,
        maxWidthDiskCache: 256,
        fadeInDuration: const Duration(milliseconds: 120),
        placeholder: (_, _) => fallback(),
        errorWidget: (_, _, _) => fallback(),
      );
    } else if (!allowExtendedSources) {
      return ClipOval(child: fallback());
    } else if (value.startsWith('data:image')) {
      try {
        final commaIndex = value.indexOf(',');
        if (commaIndex < 0 || commaIndex == value.length - 1) {
          return ClipOval(child: fallback());
        }
        image = Image.memory(
          base64Decode(value.substring(commaIndex + 1)),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        );
      } catch (_) {
        return ClipOval(child: fallback());
      }
    } else if (value.startsWith('assets/')) {
      image = Image.asset(
        value,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      );
    } else {
      try {
        final uri = Uri.tryParse(value);
        final path = uri != null && uri.scheme == 'file'
            ? uri.toFilePath()
            : value;
        image = Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        );
      } catch (_) {
        return ClipOval(child: fallback());
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: image),
    );
  }

  String _editableAmount(num amount) {
    return amount % 1 == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }
}
