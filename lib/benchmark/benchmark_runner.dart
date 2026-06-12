import 'timing_data.dart';
import 'report_writer.dart';

class BenchmarkRunner {
  static const int kSamples = 20;

  final _samples = <TimingData>[];
  bool _active = false;
  String _condition = 'unspecified';
  void Function(String path)? _onComplete;

  bool get isActive => _active;
  int get collected => _samples.length;
  String get condition => _condition;

  /// [condition] tags the run for the §7.3 report grid, e.g. 'bright_empty'.
  void start({
    required String condition,
    void Function(String path)? onComplete,
  }) {
    _samples.clear();
    _active = true;
    _condition = condition;
    _onComplete = onComplete;
  }

  void addSample(TimingData data) {
    if (!_active) return;
    _samples.add(data);
    if (_samples.length >= kSamples) {
      _active = false;
      ReportWriter.writeCsv(List.unmodifiable(_samples), condition: _condition)
          .then((path) => _onComplete?.call(path));
    }
  }
}
