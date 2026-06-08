import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'postprocess.dart';

class TfliteRunner {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;

  bool get isReady => _ready;

  // Called from a background isolate — receives bytes loaded by the main isolate
  // because rootBundle and Interpreter.fromAsset() are unavailable in isolates.
  void initializeFromBuffer(Uint8List modelBytes, List<String> labels) {
    _labels = labels;
    final options = InterpreterOptions()
      ..threads = 4
      ..useNnApiForAndroid = true;
    try {
      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter!.allocateTensors();
      _ready = true;
    } catch (_) {
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
