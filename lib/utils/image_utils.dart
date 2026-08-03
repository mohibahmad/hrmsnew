import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

const int _maxCacheBytes = 50 * 1024 * 1024; // 50 MB
int _currentCacheBytes = 0;
final _base64Cache = <String, Uint8List>{};
final _cacheKeys = <String>[];

void _cleanCacheIfNeeded() {
  while (_currentCacheBytes > _maxCacheBytes && _cacheKeys.isNotEmpty) {
    final oldest = _cacheKeys.removeAt(0);
    final removed = _base64Cache.remove(oldest);
    if (removed != null) _currentCacheBytes -= removed.length;
  }
}

void _touchKey(String key) {
  _cacheKeys.remove(key);
  _cacheKeys.add(key);
}

Uint8List? _decodeBase64(String url) {
  final cached = _base64Cache[url];
  if (cached != null) {
    _touchKey(url);
    return cached;
  }
  try {
    final base64Content = url.split(',').last;
    final bytes = base64Decode(base64Content);
    if (_currentCacheBytes + bytes.length > _maxCacheBytes) {
      _cleanCacheIfNeeded();
    }
    _base64Cache[url] = bytes;
    _cacheKeys.add(url);
    _currentCacheBytes += bytes.length;
    return bytes;
  } catch (_) {
    return null;
  }
}

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
    _cleanCacheIfNeeded();
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

ImageProvider? getProfileImageOrNull(String? url) {
  if (!_isValidUrl(url)) return null;
  if (url!.startsWith('data:image/')) {
    final bytes = _decodeBase64(url);
    return bytes == null ? null : MemoryImage(bytes);
  }
  if (url.startsWith('http')) {
    return CachedNetworkImageProvider(url);
  }
  if (url.startsWith('assets/')) {
    return AssetImage(url);
  }
  if (_fileExists(url)) {
    return FileImage(File(url));
  }
  return null;
}

String workerInitial(String? name) {
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
    final initial = workerInitial(widget.name);
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
        borderRadius:
            widget.shape == BoxShape.rectangle ? widget.borderRadius : null,
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
                fontFamily: 'SF Pro Display',
              ),
            )
          : null,
    );
  }
}
