import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'timing_data.dart';

class ReportWriter {
  static Future<String> writeCsv(List<TimingData> samples) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/hapticway_bench_$ts.csv');

    final buf = StringBuffer();

    buf.writeln('run,preprocess_ms,infer_ms,total_ms');
    for (int i = 0; i < samples.length; i++) {
      final s = samples[i];
      buf.writeln('${i + 1},${s.preprocessMs},${s.inferMs},${s.totalMs}');
    }

    buf.writeln();
    buf.writeln('percentile,preprocess_ms,infer_ms,total_ms');
    for (final pct in [50, 95, 99]) {
      buf.writeln('p$pct,'
          '${_pct(samples.map((s) => s.preprocessMs).toList(), pct)},'
          '${_pct(samples.map((s) => s.inferMs).toList(), pct)},'
          '${_pct(samples.map((s) => s.totalMs).toList(), pct)}');
    }

    await file.writeAsString(buf.toString());
    return file.path;
  }

  static int _pct(List<int> values, int percentile) {
    final sorted = [...values]..sort();
    final idx = ((percentile / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }
}
