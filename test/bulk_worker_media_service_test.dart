import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrms/services/bulk_worker_media_service.dart';

void main() {
  test('per-cell media validation rejects an unreachable HTTP link', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final error = await validateRemoteWorkerMediaLink(
      field: 'backId',
      url: 'http://${server.address.host}:${server.port}/missing.jpg',
    );

    expect(error, isNotNull);
  });

  test('per-cell media validation rejects malformed URLs', () async {
    final error = await validateRemoteWorkerMediaLink(
      field: 'cv',
      url: 'not-a-link',
    );

    expect(error, isNotNull);
  });
}
