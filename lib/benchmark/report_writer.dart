import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'timing_data.dart';

class ReportWriter {
  /// Writes the per-run CSV for one benchmark session and appends per-metric
  /// summary rows (mean, SD, P50, P95, P99) to the cumulative
  /// `hapticway_bench_summary.csv` — one block per condition run (§7.3).
  static Future<String> writeCsv(
    List<TimingData> samples, {
    required String condition,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/hapticway_bench_${condition}_$ts.csv');

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
    await _appendSummary(dir.path, condition, ts, samples);
    return file.path;
  }

  /// Tidy-format summary: one row per metric per session, accumulated across
  /// sessions so all four conditions end up in a single file for the report.
  static Future<void> _appendSummary(
    String dirPath,
    String condition,
    int ts,
    List<TimingData> samples,
  ) async {
    final summary = File('$dirPath/hapticway_bench_summary.csv');
    final buf = StringBuffer();
    if (!await summary.exists()) {
      buf.writeln('condition,timestamp,metric,n,mean_ms,sd_ms,p50_ms,p95_ms,p99_ms');
    }
    final metrics = <String, List<int>>{
      'preprocess': samples.map((s) => s.preprocessMs).toList(),
      'infer': samples.map((s) => s.inferMs).toList(),
      'total': samples.map((s) => s.totalMs).toList(),
    };
    metrics.forEach((name, values) {
      buf.writeln('$condition,$ts,$name,${values.length},'
          '${_mean(values).toStringAsFixed(1)},'
          '${_sd(values).toStringAsFixed(1)},'
          '${_pct(values, 50)},${_pct(values, 95)},${_pct(values, 99)}');
    });
    await summary.writeAsString(buf.toString(), mode: FileMode.append);
  }

  static double _mean(List<int> values) =>
      values.reduce((a, b) => a + b) / values.length;

  static double _sd(List<int> values) {
    final m = _mean(values);
    final sumSq = values.fold<double>(0, (acc, v) => acc + (v - m) * (v - m));
    return math.sqrt(sumSq / (values.length - 1));
  }

  static int _pct(List<int> values, int percentile) {
    final sorted = [...values]..sort();
    final idx = ((percentile / 100) * (sorted.length - 1)).round();
    return sorted[idx];
  }
}
