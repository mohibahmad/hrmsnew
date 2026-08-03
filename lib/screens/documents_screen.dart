import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/dummy_data.dart';
import '../services/upload_service.dart';
import '../services/error_reporter.dart';
import '../utils/image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdfx/pdfx.dart';
import 'add_worker_flow.dart' show PdfPagePreview;
import '../utils/guest_restriction.dart';

class DocumentsScreen extends StatefulWidget {
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
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _workers = [];
  bool _isLoading = false;
  StreamSubscription? _workersSub;
  Map<String, dynamic>? _editingWorker;
  late AuthService _authService;
  late FirestoreService _firestore;

  @override
  void dispose() {
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      _isLoading = true;
      _workersSub = _firestore.workersStream.listen(
        (snapshot) {
          if (mounted) {
            setState(() {
              _workers = snapshot.docs.map((doc) {
                return {...doc.data() as Map<String, dynamic>, 'id': doc.id};
              }).toList();
              _isLoading = false;
            });
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        },
      );
    }
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _workers;
    return _workers.where((w) {
      final name = (w['name'] ?? '').toString().toLowerCase();
      final position = (w['position'] ?? '').toString().toLowerCase();
      return name.contains(q) || position.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 94,
          padding: EdgeInsets.only(
            left: _editingWorker != null ? 16 : 40,
            right: 40,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            border: Border(
              bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
            ),
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
                    style: TextStyle(
                      color: const Color(0xFF000000),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SF Pro Display',
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
        ),
        Expanded(
          child: _editingWorker != null
              ? _EditDocumentsPage(
                  worker: _editingWorker!,
                  onDocumentsUpdated: () {
                    setState(() {});
                  },
                  onBack: () => setState(() => _editingWorker = null),
                  onNotificationTap: widget.onNotificationTap,
                  onProfileTap: widget.onProfileTap,
                )
              : _buildWorkerList(),
        ),
      ],
    );
  }

  Widget _buildWorkerList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 22.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
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
                          onChanged: (val) {
                            setState(() => _searchQuery = val);
                          },
                          decoration: InputDecoration(
                            hintText: 'search_workers_hint'.tr(),
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
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
                            setState(() => _searchQuery = '');
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
            ],
          ),
          const SizedBox(height: 20),
          if (_filteredWorkers.isEmpty)
            _buildEmptyState()
          else
            ..._filteredWorkers.map((worker) => _buildWorkerCard(worker)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool isSearchEmpty = _searchQuery.isNotEmpty;
    final double dynamicHeight = MediaQuery.of(context).size.height - 450;
    return SizedBox(
      width: double.infinity,
      height: dynamicHeight < 300 ? 300 : dynamicHeight,
      child: Center(
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
              isSearchEmpty
                  ? 'no_search_results'.tr()
                  : 'no_workers_added_yet'.tr(),
              style: const TextStyle(
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

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? 'worker_fallback'.tr()).toString();
    final position = (worker['position'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          final isGuest = _authService.currentUser?.isAnonymous ?? false;
          if (isGuest) {
            showGuestRestrictionDialog(context);
            return;
          }
          _openDocumentDialog(worker);
        },
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.04),
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
                        fontFamily: 'SF Pro Display',
                        color: Color(0xFF000000),
                      ),
                    ),
                    if (position.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        position,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[500],
                          fontFamily: 'SF Pro Display',
                        ),
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
                  color: const Color(0xFF0247C4).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF0247C4).withValues(alpha: 0.2),
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
                        fontFamily: 'SF Pro Display',
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

  void _openDocumentDialog(Map<String, dynamic> worker) {
    setState(() => _editingWorker = worker);
  }
}

class _EditDocumentsPage extends StatefulWidget {
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
  State<_EditDocumentsPage> createState() => _EditDocumentsPageState();
}

class _EditDocumentsPageState extends State<_EditDocumentsPage> {
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
  Uint8List? _frontIdBytes;
  String? _frontIdName;
  Uint8List? _backIdBytes;
  String? _backIdName;
  Uint8List? _cvBytes;
  String? _cvName;
  bool _isCvUploaded = false;
  late AuthService _authService;
  late FirestoreService _firestore;

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
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

  String get _workerId => (widget.worker['id'] ?? '').toString().trim();
  String get _workerName =>
      (widget.worker['name'] ?? 'worker_fallback'.tr()).toString().trim();

