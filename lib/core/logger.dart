import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// JSONL benchmark logger — gated behind kDebugMode.
// Entries contain only timing + class labels + bbox geometry — never frames, never PII.
class BenchmarkLogger {
  static IOSink? _sink;
  static DateTime? _sessionStart;

  static Future<void> openSession() async {
    if (!kDebugMode) return;
    _sessionStart = DateTime.now();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = _sessionStart!.toIso8601String().replaceAll(':', '-').substring(0, 19);
    final file = File('${dir.path}/hapticway_bench_$stamp.jsonl');
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _log({'event': 'session_start', 'ts': _sessionStart!.millisecondsSinceEpoch});
  }

  static void logFrame({
    required int captureTs,
    required int preprocessTs,
    required int inferTs,
    required int postprocessTs,
    required List<String> labels,
  }) {
    if (!kDebugMode || _sink == null) return;
    _log({
      'event': 'frame',
      'capture_ts': captureTs,
      'preprocess_ts': preprocessTs,
      'infer_ts': inferTs,
      'postprocess_ts': postprocessTs,
      'preprocess_ms': preprocessTs - captureTs,
      'infer_ms': inferTs - preprocessTs,
      'postprocess_ms': postprocessTs - inferTs,
      'total_ms': postprocessTs - captureTs,
      'labels': labels,
    });
  }

  static Future<void> closeSession() async {
    if (!kDebugMode || _sink == null) return;
    _log({'event': 'session_end', 'ts': DateTime.now().millisecondsSinceEpoch});
    await _sink!.flush();
    await _sink!.close();
    _sink = null;
  }

  static void _log(Map<String, dynamic> entry) {
    _sink?.writeln(jsonEncode(entry));
  }
}
