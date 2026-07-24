import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

const int _maxCacheEntries = 50;
final _base64Cache = <String, Uint8List>{};
final _cacheKeys = <String>[];

void _cleanCacheIfNeeded() {
  while (_cacheKeys.length > _maxCacheEntries) {
    final oldest = _cacheKeys.removeAt(0);
    _base64Cache.remove(oldest);
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
    if (_base64Cache.length >= _maxCacheEntries) {
      _cleanCacheIfNeeded();
    }
    _base64Cache[url] = bytes;
    _cacheKeys.add(url);
    return bytes;
  } catch (_) {
    return null;
  }
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

class WorkerAvatar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final image = getProfileImageOrNull(imageUrl);
    final initial = workerInitial(name);
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
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColors[colorIndex],
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
        border: border,
        image: image == null
            ? null
            : DecorationImage(image: image, fit: BoxFit.cover),
      ),
      child: image == null
          ? Text(
              initial,
              style: TextStyle(
                color: foregroundColors[colorIndex],
                fontSize: size * 0.4,
                fontWeight: FontWeight.w800,
                fontFamily: 'SF Pro Display',
              ),
            )
          : null,
    );
  }
}