  String _cleanFileName(String value) {
    try {
      if (value.startsWith('data:')) return 'cv';
      var cleanValue = value.split('?').first;
      cleanValue = Uri.decodeComponent(cleanValue);
      final name = cleanValue.split('/').last.trim();
      return name.isNotEmpty ? name : 'cv';
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

  String _getMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'application/octet-stream';
  }

  @override
  void initState() {
    super.initState();
    final existingCv = _existingCv;
    if (existingCv != null && existingCv.isNotEmpty) {
      _isCvUploaded = true;
      _cvName = _cleanFileName(existingCv);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _authService = Provider.of<AuthService>(context, listen: false);
    _firestore = Provider.of<FirestoreService>(context, listen: false);
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
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
            isError: true,
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'upload_failed'.tr(
              namedArgs: {'error': 'Failed to pick file'.tr()},
            ),
            isError: true,
          );
        }
        return;
      }

      if (bytes.length > UploadService.maxFileBytes) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'file_too_large'.tr(namedArgs: {'size': '10MB'}),
            isError: true,
          );
        }
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
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': _documentErrorMessage(error)},
          ),
          isError: true,
        );
      }
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

    if (bytes == null && (existingUrl == null || existingUrl.isEmpty)) return;

    final isGuest = _authService.currentUser?.isAnonymous ?? false;
    if (!isGuest && _workerId.isEmpty) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': 'Worker not found'.tr()},
          ),
          isError: true,
        );
      }
      return;
    }

    setState(() => _isUploading = true);

    String? newlyUploadedUrl;

    try {
      String? url;

      if (bytes != null) {
        if (isGuest) {
          url =
              'data:${_getMimeType(fileName ?? 'file')};base64,${base64Encode(bytes)}';
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
                mimeType: _getMimeType(fileName ?? 'file'),
              ),
            ],
          );

          if (results.isEmpty || !results.first.isSuccess) {
            final error = results.isEmpty
                ? 'file_upload_failed'.tr(
                    namedArgs: {'file': fileName ?? 'file'},
                  )
                : results.first.error ??
                      'file_upload_failed'.tr(
                        namedArgs: {'file': fileName ?? 'file'},
                      );
            throw Exception(error);
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

      final updates = <String, dynamic>{};
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
      }
      updates['name'] = _workerName;

      if (isGuest) {
        final workerIndex = DummyData.workers.indexWhere((worker) {
          final workerId = (worker['id'] ?? '').toString();
          final workerEmail = (worker['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final targetEmail = (widget.worker['email'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          return (workerId.isNotEmpty && workerId == _workerId) ||
              (workerEmail.isNotEmpty && workerEmail == targetEmail);
        });
        if (workerIndex != -1) {
          DummyData.workers[workerIndex].addAll(updates);
          await DummyData.saveToPrefs();
        }
      } else {
        // Partial update: only send the document fields, never the whole
        // cached worker object. A stale in-memory copy must not overwrite
        // salary/status/leave-balance/contact changed by another screen.
        await _firestore.updateWorkerFields(_workerId, updates);
      }

      // Firestore save succeeded. Delete the replaced old file (best-effort).
      if (existingUrl != null && existingUrl.isNotEmpty && existingUrl != url) {
        try {
          await UploadService.deleteByUrl(existingUrl);
        } catch (error, stackTrace) {
          ErrorReporter.report(
            error,
            stackTrace,
            context: 'documentsCleanupOldFile',
          );
        }
      }

      updates.forEach((key, value) {
        widget.worker[key] = value;
      });
      widget.onDocumentsUpdated();

      if (!mounted) return;
      FlashySnackBar.show(
        context,
        message: field == 'frontId'
            ? 'cnic_front_updated'.tr(namedArgs: {'name': _workerName})
            : field == 'backId'
            ? 'cnic_back_updated'.tr(namedArgs: {'name': _workerName})
            : 'cv_updated'.tr(namedArgs: {'name': _workerName}),
      );
    } catch (error) {
      // Firestore save failed: roll back the newly uploaded file so it does
      // not remain as an invisible orphan in Storage.
      if (newlyUploadedUrl != null) {
        try {
          await UploadService.deleteByUrl(newlyUploadedUrl);
        } catch (cleanupError, cleanupStack) {
          ErrorReporter.report(
            cleanupError,
            cleanupStack,
            context: 'documentsRollbackNewFile',
          );
        }
      }
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'upload_failed'.tr(
            namedArgs: {'error': _documentErrorMessage(error)},
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _viewDocument(
    String? url,
    bool isImage,
    String label, {
    bool isPdf = false,
  }) {
    if (url == null || url.isEmpty) return;
    if (!isPdf) {
      final lower = url.toLowerCase();
      isPdf =
          lower.endsWith('.pdf') ||
          lower.contains('application/pdf') ||
          lower.contains('/pdf/');
    }
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close'.tr(),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, secAnim) => _FullScreenDocumentViewer(
        url: url,
        label: label,
        isImage: isImage,
        isPdf: isPdf,
      ),
      transitionBuilder: (ctx, anim, secAnim, child) {
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
                    color: const Color(0xFF000000).withValues(alpha: 0.35),
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
              style: TextStyle(
                color: Color(0xFF000000),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 36,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'id_card_label'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SF Pro Display',
                              ),
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
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _pickFile('frontId'),
                                    child: Text(
                                      'upload_front_side'.tr(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_frontIdBytes != null ||
                                      (_existingFrontId != null &&
                                          _existingFrontId!.isNotEmpty))
                                    GestureDetector(
                                      onTap: () => _pickFile('frontId'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF000000),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
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
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            SvgPicture.asset(
                                              'assets/edit_icon.svg',
                                              height: 14,
                                              width: 14,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                    Colors.white,
                                                    BlendMode.srcIn,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildIdUploadBox(
                                label: 'upload_front_id_hint'.tr(),
                                bytes: _frontIdBytes,
                                fileName: _frontIdName,
                                existingUrl: _existingFrontId,
                                onTap: () => _pickFile('frontId'),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _pickFile('backId'),
                                    child: Text(
                                      'upload_back_side'.tr(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_backIdBytes != null ||
                                      (_existingBackId != null &&
                                          _existingBackId!.isNotEmpty))
                                    GestureDetector(
                                      onTap: () => _pickFile('backId'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF000000),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
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
                                                fontFamily: 'SF Pro Display',
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            SvgPicture.asset(
                                              'assets/edit_icon.svg',
                                              height: 14,
                                              width: 14,
                                              colorFilter:
                                                  const ColorFilter.mode(
                                                    Colors.white,
                                                    BlendMode.srcIn,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildIdUploadBox(
                                label: 'upload_back_id_hint'.tr(),
                                bytes: _backIdBytes,
                                fileName: _backIdName,
                                existingUrl: _existingBackId,
                                onTap: () => _pickFile('backId'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 36,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'upload_cv_label'.tr(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              const Spacer(),
                              if (_isCvUploaded ||
                                  (_existingCv != null &&
                                      _existingCv!.isNotEmpty)) ...[
                                GestureDetector(
                                  onTap: () => _pickFile('cv'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
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
                                            fontFamily: 'SF Pro Display',
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
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _isCvUploaded ||
                                (_existingCv != null && _existingCv!.isNotEmpty)
                            ? Expanded(child: _buildCvPreview())
                            : Expanded(child: _buildCvUpload()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            if (_isUploading)
              Center(
                child: CircularProgressIndicator(color: Color(0xFF0247C4)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdUploadBox({
    required String label,
    Uint8List? bytes,
    String? fileName,
    String? existingUrl,
    VoidCallback? onTap,
  }) {
    final bool hasFile =
        bytes != null || (existingUrl != null && existingUrl.isNotEmpty);
    final cleanUrl = (existingUrl ?? '').split('?').first.toLowerCase();
    final cleanName = (fileName ?? '').toLowerCase();
    final bool isPdf =
        cleanName.endsWith('.pdf') ||
        cleanUrl.endsWith('.pdf') ||
        cleanUrl.startsWith('data:application/pdf');
    final bool isImage =
        bytes != null ||
        cleanName.endsWith('.png') ||
        cleanName.endsWith('.jpg') ||
        cleanName.endsWith('.jpeg') ||
        cleanName.endsWith('.gif') ||
        cleanName.endsWith('.webp') ||
        cleanName.endsWith('.bmp') ||
        cleanUrl.endsWith('.png') ||
        cleanUrl.endsWith('.jpg') ||
        cleanUrl.endsWith('.jpeg') ||
        cleanUrl.endsWith('.gif') ||
        cleanUrl.endsWith('.webp') ||
        cleanUrl.endsWith('.bmp') ||
        cleanUrl.startsWith('data:image') ||
        (cleanUrl.startsWith('http') && !isPdf);
    final decodedDataImage = existingUrl == null
        ? null
        : _decodeDataUrl(existingUrl);

    return GestureDetector(
      onTap: hasFile
          ? () {
              if (bytes != null) {
                final mimeType = _getMimeType(fileName ?? 'file');
                final safeMimeType = mimeType.startsWith('image/')
                    ? mimeType
                    : 'image/jpeg';
                final dataUrl =
                    'data:$safeMimeType;base64,${base64Encode(bytes)}';
                _viewDocument(dataUrl, true, label);
              } else if (existingUrl != null && existingUrl.isNotEmpty) {
                _viewDocument(existingUrl, isImage, label, isPdf: isPdf);
              }
            }
          : onTap,
      child: Container(
        height: 320,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasFile
                ? const Color(0xFF0B50C3).withValues(alpha: 0.5)
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
                      errorBuilder: (context, error, stackTrace) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (decodedDataImage != null)
                    Image.memory(
                      decodedDataImage,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
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
                      color: Colors.black.withValues(alpha: 0.54),
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
                                fontFamily: 'SF Pro Display',
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
            fontFamily: 'SF Pro Display',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'tap_to_select_file'.tr(),
          style: TextStyle(
            color: Colors.grey.shade300,
            fontSize: 12,
            fontFamily: 'SF Pro Display',
          ),
        ),
      ],
    );
  }

  Widget _buildCvUpload() {
    return Container(
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
                        style: TextStyle(
                          color: Color(0xFFFFFFFF),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          fontFamily: 'SF Pro Display',
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
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'upload_cv_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4B5563),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCvPreview() {
    final cvUrl = _existingCv;
    final detectedName = (_cvName == null || _cvName!.trim().isEmpty)
        ? _cleanFileName(cvUrl ?? '')
        : _cvName!.trim();
    final cvNameLower = detectedName.toLowerCase();
    final lowerUrl = (cvUrl ?? '').toLowerCase();
    final isPdf =
        cvNameLower.endsWith('.pdf') ||
        lowerUrl.startsWith('data:application/pdf');
    final isImage =
        cvNameLower.endsWith('.png') ||
        cvNameLower.endsWith('.jpg') ||
        cvNameLower.endsWith('.jpeg') ||
        cvNameLower.endsWith('.gif') ||
        cvNameLower.endsWith('.webp') ||
        cvNameLower.endsWith('.bmp') ||
        lowerUrl.startsWith('data:image/');
    final isDoc = cvNameLower.endsWith('.doc') || cvNameLower.endsWith('.docx');

    void onTapCv() {
      if (_cvBytes != null) {
        final mimeType = _getMimeType(_cvName ?? 'file');
        final dataUrl = 'data:$mimeType;base64,${base64Encode(_cvBytes!)}';
        _viewDocument(
          dataUrl,
          isImage,
          _cvName ?? 'cv_resume'.tr(),
          isPdf: isPdf,
        );
      } else if (cvUrl != null && cvUrl.isNotEmpty) {
        _viewDocument(
          cvUrl,
          isImage,
          _cvName ?? 'cv_resume'.tr(),
          isPdf: isPdf,
        );
      }
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
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: isImage
                      ? (_cvBytes != null
                            ? Image.memory(
                                _cvBytes!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              )
                            : (cvUrl != null && cvUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: cvUrl,
                                      fit: BoxFit.contain,
                                      errorWidget: (context, url, error) =>
                                          const Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              size: 48,
                                            ),
                                          ),
                                    )
                                  : const SizedBox.shrink()))
                      : isPdf
                      ? PdfPagePreview(
                          cvBytes: _cvBytes,
                          existingCvUrl: cvUrl,
                          fit: BoxFit.cover,
                        )
                      : isDoc
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                cvNameLower.endsWith('.docx')
                                    ? Icons.article_outlined
                                    : Icons.description_outlined,
                                size: 48,
                                color: const Color(0xFF0247C4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _cvName ?? 'cv_resume'.tr(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.description,
                                size: 48,
                                color: Color(0xFF0247C4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _cvName ?? 'cv_resume'.tr(),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 13,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _cleanDocumentFileName(String rawName) {
  if (rawName.trim().isEmpty) return 'document'.tr();
  String name = rawName.trim().split('?').first;
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {}
  if (name.contains('/')) {
    name = name.split('/').last;
  }
  name = name.trim();
  name = name.replaceFirst(RegExp(r'^\d+[_-]+'), '');
  name = name.replaceAll(RegExp(r'_+'), ' ');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  return name.trim().isNotEmpty ? name.trim() : 'document'.tr();
}

class _FullScreenPdfPreview extends StatefulWidget {
  final String? url;

  const _FullScreenPdfPreview({this.url});

  @override
  State<_FullScreenPdfPreview> createState() => _FullScreenPdfPreviewState();
}

class _FullScreenPdfPreviewState extends State<_FullScreenPdfPreview> {
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
      if (source.isEmpty) {
        throw StateError('Failed to load PDF'.tr());
      }

      Uint8List bytes;
      if (source.startsWith('http://') || source.startsWith('https://')) {
        final downloaded = await UploadService.downloadRemoteFile(
          url: source,
          folder: 'document_previews',
          fallbackFileName: 'document.pdf',
          fallbackMimeType: 'application/pdf',
        );
        bytes = downloaded.bytes;
      } else if (source.startsWith('data:application/pdf')) {
        if (!source.contains(',')) {
          throw const FormatException('Invalid PDF data');
        }
        bytes = base64Decode(source.split(',').last);
      } else {
        throw StateError('Failed to load PDF'.tr());
      }

      if (bytes.isEmpty) {
        throw StateError('Failed to load PDF'.tr());
      }
      if (bytes.length > UploadService.maxFileBytes) {
        throw StateError('file_too_large'.tr(namedArgs: {'size': '10MB'}));
      }

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
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isLoading = false;
        });
      }
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
              'Loading PDF...'.tr(),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.grey,
                fontFamily: 'SF Pro Display',
              ),
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
              'Failed to load PDF'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontFamily: 'SF Pro Display',
              ),
            ),
          ],
        ),
      );
    }
    final document = _document;
    if (document == null) {
      return Center(
        child: Text(
          'No pages found'.tr(),
          style: const TextStyle(
            color: Colors.grey,
            fontFamily: 'SF Pro Display',
          ),
        ),
      );
    }
    // Lazy render: only the visible page(s) are rendered on demand at 1.5×
    // resolution. Off-screen pages are not held in memory, so a 50–100 page
    // document no longer consumes hundreds of MB of rendered PNGs.
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: document.pagesCount,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LazyPdfPage(document: document, pageNumber: index + 1),
        );
      },
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
      // 1.5× resolution is sufficient for on-screen viewing and keeps memory
      // usage low for long documents.
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
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    } finally {
      await page?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.contain,
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

  const _FullScreenDocumentViewer({
    required this.url,
    required this.label,
    required this.isImage,
    this.isPdf = false,
  });

  @override
  State<_FullScreenDocumentViewer> createState() =>
      _FullScreenDocumentViewerState();
}

class _FullScreenDocumentViewerState extends State<_FullScreenDocumentViewer> {
  Uint8List _base64ToBytes(String dataUrl) {
    try {
      if (!dataUrl.contains(',')) return Uint8List(0);
      final base64 = dataUrl.split(',').last;
      return base64Decode(base64);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final previewWidth = size.width > 720
        ? (size.width * 0.85).clamp(450.0, 720.0)
        : size.width;
    final failedToLoadText = 'failed_to_load'.tr();
    final cleanTitle = _cleanDocumentFileName(widget.label);
    final cleanFileName = _cleanDocumentFileName(widget.url);

    final Widget imageContent = widget.url.startsWith('data:')
        ? Image.memory(
            _base64ToBytes(widget.url),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                failedToLoadText,
                style: const TextStyle(color: Color(0xFF9E9E9E)),
              ),
            ),
          )
        : CachedNetworkImage(
            imageUrl: widget.url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            placeholder: (c, u) => const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0247C4)),
              ),
            ),
            errorWidget: (c, u, e) => Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Color(0xFF9E9E9E),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    failedToLoadText,
                    style: const TextStyle(color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
          );

    final content = Container(
      width: previewWidth,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.25),
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
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A).withValues(alpha: 0.06),
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
          Flexible(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
              child: widget.isImage
                  ? Container(
                      color: const Color(0xFFFFFFFF),
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxHeight: size.height * 0.85,
                      ),
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: imageContent,
                      ),
                    )
                  : widget.isPdf
                  ? Container(
                      color: const Color(0xFFFFFFFF),
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxHeight: size.height * 0.85,
                      ),
                      child: _FullScreenPdfPreview(url: widget.url),
                    )
                  : SizedBox(
                      height: 280,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text(
                                cleanFileName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF1A1A1A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.url.startsWith('http') ||
                                    widget.url.startsWith('file'))
                                  GestureDetector(
                                    onTap: () async {
                                      try {
                                        final uri = Uri.tryParse(widget.url);
                                        if (uri == null) {
                                          throw const FormatException();
                                        }
                                        final opened = await launchUrl(
                                          uri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                        if (!opened && context.mounted) {
                                          FlashySnackBar.show(
                                            context,
                                            message: 'failed_to_load'.tr(),
                                            isError: true,
                                          );
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          FlashySnackBar.show(
                                            context,
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
                                            'Open Document'.tr(),
                                            style: const TextStyle(
                                              color: Color(0xFFFFFFFF),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'SF Pro Display',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (widget.url.startsWith('http') ||
                                    widget.url.startsWith('file'))
                                  const SizedBox(width: 12),
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
                                        fontFamily: 'SF Pro Display',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
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
}
