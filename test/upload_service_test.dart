import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/upload_service.dart';

void main() {
  test(
    'remote media link is downloaded and prepared for Firebase upload',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(const [1, 2, 3, 4]);
        await request.response.close();
      });

      final file = await UploadService.downloadRemoteFile(
        url: 'http://${server.address.host}:${server.port}/worker-photo.png',
        folder: 'profile_images',
        fallbackFileName: 'profile.jpg',
        fallbackMimeType: 'image/jpeg',
      );

      expect(file.folder, 'profile_images');
      expect(file.fileName, 'worker-photo.png');
      expect(file.mimeType, 'image/png');
      expect(file.bytes, const [1, 2, 3, 4]);
    },
  );

  test('remote media download rejects non-http URLs', () async {
    expect(
      () => UploadService.downloadRemoteFile(
        url: 'file:///tmp/worker-photo.png',
        folder: 'profile_images',
        fallbackFileName: 'profile.jpg',
        fallbackMimeType: 'image/jpeg',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('actual PNG bytes override an incorrect server content type', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.add(const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
      ]);
      await request.response.close();
    });

    final file = await UploadService.downloadRemoteFile(
      url: 'http://${server.address.host}:${server.port}/photo',
      folder: 'profile_images',
      fallbackFileName: 'profile.png',
      fallbackMimeType: 'image/jpeg',
    );

    expect(file.mimeType, 'image/png');
  });
}
