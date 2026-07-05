import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';

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
  return url.startsWith('http') ||
      url.startsWith('data:image/') ||
      url.startsWith('/') ||
      url.startsWith('file://');
}

bool _fileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

ImageProvider getProfileImage(String? url, String? email, int index) {
  final currentUser = AuthService().currentUser;
  final isCurrentUser =
      currentUser != null &&
      !currentUser.isAnonymous &&
      currentUser.email?.toLowerCase() == email?.toLowerCase();

  if (_isValidUrl(url)) {
    if (url!.startsWith('data:image/')) {
      final bytes = _decodeBase64(url);
      if (bytes != null) {
        return MemoryImage(bytes);
      }
    }
    if (url.startsWith('http')) {
      return CachedNetworkImageProvider(url);
    }
    if (_fileExists(url)) {
      return FileImage(File(url));
    }
  }

  if (isCurrentUser) {
    final notifierUrl = AuthService.profilePicNotifier.value;
    if (_isValidUrl(notifierUrl)) {
      if (notifierUrl!.startsWith('http')) {
        return CachedNetworkImageProvider(notifierUrl);
      }
      if (notifierUrl.startsWith('data:image/')) {
        final bytes = _decodeBase64(notifierUrl);
        if (bytes != null) {
          return MemoryImage(bytes);
        }
      }
      if (_fileExists(notifierUrl)) {
        return FileImage(File(notifierUrl));
      }
    }
  }

  return AssetImage(
    index % 2 == 0 ? 'assets/profileimage.png' : 'assets/boy.png',
  );
}
