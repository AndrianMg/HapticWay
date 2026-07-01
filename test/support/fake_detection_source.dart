import 'dart:async';

import 'package:hapticway/benchmark/timing_data.dart';
import 'package:hapticway/inference/camera_isolate.dart';
import 'package:hapticway/inference/detection.dart';

/// Test double for [DetectionSource] — lets a test push detection/timing
/// events on demand without ever spawning a real background isolate.
class FakeDetectionSource implements DetectionSource {
  final _detectionController = StreamController<List<Detection>>.broadcast();
  final _timingController = StreamController<TimingData>.broadcast();

  bool started = false;
  bool stopped = false;

  @override
  Stream<List<Detection>> get detections => _detectionController.stream;

  @override
  Stream<TimingData> get timing => _timingController.stream;

  @override
  Future<void> start() async {
    started = true;
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
}
