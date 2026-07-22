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
import '../utils/image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/notification_bell.dart';
import 'add_worker_flow.dart' show PdfPagePreview;

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

  @override
  void dispose() {
    _workersSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final isGuest = AuthService().currentUser?.isAnonymous ?? false;
    if (isGuest) {
      _workers = List<Map<String, dynamic>>.from(DummyData.workers);
    } else {
      _isLoading = true;
      _workersSub = FirestoreService().workersStream.listen((snapshot) {
        if (mounted) {
          setState(() {
            _workers = snapshot.docs.map((doc) {
              return {...doc.data() as Map<String, dynamic>, 'id': doc.id};
            }).toList();
            _isLoading = false;
          });
        }
      });
    }
  }

  List<Map<String, dynamic>> get _filteredWorkers {
    if (_searchQuery.isEmpty) return _workers;
    final q = _searchQuery.toLowerCase();
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
                        ? (_editingWorker!['name'] ?? 'Unknown').toString()
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
          ..._filteredWorkers.map((worker) => _buildWorkerCard(worker)),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? 'Unknown').toString();
    final position = (worker['position'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
            GestureDetector(
              onTap: () => _openDocumentDialog(worker),
              child: Container(
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
            ),
          ],
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
  bool _isUploading = false;
  Uint8List? _frontIdBytes;
  String? _frontIdName;
  Uint8List? _backIdBytes;
  String? _backIdName;
  Uint8List? _cvBytes;
  String? _cvName;
  bool _isCvUploaded = false;

  String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final s = v?.toString();
      if (s != null && s.isNotEmpty && s != 'null') return s;
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

  String get _workerId => widget.worker['id'] ?? '';
  String get _workerName => (widget.worker['name'] ?? 'Unknown').toString();

  String _cleanFileName(String url) {
    try {
      final name = url.split('/').last.split('?').first;
      return name.isNotEmpty ? name : 'cv';
    } catch (_) {
      return 'cv';
    }
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

  Future<void> _pickFile(String field) async {
    final result = await FilePicker.pickFiles(
      type: field == 'cv' ? FileType.custom : FileType.image,
      allowedExtensions: field == 'cv' ? ['pdf', 'doc', 'docx'] : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      if (field == 'frontId') {
        _frontIdBytes = file.bytes;
        _frontIdName = file.name;
      } else if (field == 'backId') {
        _backIdBytes = file.bytes;
        _backIdName = file.name;
      } else if (field == 'cv') {
        _cvBytes = file.bytes;
        _cvName = file.name;
        _isCvUploaded = true;
      }
    });

    await _uploadAndSave(field);
  }

  Future<void> _uploadAndSave(String field) async {
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
    }

    if (bytes == null && (existingUrl == null || existingUrl.isEmpty)) return;

    setState(() => _isUploading = true);

    try {
      String? url = existingUrl;
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;

      if (bytes != null) {
        if (isGuest) {
          final isImage = field != 'cv';
          url =
              'data:${isImage ? 'image/jpeg' : 'application/pdf'};base64,${base64Encode(bytes)}';
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
                mimeType: field == 'cv' ? 'application/pdf' : 'image/jpeg',
              ),
            ],
          );
          if (results.isNotEmpty && results.first.isSuccess) {
            url = results.first.url;
          }
        }
      }

      if (url != null && url.isNotEmpty) {
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
          updates[field] = url;
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
          await FirestoreService().updateWorker(_workerId, updates);
        }
        updates.forEach((key, value) {
          widget.worker[key] = value;
        });
        widget.onDocumentsUpdated();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            FlashySnackBar.show(
              context,
              message: field == 'frontId'
                  ? 'cnic_front_updated'.tr(namedArgs: {'name': _workerName})
                  : field == 'backId'
                  ? 'cnic_back_updated'.tr(namedArgs: {'name': _workerName})
                  : 'cv_updated'.tr(namedArgs: {'name': _workerName}),
            );
          }
        });
      }
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: 'upload_failed'.tr(namedArgs: {'error': '$e'}),
            isError: true,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _viewDocument(String? url, bool isImage, String label) {
    if (url == null || url.isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim, secAnim) =>
          _FullScreenDocumentViewer(url: url, label: label, isImage: isImage),
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
    final bool isPdf = cleanName.endsWith('.pdf') || cleanUrl.endsWith('.pdf');
    final bool isImage =
        cleanName.endsWith('.png') ||
        cleanName.endsWith('.jpg') ||
        cleanName.endsWith('.jpeg') ||
        cleanUrl.endsWith('.png') ||
        cleanUrl.endsWith('.jpg') ||
        cleanUrl.endsWith('.jpeg') ||
        (existingUrl != null && existingUrl.startsWith('data:image'));

    return GestureDetector(
      onTap: hasFile
          ? () {
              if (bytes != null) {
                final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
                _viewDocument(dataUrl, true, label);
              } else if (existingUrl != null && existingUrl.isNotEmpty) {
                _viewDocument(existingUrl, isImage, label);
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
                    Container(
                      color: Colors.white,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.picture_as_pdf,
                            color: Color(0xFFE53935),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              fileName ?? 'pdf_document'.tr(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (bytes != null)
                    Image.memory(bytes, fit: BoxFit.cover)
                  else if (existingUrl != null &&
                      existingUrl.startsWith('http'))
                    CachedNetworkImage(
                      imageUrl: existingUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          _buildIdPlaceholder(label, hasFile),
                    )
                  else if (existingUrl != null &&
                      existingUrl.startsWith('data:image'))
                    Image.memory(
                      base64Decode(existingUrl.split(',').last),
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
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
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
          ),
          GestureDetector(
            onTap: () => _pickFile('cv'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCvPreview() {
    final cvUrl = _existingCv;
    final lowerUrl = cvUrl?.toLowerCase() ?? '';
    final cvNameLower = (_cvName ?? '').toLowerCase();
    final isPdf =
        cvNameLower.endsWith('.pdf') ||
        lowerUrl.endsWith('.pdf') ||
        lowerUrl.contains('application/pdf') ||
        lowerUrl.contains('/cvs/');
    final isImage =
        cvNameLower.endsWith('.png') ||
        cvNameLower.endsWith('.jpg') ||
        cvNameLower.endsWith('.jpeg') ||
        lowerUrl.endsWith('.png') ||
        lowerUrl.endsWith('.jpg') ||
        lowerUrl.endsWith('.jpeg') ||
        lowerUrl.contains('image/');
    final isDoc = cvNameLower.endsWith('.doc') || cvNameLower.endsWith('.docx');

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
            top: 8,
            bottom: 8,
            left: 50,
            right: 50,
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
                        ? Image.memory(_cvBytes!, fit: BoxFit.cover)
                        : (cvUrl != null && cvUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: cvUrl,
                                  fit: BoxFit.cover,
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
                  ? PdfPagePreview(cvBytes: _cvBytes, existingCvUrl: cvUrl)
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
        ],
      ),
    );
  }
}

class _FullScreenDocumentViewer extends StatefulWidget {
  final String url;
  final String label;
  final bool isImage;

  const _FullScreenDocumentViewer({
    required this.url,
    required this.label,
    required this.isImage,
  });

  @override
  State<_FullScreenDocumentViewer> createState() =>
      _FullScreenDocumentViewerState();
}

class _FullScreenDocumentViewerState extends State<_FullScreenDocumentViewer> {
  Uint8List _base64ToBytes(String dataUrl) {
    try {
      final base64 = dataUrl.split(',').last;
      return base64Decode(base64);
    } catch (_) {
      return Uint8List(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final previewWidth = (size.width * 0.80).clamp(380.0, 800.0);
    final previewHeight = previewWidth * 0.62;
    final failedToLoadText = 'failed_to_load'.tr();

    final content = Container(
      width: previewWidth,
      height: previewHeight,
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
                    widget.label,
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
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(14),
              ),
              child: widget.isImage
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: widget.url.startsWith('data:')
                          ? Image.memory(
                              _base64ToBytes(widget.url),
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            )
                          : CachedNetworkImage(
                              imageUrl: widget.url,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (c, u) => const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF0247C4),
                                ),
                              ),
                              errorWidget: (c, u, e) => Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(height: 250),
                                  Icon(
                                    Icons.broken_image,
                                    size: 48,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    failedToLoadText,
                                    style: TextStyle(color: Color(0xFF9E9E9E)),
                                  ),
                                ],
                              ),
                            ),
                    )
                  : Center(
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
                              widget.url.split('/').last,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 14,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0247C4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'close'.tr(),
                                style: TextStyle(
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
