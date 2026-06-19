import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

final _base64Cache = <String, Uint8List>{};

ImageProvider getProfileImage(String? url, String? email, int index) {
  final currentUser = AuthService().currentUser;
  if (email != null && currentUser != null && email.toLowerCase() == currentUser.email?.toLowerCase()) {
    final notifierUrl = AuthService.profilePicNotifier.value;
    if (notifierUrl != null && notifierUrl.isNotEmpty) {
      if (notifierUrl.startsWith('http')) {
        return NetworkImage(notifierUrl);
      }
      if (notifierUrl.startsWith('data:image/')) {
        return MemoryImage(_decodeBase64(notifierUrl));
      }
      return FileImage(File(notifierUrl));
    }
  }

  if (url == null || url.isEmpty) {
    return AssetImage(
      index % 2 == 0 ? 'assets/profileimage.png' : 'assets/boy.png',
    );
  }
  if (url.startsWith('data:image/')) {
    return MemoryImage(_decodeBase64(url));
  }
  if (url.startsWith('http')) {
    return NetworkImage(url);
  }
  return AssetImage(url);
}

Uint8List _decodeBase64(String url) {
  final cached = _base64Cache[url];
  if (cached != null) return cached;
  final base64Content = url.split(',').last;
  final bytes = base64Decode(base64Content);
  _base64Cache[url] = bytes;
  return bytes;
}
