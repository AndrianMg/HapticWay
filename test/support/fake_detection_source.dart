import 'dart:async';

import 'package:hapticway/benchmark/timing_data.dart';
import 'package:hapticway/inference/camera_isolate.dart';
import 'package:hapticway/inference/detection.dart';

/// Test double for [DetectionSource] — lets a test push detection/timing
/// events on demand without ever spawning a real background isolate.
///
/// Unlike the real [CameraIsolate] (fresh instance per pipeline start), the
/// same fake instance is reused across pause/resume cycles in widget tests,
/// so [start] recreates the stream controllers if a previous [stop] closed
/// them.
class FakeDetectionSource implements DetectionSource {
  var _detectionController = StreamController<List<Detection>>.broadcast();
  var _timingController = StreamController<TimingData>.broadcast();

  bool started = false;
  bool stopped = false;
  int startCount = 0;

  @override
  Stream<List<Detection>> get detections => _detectionController.stream;

  @override
  Stream<TimingData> get timing => _timingController.stream;

  @override
  Future<void> start() async {
    if (_detectionController.isClosed) {
      _detectionController = StreamController<List<Detection>>.broadcast();
      _timingController = StreamController<TimingData>.broadcast();
    }
    started = true;
    stopped = false;
    startCount++;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await _detectionController.close();
    await _timingController.close();
  }

  void addDetections(List<Detection> detections) =>
      _detectionController.add(detections);

  void addTiming(TimingData data) => _timingController.add(data);

  void addDetectionError(Object error) =>
      _detectionController.addError(error);
}
