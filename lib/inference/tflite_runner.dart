import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'postprocess.dart';

class TfliteRunner {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;

  bool get isReady => _ready;

  Future<void> initialize() async {
    await _loadLabels();
    await _loadInterpreter();
  }

  Future<void> _loadLabels() async {
    try {
      final raw = await rootBundle.loadString('assets/labels/coco_labels_filtered.txt');
      _labels = raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (e) {
      // Labels missing — detection will produce no results.
    }
  }

  Future<void> _loadInterpreter() async {
    // useNnApiForAndroid enables the NNAPI accelerator (API 27+) with CPU fallback.
    final options = InterpreterOptions()
      ..threads = 4
      ..useNnApiForAndroid = true;

    try {
      _interpreter = await Interpreter.fromAsset(
        'models/ssd_mobilenet_v2_int8.tflite',
        options: options,
      );
      _interpreter!.allocateTensors();
      _ready = true;
    } catch (e) {
      // Model file not yet present — place it at assets/models/ssd_mobilenet_v2_int8.tflite
      _ready = false;
    }
  }

  // Returns an empty list if the model is not ready.
  List<Detection> run(Uint8List rgbFrame300x300) {
    if (!_ready || _interpreter == null) return [];

    // Output buffers — SSD MobileNet v2 produces max 10 detections.
    const maxDet = 10;
    final outBoxes =
        List.generate(1, (_) => List.generate(maxDet, (_) => List<double>.filled(4, 0.0)));
    final outClasses = List.generate(1, (_) => List<double>.filled(maxDet, 0.0));
    final outScores = List.generate(1, (_) => List<double>.filled(maxDet, 0.0));
    final outCount = List<double>.filled(1, 0.0);

    try {
      _interpreter!.runForMultipleInputs(
        [rgbFrame300x300],
        {0: outBoxes, 1: outClasses, 2: outScores, 3: outCount},
      );
    } catch (_) {
      return [];
    }

    return Postprocess.parse(
      boxes: outBoxes[0],
      classes: outClasses[0],
      scores: outScores[0],
      count: outCount[0].round(),
      labels: _labels,
    );
  }

  void close() {
    _interpreter?.close();
    _ready = false;
  }
}
