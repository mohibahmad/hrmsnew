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
  int _index = 0;

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
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            border: Border(
              bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Workforce',
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
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40.0,
                    vertical: 22.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFFFF),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFEEEEEE),
                                ),
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
                                        hintText: 'Search workers...',
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
                      ..._filteredWorkers.map(
                        (worker) => _buildWorkerCard(worker),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWorkerCard(Map<String, dynamic> worker) {
    final name = (worker['name'] ?? 'Unknown').toString();
    final position = (worker['position'] ?? '').toString();
    final email = (worker['email'] ?? '').toString();

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
            ClipOval(
              child: SizedBox(
                width: 48,
                height: 48,
                child: Image(
                  image: getProfileImage(
                    worker['profileImage']?.toString(),
                    email,
                    _index++,
                  ),
                  fit: BoxFit.cover,
                ),
              ),
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
                      'Edit Documents',
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EditDocumentsPage(
          worker: worker,
          onDocumentsUpdated: () {
            setState(() {});
          },
          onNotificationTap: widget.onNotificationTap,
          onProfileTap: widget.onProfileTap,
        ),
      ),
    );
  }
}

class _EditDocumentsPage extends StatefulWidget {
  final Map<String, dynamic> worker;
  final VoidCallback onDocumentsUpdated;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;

  const _EditDocumentsPage({
    required this.worker,
    required this.onDocumentsUpdated,
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

  String? get _existingFrontId => widget.worker['frontId']?.toString();
  String? get _existingBackId => widget.worker['backId']?.toString();
  String? get _existingCv => widget.worker['cv']?.toString();
  String get _workerId => widget.worker['id'] ?? '';
  String get _workerName => (widget.worker['name'] ?? 'Unknown').toString();

  Future<void> _pickFile(String field) async {
    final result = await FilePicker.pickFiles(
      type: field == 'cv' ? FileType.custom : FileType.image,
      allowedExtensions: field == 'cv'
          ? ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg']
          : null,
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
        await FirestoreService().updateWorker(_workerId, {field: url});
        widget.worker[field] = url;
        widget.onDocumentsUpdated();
        if (mounted) {
          FlashySnackBar.show(
            context,
            message:
                '$_workerName ${field == 'frontId'
                    ? "CNIC Front"
                    : field == 'backId'
                    ? "CNIC Back"
                    : "CV"} updated',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(
          context,
          message: 'Upload failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _viewDocument(String? url, bool isImage, String label) {
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _FullScreenDocumentViewer(url: url, label: label, isImage: isImage),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(94),
        child: Container(
          height: 94,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFFFF),
            border: Border(
              bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF333333)),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Text(
                _workerName,
                style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'SF Pro Display',
                ),
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
      ),
      body: SingleChildScrollView(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Side: ID Card Upload
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'id_card_label'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
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
                            Text(
                              'upload_front_side'.tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamily: 'SF Pro Display',
                              ),
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
                            Text(
                              'upload_back_side'.tr(),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                fontFamily: 'SF Pro Display',
                              ),
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
                // Right Side: CV Upload
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'upload_cv_label'.tr(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      const SizedBox(height: 16),
                      _isCvUploaded ||
                              (_existingCv != null && _existingCv!.isNotEmpty)
                          ? _buildCvPreview()
                          : _buildCvUpload(),
                    ],
                  ),
                ),
              ],
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
    final bool isPdf =
        (fileName != null && fileName.toLowerCase().endsWith('.pdf')) ||
        (existingUrl != null && existingUrl.toLowerCase().endsWith('.pdf'));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 300,
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
        Icon(
          Icons.badge,
          size: 48,
          color: hasFile ? const Color(0xFF0B50C3) : Colors.grey.shade400,
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
      height: 596,
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
              imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
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
    final isPdf = cvUrl != null && cvUrl.toLowerCase().endsWith('.pdf');
    final isImage =
        cvUrl != null &&
        (cvUrl.toLowerCase().endsWith('.png') ||
            cvUrl.toLowerCase().endsWith('.jpg') ||
            cvUrl.toLowerCase().endsWith('.jpeg'));

    return Container(
      height: 700,
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
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.picture_as_pdf,
                            color: Color(0xFFE53935),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _cvName ?? 'CV/Resume',
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
                            'CV/Resume',
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
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'edit'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/edit_icon.svg',
                          height: 18,
                          width: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _cvBytes = null;
                      _cvName = null;
                      _isCvUploaded = false;
                    });
                    if (_workerId.isNotEmpty) {
                      FirestoreService().updateWorker(_workerId, {'cv': ''});
                      widget.worker['cv'] = '';
                      widget.onDocumentsUpdated();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'delete'.tr(),
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),
                        const SizedBox(width: 8),
                        SvgPicture.asset(
                          'assets/delete_icon.svg',
                          height: 18,
                          width: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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

class _FullScreenDocumentViewerState extends State<_FullScreenDocumentViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutBack,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

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
    return Dialog(
      backgroundColor: const Color(0xFF0F0F1A),
      insetPadding: const EdgeInsets.all(16),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Color(0xFFFFFFFF),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A3E), height: 1),
            Expanded(
              child: widget.isImage
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Center(
                        child: widget.url.startsWith('data:')
                            ? Image.memory(
                                _base64ToBytes(widget.url),
                                fit: BoxFit.contain,
                              )
                            : CachedNetworkImage(
                                imageUrl: widget.url,
                                fit: BoxFit.contain,
                                placeholder: (c, u) => const Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFFFFFFFF),
                                  ),
                                ),
                                errorWidget: (c, u, e) => const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      size: 48,
                                      color: Color(0xFFFFFFFF),
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      'Failed to load',
                                      style: TextStyle(
                                        color: Color(0xFFFFFFFF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.picture_as_pdf,
                            size: 72,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.url.split('/').last,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 14,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          const SizedBox(height: 20),
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
                              child: const Text(
                                'Close',
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
          ],
        ),
      ),
    );
  }
}
