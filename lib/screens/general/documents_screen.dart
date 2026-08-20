import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../utils/ui_helpers.dart';
import '../../utils/helpers.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdfx/pdfx.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../riverpod_providers.dart';
import '../../services/auth_service.dart';
import '../../services/dummy_data.dart';
import '../../services/error_reporter.dart';
import '../../services/firestore_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/clickable_gesture_detector.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/screen_table_shimmer.dart';
import '../workers/add_worker_flow.dart' show DocPreview, PdfPagePreview;

class DocumentsScreen extends ConsumerStatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback onProfileTap;
  final VoidCallback? onNotificationTap;

  const DocumentsScreen({
    super.key,
    required this.onLogout,
    required this.onProfileTap,
    this.onNotificationTap,
  });

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final _searchController = TextEditingController();

  String _searchQuery = '';
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  StreamSubscription? _workersSub;
  Map<String, dynamic>? _editingWorker;
  bool _editingShimmer = false;
  Timer? _editingShimmerTimer;

  late final AuthService _authService;
  late final FirestoreService _firestore;

  bool _initialized = false;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);

    if (_isGuest) {
      _workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      _isLoading = true;
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (!mounted) return;
          setState(() {
            _workers = snapshot.docs
                .map(
                  (doc) => {
                    ...doc.data() as Map<String, dynamic>,
                    'id': doc.id,
                  },
                )
                .toList();
            _isLoading = false;
          });
        },
        onError: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    }
  }

  @override
  void dispose() {
    _workersSub?.cancel();
    _editingShimmerTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _workers;
    return _workers.where((w) {
      final name = (w['name'] ?? '').toString().toLowerCase();
      final position = (w['position'] ?? w['role'] ?? w['jobPosition'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(q) || position.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _editingWorker != null
              ? _editingShimmer
                    ? _buildEditPageShimmer()
                    : _EditDocumentsPage(
                        worker: _editingWorker!,
                        onDocumentsUpdated: () => setState(() {}),
                        onBack: () {
                          _editingShimmerTimer?.cancel();
                          setState(() {
                            _editingWorker = null;
                            _editingShimmer = false;
                          });
                        },
                        onNotificationTap: widget.onNotificationTap,
                        onProfileTap: widget.onProfileTap,
                      )
              : _buildWorkerList(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 94,
      padding: EdgeInsets.only(
        left: _editingWorker != null ? 16 : 40,
        right: 40,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Row(
        children: [
          if (_editingWorker != null) ...[
            GestureDetector(
              onTap: () => setState(() => _editingWorker = null),
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
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _editingWorker != null
                    ? (_editingWorker!['name'] ?? 'worker_fallback'.tr())
                          .toString()
                    : 'workforce'.tr(),
                style: const TextStyle(
                  color: Color(0xFF000000),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
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

  Widget _buildWorkerList() {
    if (_isLoading) {
      return LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: const EdgeInsets.fromLTRB(40, 22, 40, 22),
          child: Column(
            children: [
              const ScreenSearchShimmer(height: 48),
              const SizedBox(height: 20),
              Expanded(
                child: ScreenTableShimmer(
                  height: constraints.maxHeight - 68,
                  columnFlexes: const [3, 2],
                  showHeader: false,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredWorkers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40.0, 22.0, 40.0, 0.0),
          child: _buildSearchBar(),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: filtered.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40.0,
                    vertical: 22.0,
                  ),
                  child: _buildEmptyState(),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(40.0, 0.0, 40.0, 22.0),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildWorkerCard(filtered[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 48,
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
            colorFilter: const ColorFilter.mode(
              Color(0xFFBDBDBD),
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'search_workers_name_position'.tr(),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
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
    );
  }

  Widget _buildEmptyState() {
    final dynamicHeight = (MediaQuery.of(context).size.height - 230).clamp(
      440.0,
      1200.0,
    );
    return Container(
      width: double.infinity,
      height: dynamicHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            _searchQuery.isNotEmpty
                ? 'no_search_results'.tr()
                : 'no_workers_added_yet'.tr(),
            style: const TextStyle(
              color: Color(0xFF0247C4),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? 'worker_fallback'.tr()).toString();
    final position = (worker['position'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          if (_isGuest) {
            showGuestRestrictionDialog(context);
            return;
          }
          setState(() {
            _editingWorker = worker;
            _editingShimmer = true;
          });
          _editingShimmerTimer?.cancel();
          _editingShimmerTimer = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) setState(() => _editingShimmer = false);
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              WorkerAvatar(
                imageUrl: worker['profileImage']?.toString(),
                name: name,
                size: 48,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        LocalizationHelper.localizePosition(position),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0247C4).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF0247C4).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                    const SizedBox(width: 6),
                    Text(
                      'edit_documents'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF0247C4),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmerBlock({double? width, required double height}) => Container(
    width: width ?? double.infinity,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
    ),
  );

  Widget _shimmerBox({double? width, required double height}) =>
      Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: _shimmerBlock(width: width, height: height),
      );

  Widget _buildEditPageShimmer() {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shimmerBox(width: 220, height: 24),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: _editShimmerColumn(isCvColumn: false),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: _editShimmerColumn(isCvColumn: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _editShimmerColumn({required bool isCvColumn}) {
    if (isCvColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _shimmerBox(width: 120, height: 16),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _shimmerBox(height: double.infinity)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _shimmerBox(width: 120, height: 16),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmerBox(height: 32),
              const SizedBox(height: 12),
              _shimmerBox(height: _EditDocumentsPageState._idPreviewHeight),
              const SizedBox(height: 12),
              _shimmerBox(height: 32),
              const SizedBox(height: 12),
              _shimmerBox(height: _EditDocumentsPageState._idPreviewHeight),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditDocumentsPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> worker;
  final VoidCallback onDocumentsUpdated;
  final VoidCallback onBack;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const _EditDocumentsPage({
    required this.worker,
    required this.onDocumentsUpdated,
    required this.onBack,
    this.onNotificationTap,
    this.onProfileTap,
  });

  @override
  ConsumerState<_EditDocumentsPage> createState() => _EditDocumentsPageState();
}

class _EditDocumentsPageState extends ConsumerState<_EditDocumentsPage> {
  static const double _idPreviewHeight = 270;
  static const List<String> _cvAllowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'pdf',
    'doc',
    'docx',
  ];

  bool _isUploading = false;
  String? _downloadingField;
  String? _uploadingField;
  Uint8List? _frontIdBytes;
  String? _frontIdName;
  Uint8List? _backIdBytes;
  String? _backIdName;
  Uint8List? _cvBytes;
  String? _cvName;
  bool _isCvUploaded = false;

  late AuthService _authService;
  late FirestoreService _firestore;

  bool get _isGuest => _authService.currentUser?.isAnonymous ?? false;

  String get _workerId => (widget.worker['id'] ?? '').toString().trim();

  String get _workerName =>
      (widget.worker['name'] ?? 'worker_fallback'.tr()).toString().trim();

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final text = v?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return null;
  }

  String? get _existingFrontId => _firstNonEmpty([
    widget.worker['frontId']?.toString(),
    widget.worker['front_id']?.toString(),
    widget.worker['idFront']?.toString(),
    widget.worker['frontID']?.toString(),
    widget.worker['id_front']?.toString(),
  ]);

  String? get _existingBackId => _firstNonEmpty([
    widget.worker['backId']?.toString(),
    widget.worker['back_id']?.toString(),
    widget.worker['idBack']?.toString(),
    widget.worker['backID']?.toString(),
    widget.worker['id_back']?.toString(),
  ]);

  String? get _existingCv => _firstNonEmpty([
    widget.worker['cv']?.toString(),
    widget.worker['cvUrl']?.toString(),
    widget.worker['cv_url']?.toString(),
  ]);

  String? get _existingCvName => _firstNonEmpty([
    widget.worker['cvFileName']?.toString(),
    widget.worker['cv_file_name']?.toString(),
    widget.worker['cvName']?.toString(),
  ]);

  @override
  void initState() {
    super.initState();
    final existingCv = _existingCv;
    if (existingCv != null && existingCv.isNotEmpty) {
      _isCvUploaded = true;
      _cvName = _existingCvName ?? _cleanFileName(existingCv);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = ref.read(authServiceProvider);
    _firestore = ref.read(firestoreServiceProvider);
  }

  String _cleanFileName(String value) {
    try {
      if (value.startsWith('data:')) return 'cv';
      var clean = value.split('?').first;
      clean = Uri.decodeComponent(clean);
      final name = clean.split('/').last.trim();
      final cleaned = name.replaceFirst(RegExp(r'^\d+_\d+_'), '');
      return cleaned.isNotEmpty ? cleaned : 'cv';
    } catch (_) {
      return 'cv';
    }
  }

  Uint8List? _decodeDataUrl(String value) {
    try {
      if (!value.startsWith('data:') || !value.contains(',')) return null;
      final bytes = base64Decode(value.split(',').last);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  String _documentErrorMessage(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|StateError|Bad state):\s*'), '')
        .trim();
  }

  Future<void> _pickFile(String field) async {
    if (_isUploading) return;
    try {
      final result = await FilePicker.pickFiles(
        type: field == 'cv' ? FileType.custom : FileType.image,
        allowedExtensions: field == 'cv' ? _cvAllowedExtensions : null,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;

      if (file.size > UploadService.maxFileBytes) {
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
            isError: true,
          );
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'upload_failed'.tr(
              namedArgs: {'error': 'Failed to pick file'.tr()},
            ),
            isError: true,
          );
        return;
      }

      if (bytes.length > UploadService.maxFileBytes) {
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
            isError: true,
          );
        return;
      }

      setState(() {
        if (field == 'frontId') {
          _frontIdBytes = bytes;
          _frontIdName = file.name;
        } else if (field == 'backId') {
          _backIdBytes = bytes;
          _backIdName = file.name;
        } else if (field == 'cv') {
          _cvBytes = bytes;
          _cvName = file.name;
          _isCvUploaded = true;
        }
      });

      await _uploadAndSave(field);
    } catch (error) {
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': _documentErrorMessage(error)},
          ),
          isError: true,
        );
    }
  }

  Future<void> _downloadFile(
    String? url,
    Uint8List? bytes,
    String defaultName, {
    String? field,
  }) async {
    if (_downloadingField != null) return;
    setState(() => _downloadingField = field);
    try {
      Uint8List? fileBytes = bytes;

      if ((fileBytes == null || fileBytes.isEmpty) &&
          url != null &&
          url.trim().isNotEmpty) {
        if (url.startsWith('data:')) {
          final commaIdx = url.indexOf(',');
          if (commaIdx != -1)
            fileBytes = base64Decode(url.substring(commaIdx + 1));
        } else {
          try {
            final downloaded = await UploadService.downloadRemoteFile(
              url: url,
              folder: 'documents',
              fallbackFileName: defaultName,
              fallbackMimeType: 'application/octet-stream',
            );
            fileBytes = downloaded.bytes;
          } catch (_) {
            try {
              fileBytes = await FirebaseStorage.instance
                  .refFromURL(url)
                  .getData();
            } catch (_) {}
          }
        }
      }

      if (fileBytes != null && fileBytes.isNotEmpty) {
        final result = await FilePicker.saveFile(
          dialogTitle: 'download_file'.tr(),
          fileName: defaultName,
          bytes: fileBytes,
        );
        if (result != null && result.trim().isNotEmpty) {
          await io.File(result).writeAsBytes(fileBytes, flush: true);
          if (mounted)
            FlashySnackBar.show(
              context,
              message: 'file_downloaded_successfully'.tr(),
            );
          await FileOpener.open(result);
        }
      } else {
        if (mounted)
          FlashySnackBar.show(
            context,
            message: 'could_not_download_file'.tr(),
            isError: true,
          );
      }
    } catch (_) {
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'could_not_download_file'.tr(),
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _downloadingField = null);
    }
  }

  Future<void> _uploadAndSave(String field) async {
    if (_isUploading) return;

    Uint8List? bytes;
    String? fileName;
    String? existingUrl;

    if (field == 'frontId') {
      bytes = _frontIdBytes;
      fileName = _frontIdName;
      existingUrl = _existingFrontId;
    } else if (field == 'backId') {
      bytes = _backIdBytes;
      fileName = _backIdName;
      existingUrl = _existingBackId;
    } else if (field == 'cv') {
      bytes = _cvBytes;
      fileName = _cvName;
      existingUrl = _existingCv;
    } else {
      return;
    }

    if (bytes == null && (existingUrl == null || existingUrl.isEmpty)) {
      return;
    }

    if (!_isGuest && _workerId.isEmpty) {
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': 'Worker not found'.tr()},
          ),
          isError: true,
        );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadingField = field;
    });
    String? newlyUploadedUrl;

    try {
      String? url;

      if (bytes != null) {
        if (_isGuest) {
          url =
              'data:${mimeTypeForExtension(fileName ?? 'file')};base64,${base64Encode(bytes)}';
        } else {
          final folder = field == 'frontId'
              ? 'front_ids'
              : field == 'backId'
              ? 'back_ids'
              : 'cvs';
          final results = await UploadService.uploadFiles(
            files: [
              UploadFile(
                folder: folder,
                fileName: fileName ?? 'file',
                bytes: bytes,
                mimeType: mimeTypeForExtension(fileName ?? 'file'),
              ),
            ],
          );

          if (results.isEmpty || !results.first.isSuccess) {
            throw Exception(
              results.isEmpty
                  ? 'file_upload_failed'.tr(
                      namedArgs: {'file': fileName ?? 'file'},
                    )
                  : results.first.error ??
                        'file_upload_failed'.tr(
                          namedArgs: {'file': fileName ?? 'file'},
                        ),
            );
          }

          url = results.first.url;
          newlyUploadedUrl = url;
        }
      } else {
        url = existingUrl;
      }

      if (url == null || url.trim().isEmpty) {
        throw Exception(
          'file_upload_failed'.tr(namedArgs: {'file': fileName ?? 'file'}),
        );
      }

      final updates = _buildUpdatesMap(field, url, fileName);

      if (_isGuest) {
        final idx = DummyData.workers.indexWhere((w) {
          final wId = (w['id'] ?? '').toString();
          final wEmail = (w['email'] ?? '').toString().trim().toLowerCase();
          final targetEmail = (widget.worker['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return (wId.isNotEmpty && wId == _workerId) ||
              (wEmail.isNotEmpty && wEmail == targetEmail);
        });
        if (idx != -1) {
          DummyData.workers[idx].addAll(updates);
          await DummyData.saveToPrefs();
        }
      } else {
        await _firestore.updateWorkerFields(_workerId, updates);
      }

      if (existingUrl != null && existingUrl.isNotEmpty && existingUrl != url) {
        try {
          await UploadService.deleteByUrl(existingUrl);
        } catch (e, s) {
          ErrorReporter.report(e, s, context: 'documentsCleanupOldFile');
        }
      }

      updates.forEach((key, value) => widget.worker[key] = value);
      widget.onDocumentsUpdated();

      if (!mounted) return;
      FlashySnackBar.show(context, message: _successMessage(field));
    } catch (error) {
      if (newlyUploadedUrl != null) {
        try {
          await UploadService.deleteByUrl(newlyUploadedUrl);
        } catch (e, s) {
          ErrorReporter.report(e, s, context: 'documentsRollbackNewFile');
        }
      }
      if (mounted)
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': _documentErrorMessage(error)},
          ),
          isError: true,
        );
    } finally {
      if (mounted)
        setState(() {
          _isUploading = false;
          _uploadingField = null;
        });
    }
  }

  Map<String, dynamic> _buildUpdatesMap(
    String field,
    String url,
    String? fileName,
  ) {
    final updates = <String, dynamic>{'name': _workerName};

    if (field == 'frontId') {
      updates['frontId'] = url;
      updates['front_id'] = url;
      updates['idFront'] = url;
      updates['id_front'] = url;
    } else if (field == 'backId') {
      updates['backId'] = url;
      updates['back_id'] = url;
      updates['idBack'] = url;
      updates['id_back'] = url;
    } else {
      updates['cv'] = url;
      updates['cvFileName'] = fileName ?? _cleanFileName(url);
    }

    return updates;
  }

  String _successMessage(String field) {
    return switch (field) {
      'frontId' => 'cnic_front_updated'.tr(namedArgs: {'name': _workerName}),
      'backId' => 'cnic_back_updated'.tr(namedArgs: {'name': _workerName}),
      _ => 'cv_updated'.tr(namedArgs: {'name': _workerName}),
    };
  }

  void _viewDocument(
    String? url,
    bool isImage,
    String label, {
    bool isPdf = false,
    bool isDoc = false,
    Uint8List? pdfBytes,
  }) {
    if (url == null || url.isEmpty) return;

    final lower = url.toLowerCase();
    if (!isPdf && !isDoc)
      isPdf =
          lower.endsWith('.pdf') ||
          lower.contains('application/pdf') ||
          lower.contains('/pdf/');
    if (!isPdf && !isDoc)
      isDoc = lower.endsWith('.doc') || lower.endsWith('.docx');

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close'.tr(),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, _, _) => _FullScreenDocumentViewer(
        url: url,
        label: label,
        isImage: isImage,
        isPdf: isPdf,
        isDoc: isDoc,
        pdfBytes: pdfBytes,
        heightFactor: 0.8,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        final scale = Tween<double>(
          begin: 0.92,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack));
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 6 * anim.value,
                  sigmaY: 6 * anim.value,
                ),
                child: FadeTransition(
                  opacity: fade,
                  child: Container(
                    color: const Color(0xFF000000).withOpacity(0.35),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            ),
          ],
        );
      },
    );
  }

  void _showImagePreviewDialog(
    BuildContext context, {
    Uint8List? bytes,
    String? url,
    required bool isPdf,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close'.tr(),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, _, _) => _FullScreenDocumentViewer(
        url: url ?? '',
        label: 'document'.tr(),
        isImage: !isPdf,
        isPdf: isPdf,
        pdfBytes: bytes,
        imageBytes: isPdf ? null : bytes,
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        final scale = Tween<double>(
          begin: 0.92,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack));
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 6 * anim.value,
                  sigmaY: 6 * anim.value,
                ),
                child: FadeTransition(
                  opacity: fade,
                  child: Container(
                    color: const Color(0xFF000000).withOpacity(0.35),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: fade,
              child: ScaleTransition(scale: scale, child: child),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'personal_documentation'.tr(),
              style: const TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 1, child: _buildIdCardSection()),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: _buildCvSection()),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildIdCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'id_card_label'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIdFieldHeader(
                'upload_front_side'.tr(),
                'frontId',
                _existingFrontId,
                _frontIdBytes,
                _frontIdName,
              ),
              const SizedBox(height: 12),
              _buildIdUploadBox(
                label: 'upload_front_id_hint'.tr(),
                field: 'frontId',
                bytes: _frontIdBytes,
                fileName: _frontIdName,
                existingUrl: _existingFrontId,
                onTap: () => _pickFile('frontId'),
              ),
              const SizedBox(height: 12),
              _buildIdFieldHeader(
                'upload_back_side'.tr(),
                'backId',
                _existingBackId,
                _backIdBytes,
                _backIdName,
              ),
              const SizedBox(height: 12),
              _buildIdUploadBox(
                label: 'upload_back_id_hint'.tr(),
                field: 'backId',
                bytes: _backIdBytes,
                fileName: _backIdName,
                existingUrl: _existingBackId,
                onTap: () => _pickFile('backId'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdFieldHeader(
    String labelText,
    String field,
    String? existingUrl,
    Uint8List? bytes,
    String? fileName,
  ) {
    final hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);
    final defaultName = field == 'frontId' ? 'front_id' : 'back_id';

    return Row(
      children: [
        GestureDetector(
          onTap: () => _pickFile(field),
          child: Text(
            labelText,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        const Spacer(),
        if (hasFile) ...[
          _buildIconButton(
            onTap: () => _downloadFile(
              existingUrl,
              bytes,
              fileName ?? defaultName,
              field: field,
            ),
            icon: Icons.file_download_outlined,
            label: 'download'.tr(),
            isLoading: _downloadingField == field,
          ),
          const SizedBox(width: 8),
          _buildEditButton(onTap: () => _pickFile(field)),
        ],
      ],
    );
  }

  Widget _buildIconButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
    bool isLoading = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditButton({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'edit'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 6),
            SvgPicture.asset(
              'assets/edit_icon.svg',
              height: 14,
              width: 14,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCvSection() {
    final hasCv =
        _isCvUploaded || (_existingCv != null && _existingCv!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'upload_cv_label'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (hasCv) ...[
                GestureDetector(
                  onTap: () => _downloadFile(
                    _existingCv,
                    _cvBytes,
                    _cvName ?? 'cv',
                    field: 'cv',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_downloadingField == 'cv')
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          const Icon(
                            Icons.file_download_outlined,
                            color: Colors.white,
                            size: 14,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          'download'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildEditButton(onTap: () => _pickFile('cv')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        (hasCv && _uploadingField != 'cv')
            ? Expanded(child: _buildCvPreview())
            : Expanded(child: _buildCvUpload()),
      ],
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    required String field,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);
    final cleanUrl = (existingUrl ?? '').split('?').first.toLowerCase();
    final cleanName = (fileName ?? '').toLowerCase();
    final isPdf =
        cleanName.endsWith('.pdf') ||
        cleanUrl.endsWith('.pdf') ||
        cleanUrl.startsWith('data:application/pdf');
    final decodedDataImage = existingUrl == null
        ? null
        : _decodeDataUrl(existingUrl);

    final boxContent = GestureDetector(
      onTap: hasFile
          ? () => _showImagePreviewDialog(
              context,
              bytes: bytes,
              url: existingUrl,
              isPdf: isPdf,
            )
          : onTap,
      child: Container(
        height: _idPreviewHeight,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF0B50C3).withOpacity(0.5)
                : Colors.grey.shade200,
            width: hasFile ? 2 : 1,
          ),
        ),
        child: hasFile
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (isPdf)
                    PdfPagePreview(cvBytes: bytes, existingCvUrl: existingUrl)
                  else if (bytes != null)
                    Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (decodedDataImage != null)
                    Image.memory(
                      decodedDataImage,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else
                    _buildIdPlaceholder(label, hasFile),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black.withOpacity(0.54),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              fileName ?? 'file_uploaded'.tr(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildIdPlaceholder(label, false),
      ),
    );

    if (_uploadingField == field) {
      return Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height: _idPreviewHeight,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: const Color(0xFF0B50C3).withOpacity(0.5),
              width: 2,
            ),
          ),
        ),
      );
    }

    return boxContent;
  }

  Widget _buildIdPlaceholder(String label, bool hasFile) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          'assets/Id card.png',
          width: 50,
          height: 50,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tap_to_select_file'.tr(),
          style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    final uploadBox = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 12,
            bottom: 12,
            left: 24,
            right: 24,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      height: 16,
                      width: 200,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: 150,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 40),
                    ...List.generate(
                      8,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          height: 12,
                          width: double.infinity,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _pickFile('cv'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'upload'.tr(),
                        style: const TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SvgPicture.asset(
                        'assets/Upload_profile.svg',
                        height: 18,
                        width: 18,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'upload_cv_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (_uploadingField == 'cv') {
      return Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: uploadBox,
      );
    }

    return uploadBox;
  }

  Widget _buildCvPreview() {
    final cvUrl = _existingCv;
    final detectedName = (_cvName == null || _cvName!.trim().isEmpty)
        ? _cleanFileName(cvUrl ?? '')
        : _cvName!.trim();
    final lower = detectedName.toLowerCase();
    final lowerUrl = (cvUrl ?? '').toLowerCase();

    final isPdf =
        lower.endsWith('.pdf') || lowerUrl.startsWith('data:application/pdf');
    final isImage =
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lowerUrl.startsWith('data:image/');
    final isDoc = lower.endsWith('.doc') || lower.endsWith('.docx');

    void onTapCv() {
      if (_cvBytes != null) {
        final mime = mimeTypeForExtension(_cvName ?? 'file');
        _viewDocument(
          'data:$mime;base64,${base64Encode(_cvBytes!)}',
          isImage,
          _cvName ?? 'cv_resume'.tr(),
          isPdf: isPdf,
          isDoc: isDoc,
          pdfBytes: _cvBytes,
        );
      } else if (cvUrl != null && cvUrl.isNotEmpty) {
        _viewDocument(
          cvUrl,
          isImage,
          _cvName ?? 'cv_resume'.tr(),
          isPdf: isPdf,
          isDoc: isDoc,
        );
      }
    }

    Widget previewContent;

    if (isImage) {
      previewContent = _cvBytes != null
          ? Image.memory(
              _cvBytes!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            )
          : (cvUrl != null && cvUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: cvUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image, size: 48)),
                  )
                : const SizedBox.shrink());
    } else if (isPdf) {
      previewContent = PdfPagePreview(
        cvBytes: _cvBytes,
        existingCvUrl: cvUrl,
        fit: BoxFit.cover,
      );
    } else if (isDoc) {
      previewContent = DocPreview(
        docBytes: _cvBytes,
        docName: _cvName,
        docUrl: cvUrl,
      );
    } else {
      previewContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description, size: 48, color: Color(0xFF0247C4)),
            const SizedBox(height: 12),
            Text(
              _cvName ?? 'cv_resume'.tr(),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTapCv,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F3F6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              top: 8,
              bottom: 8,
              child: FractionallySizedBox(
                widthFactor: 0.76,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: previewContent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenPdfPreview extends StatefulWidget {
  final String? url;
  final Uint8List? bytes;

  const _FullScreenPdfPreview({this.url, this.bytes});

  @override
  State<_FullScreenPdfPreview> createState() => _FullScreenPdfPreviewState();
}

class _FullScreenPdfPreviewState extends State<_FullScreenPdfPreview> {
  final ScrollController _scrollController = ScrollController();
  PdfDocument? _document;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openDocument();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _document?.close();
    super.dispose();
  }

  Future<void> _openDocument() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final source = widget.url?.trim() ?? '';
      if (source.isEmpty) throw StateError('failed_to_load_pdf'.tr());

      Uint8List bytes = widget.bytes ?? Uint8List(0);

      if (bytes.isEmpty) {
        if (isHttpUrl(source)) {
          try {
            bytes =
                await FirebaseStorage.instance
                    .refFromURL(source)
                    .getData(UploadService.maxFileBytes) ??
                Uint8List(0);
          } catch (_) {
            final downloaded = await UploadService.downloadRemoteFile(
              url: source,
              folder: 'document_previews',
              fallbackFileName: 'document.pdf',
              fallbackMimeType: 'application/pdf',
            );
            bytes = downloaded.bytes;
          }
        } else if (source.startsWith('data:application/pdf')) {
          if (!source.contains(','))
            throw FormatException('invalid_pdf_data'.tr());
          bytes = base64Decode(source.split(',').last);
        } else {
          throw StateError('failed_to_load_pdf'.tr());
        }
      }

      if (bytes.isEmpty) throw StateError('failed_to_load_pdf'.tr());
      if (bytes.length > UploadService.maxFileBytes)
        throw StateError('file_too_large'.tr(namedArgs: {'size': '10MB'}));

      final document = await PdfDocument.openData(bytes);
      if (!mounted) {
        await document.close();
        return;
      }

      setState(() {
        _document = document;
        _isLoading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString();
          _isLoading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF0247C4),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'loading_pdf'.tr(),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              'failed_to_load_pdf'.tr(),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final document = _document;
    if (document == null) {
      return Center(
        child: Text(
          'no_pages_found'.tr(),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          ui.PointerDeviceKind.touch,
          ui.PointerDeviceKind.mouse,
          ui.PointerDeviceKind.trackpad,
          ui.PointerDeviceKind.stylus,
        },
      ),
      child: Scrollbar(
        controller: _scrollController,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(8),
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          itemCount: document.pagesCount,
          itemBuilder: (_, index) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _LazyPdfPage(document: document, pageNumber: index + 1),
          ),
        ),
      ),
    );
  }
}

class _LazyPdfPage extends StatefulWidget {
  final PdfDocument document;
  final int pageNumber;

  const _LazyPdfPage({required this.document, required this.pageNumber});

  @override
  State<_LazyPdfPage> createState() => _LazyPdfPageState();
}

class _LazyPdfPageState extends State<_LazyPdfPage> {
  Uint8List? _imageBytes;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renderPage();
  }

  Future<void> _renderPage() async {
    if (_loading || _imageBytes != null) return;
    setState(() => _loading = true);

    PdfPage? page;
    try {
      page = await widget.document.getPage(widget.pageNumber);
      final pageImage = await page.render(
        width: (page.width * 1.5).toDouble(),
        height: (page.height * 1.5).toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#ffffff',
      );
      if (!mounted) return;
      setState(() {
        _imageBytes = pageImage?.bytes;
        _loading = false;
      });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error.toString();
          _loading = false;
        });
    } finally {
      await page?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.fitWidth,
        filterQuality: FilterQuality.high,
        width: double.infinity,
      );
    }
    if (_error != null) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
      );
    }
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _FullScreenDocumentViewer extends StatefulWidget {
  final String url;
  final String label;
  final bool isImage;
  final bool isPdf;
  final bool isDoc;
  final Uint8List? pdfBytes;
  final Uint8List? imageBytes;
  final double heightFactor;

  const _FullScreenDocumentViewer({
    required this.url,
    required this.label,
    required this.isImage,
    this.isPdf = false,
    this.isDoc = false,
    this.pdfBytes,
    this.imageBytes,
    this.heightFactor = 0.6,
  });

  @override
  State<_FullScreenDocumentViewer> createState() =>
      _FullScreenDocumentViewerState();
}

class _FullScreenDocumentViewerState extends State<_FullScreenDocumentViewer> {
  Uint8List _base64ToBytes(String dataUrl) {
    try {
      if (!dataUrl.contains(',')) return Uint8List(0);
      return base64Decode(dataUrl.split(',').last);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Widget _buildImageContent(String failedToLoadText) {
    if (widget.imageBytes != null) {
      return Image.memory(
        widget.imageBytes!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            failedToLoadText,
            style: const TextStyle(color: Color(0xFF9E9E9E)),
          ),
        ),
      );
    }

    if (widget.url.startsWith('data:')) {
      return Image.memory(
        _base64ToBytes(widget.url),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            failedToLoadText,
            style: const TextStyle(color: Color(0xFF9E9E9E)),
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.url,
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, _) => const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF0247C4)),
        ),
      ),
      errorWidget: (_, _, _) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image, size: 48, color: Color(0xFF9E9E9E)),
            const SizedBox(height: 10),
            Text(
              failedToLoadText,
              style: const TextStyle(color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final previewWidth = size.width > 720
        ? (size.width * 0.85).clamp(450.0, 720.0)
        : (size.width * 0.92);
    final maxPreviewHeight = (size.height * widget.heightFactor + 0.2 - 70)
        .clamp(160.0, 600.0);
    final previewHeight = (size.height * (widget.heightFactor + 0.15))
        .clamp(160.0, maxPreviewHeight)
        .toDouble();

    final failedToLoadText = 'failed_to_load'.tr();
    final cleanTitle = cleanUploadedDocumentFileName(
      widget.label,
      fallback: 'document'.tr(),
    );
    final cleanFileName = cleanUploadedDocumentFileName(
      widget.url,
      fallback: 'document'.tr(),
    );

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: size.height * (widget.heightFactor + 0.1),
      ),
      child: Container(
        width: previewWidth,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.25),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF7F8FA),
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      cleanTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A).withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Color(0xFF1A1A1A),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFFEEEEEE), height: 1),
            SizedBox(
              height: previewHeight,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
                child: _buildPreviewContent(
                  previewHeight,
                  cleanFileName,
                  failedToLoadText,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(onTap: () {}, child: content),
        ),
      ),
    );
  }

  Widget _buildPreviewContent(
    double previewHeight,
    String cleanFileName,
    String failedToLoadText,
  ) {
    if (widget.isPdf) {
      return Container(
        color: const Color(0xFFFFFFFF),
        width: double.infinity,
        child: _FullScreenPdfPreview(url: widget.url, bytes: widget.pdfBytes),
      );
    }

    if (widget.isDoc) {
      return Container(
        color: const Color(0xFFFFFFFF),
        width: double.infinity,
        child: DocPreview(docUrl: widget.url, docName: widget.label),
      );
    }

    if (widget.isImage) {
      return Container(
        color: const Color(0xFFFFFFFF),
        width: double.infinity,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: _buildImageContent(failedToLoadText),
        ),
      );
    }

    return SizedBox(
      height: 290,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.picture_as_pdf,
              size: 64,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                cleanFileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.url.startsWith('http') ||
                    widget.url.startsWith('file')) ...[
                  GestureDetector(
                    onTap: () async {
                      final ctx = context;
                      try {
                        final uri = Uri.tryParse(widget.url);
                        if (uri == null) throw const FormatException();
                        final opened = await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!opened && ctx.mounted) {
                          FlashySnackBar.show(
                            ctx,
                            message: 'failed_to_load'.tr(),
                            isError: true,
                          );
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          FlashySnackBar.show(
                            ctx,
                            message: 'failed_to_load'.tr(),
                            isError: true,
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0247C4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.open_in_new,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'open_document'.tr(),
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'close'.tr(),
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
