import 'dart:typed_data';
import 'package:flutter/foundation.dart';

Uint8List _echo(Map<String, Object?> m) {
  return m['data'] as Uint8List;
}

Future<void> main() async {
  final payload = Uint8List(6 * 1024 * 1024); // 6MB font-like
  // warmup
  await compute(_echo, {'data': payload});
  const n = 100;
  final sw = Stopwatch()..start();
  var total = 0;
  for (var i = 0; i < n; i++) {
    final r = await compute(_echo, {'data': payload});
    total += r.length;
  }
  sw.stop();
  print('ISOLATE_TRANSFER_BENCH: ' + n.toString() + ' isolate calls carrying 6MB each in ' + sw.elapsedMilliseconds.toString() + 'ms');
}
