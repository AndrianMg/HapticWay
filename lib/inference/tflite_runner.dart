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
  // YOLOv8n output: [1, 4+N_classes, 2100] — single tensor, raw predictions before NMS.
  // NMS is applied in Postprocess.parseYolo().
  List<Detection> run(Uint8List rgbInput) {
    if (!_ready || _interpreter == null) return [];

    final outputTensor = _interpreter!.getOutputTensor(0);
    final outShape = outputTensor.shape; // [1, rows, anchors]
    final rows = outShape[1];
    final anchors = outShape[2];

    final rawOutput = List.generate(
      1, (_) => List.generate(rows, (_) => List<double>.filled(anchors, 0.0)),
    );

    try {
      _interpreter!.run(rgbInput, rawOutput);
    } catch (_) {
      return [];
    }

    return Postprocess.parseYolo(
      raw: rawOutput[0],   // [rows, anchors] — rows = 4 + numClasses
      labels: _labels,
    );
  }

  void close() {
    _interpreter?.close();
    _ready = false;
  }
}
