import 'timing_data.dart';
import 'report_writer.dart';

class BenchmarkRunner {
  static const int kSamples = 20;

  final _samples = <TimingData>[];
  bool _active = false;
  void Function(String path)? _onComplete;

  bool get isActive => _active;
  int get collected => _samples.length;

  void start({void Function(String path)? onComplete}) {
    _samples.clear();
    _active = true;
    _onComplete = onComplete;
  }

  void addSample(TimingData data) {
    if (!_active) return;
    _samples.add(data);
    if (_samples.length >= kSamples) {
      _active = false;
      ReportWriter.writeCsv(List.unmodifiable(_samples))
          .then((path) => _onComplete?.call(path));
    }
  }
}
