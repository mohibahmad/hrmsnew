import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide GestureDetector;
import '../widgets/clickable_gesture_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
                child: _UserAvatar(index: _index++),
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DocumentDialog(
        worker: worker,
        onDocumentsUpdated: () {
          setState(() {});
        },
      ),
    );
  }
}

class _DocumentDialog extends StatefulWidget {
  final Map<String, dynamic> worker;
  final VoidCallback onDocumentsUpdated;

  const _DocumentDialog({
    required this.worker,
    required this.onDocumentsUpdated,
  });

  @override
  State<_DocumentDialog> createState() => _DocumentDialogState();
}

class _DocumentDialogState extends State<_DocumentDialog>
    with SingleTickerProviderStateMixin {
  bool _isUploading = false;
  late final AnimationController _animController;
  late final Animation<double> _fadeSlide;

  String? get _frontId => widget.worker['frontId']?.toString();
  String? get _backId => widget.worker['backId']?.toString();
  String? get _cv => widget.worker['cv']?.toString();
  String get _workerId => widget.worker['id'] ?? '';
  String get _workerName => (widget.worker['name'] ?? 'Unknown').toString();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeSlide = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutQuint,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUpload(String field) async {
    final result = await FilePicker.pickFiles(
      type: field == 'cv'
          ? FileType.custom
          : FileType.image,
      allowedExtensions: field == 'cv' ? ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'] : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _isUploading = true);

    try {
      final fileName = file.name;
      final bytes = file.bytes!;
      final isImage = field != 'cv';

      String? url;
      final isGuest = AuthService().currentUser?.isAnonymous ?? false;

      if (isGuest) {
        url = 'data:${isImage ? 'image/jpeg' : 'application/pdf'};base64,${base64Encode(bytes)}';
      } else {
        final folder = field == 'frontId' ? 'front_ids' : field == 'backId' ? 'back_ids' : 'cvs';
        final results = await UploadService.uploadFiles(
          files: [
            UploadFile(
              folder: folder,
              fileName: fileName,
              bytes: bytes,
              mimeType: isImage ? 'image/jpeg' : 'application/pdf',
            ),
          ],
        );
        if (results.isNotEmpty && results.first.isSuccess) {
          url = results.first.url;
        }
      }

      if (url != null && url.isNotEmpty) {
        await FirestoreService().updateWorker(_workerId, {field: url});
        widget.worker[field] = url;
        widget.onDocumentsUpdated();
        if (mounted) {
          FlashySnackBar.show(
            context,
            message: '$_workerName ${field == 'frontId' ? "CNIC Front" : field == 'backId' ? "CNIC Back" : "CV"} updated',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FlashySnackBar.show(context, message: 'Upload failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _viewDocument(String? url, bool isImage, String label) {
    if (url == null || url.isEmpty) return;
    Navigator.of(context).pop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _FullScreenDocumentViewer(
        url: url,
        label: label,
        isImage: isImage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      child: FadeTransition(
        opacity: _fadeSlide,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(_fadeSlide),
          child: Container(
            width: 620,
            constraints: const BoxConstraints(maxHeight: 620),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0247C4).withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image(
                            image: getProfileImage(
                              widget.worker['profileImage']?.toString(),
                              widget.worker['email']?.toString(),
                              0,
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _workerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'SF Pro Display',
                                color: Color(0xFF000000),
                              ),
                            ),
                            Text(
                              (widget.worker['position'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close, size: 18, color: Color(0xFF999999)),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDocCard(
                          icon: Icons.badge_outlined,
                          label: 'CNIC Front',
                          url: _frontId,
                          isImage: true,
                          field: 'frontId',
                          color: const Color(0xFF0247C4),
                        ),
                        const SizedBox(height: 14),
                        _buildDocCard(
                          icon: Icons.badge_outlined,
                          label: 'CNIC Back',
                          url: _backId,
                          isImage: true,
                          field: 'backId',
                          color: const Color(0xFF7C3AED),
                        ),
                        const SizedBox(height: 14),
                        _buildDocCard(
                          icon: Icons.description_outlined,
                          label: 'CV / Resume',
                          url: _cv,
                          isImage: false,
                          field: 'cv',
                          color: const Color(0xFF0891B2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocCard({
    required IconData icon,
    required String label,
    String? url,
    required bool isImage,
    required String field,
    required Color color,
  }) {
    final hasDoc = url != null && url.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasDoc ? color.withValues(alpha: 0.25) : const Color(0xFFE8E8E8),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: hasDoc ? () => _viewDocument(url, isImage, label) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: hasDoc ? 0.1 : 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    hasDoc ? Icons.check_circle : icon,
                    size: 22,
                    color: hasDoc ? color : const Color(0xFFBDBDBD),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SF Pro Display',
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDoc ? 'Uploaded' : 'Not uploaded',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: hasDoc ? color : const Color(0xFFEF4444),
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasDoc)
                  GestureDetector(
                    onTap: _isUploading ? null : () => _viewDocument(url, isImage, label),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.remove_red_eye, size: 18, color: color),
                    ),
                  ),
                if (hasDoc) const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isUploading ? null : () => _pickAndUpload(field),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _isUploading
                          ? Colors.grey[200]
                          : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            hasDoc ? Icons.edit_outlined : Icons.cloud_upload_outlined,
                            size: 18,
                            color: _isUploading ? Colors.grey : color,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
  State<_FullScreenDocumentViewer> createState() => _FullScreenDocumentViewerState();
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
    _scaleAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutBack);
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      child: const Icon(Icons.close, color: Color(0xFFFFFFFF), size: 20),
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
                                  child: CircularProgressIndicator(color: Color(0xFFFFFFFF)),
                                ),
                                errorWidget: (c, u, e) => const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image, size: 48, color: Color(0xFFFFFFFF)),
                                    SizedBox(height: 12),
                                    Text('Failed to load', style: TextStyle(color: Color(0xFFFFFFFF))),
                                  ],
                                ),
                              ),
                      ),
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.picture_as_pdf, size: 72, color: Color(0xFFEF4444)),
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
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
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

class _UserAvatar extends StatelessWidget {
  final int index;
  const _UserAvatar({required this.index});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFEEEEEE), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image(
            image: getProfileImage(
              AuthService.profilePicNotifier.value,
              AuthService().currentUser?.email,
              index,
            ),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
