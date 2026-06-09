import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'postprocess.dart';

class TfliteRunner {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;
  bool _outputTransposed = false; // true when output is [1, anchors, rows]
  bool _inputIsFloat = false;    // Ultralytics INT8 export keeps float32 input

  bool get isReady => _ready;

  void initializeFromBuffer(Uint8List modelBytes, List<String> labels) {
    _labels = labels;
    // YOLOv8 custom ops are not supported by NNAPI — run on CPU threads only.
    final options = InterpreterOptions()..threads = 4;
    try {
      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter!.allocateTensors();

      final inTensor  = _interpreter!.getInputTensor(0);
      final outShape  = _interpreter!.getOutputTensor(0).shape;
      _inputIsFloat   = inTensor.type == TensorType.float32;
      // YOLOv8 output is either [1, 4+N, anchors] or [1, anchors, 4+N].
      // For imgsz=320, anchors=2100 >> 4+N (≤12), so the larger dim is anchors.
      _outputTransposed = outShape[1] > outShape[2];
      _ready = true;

      debugPrint(
        'TFLite: ready  in=${inTensor.shape}(${inTensor.type.name})'
        '  out=$outShape  transposed=$_outputTransposed',
      );
    } catch (e) {
      _ready = false;
      debugPrint('TFLite: init failed: $e');
    }
  }

  List<Detection> run(Uint8List rgbInput) {
    if (!_ready || _interpreter == null) return [];

    final outShape = _interpreter!.getOutputTensor(0).shape;
    final dim1 = outShape[1];
    final dim2 = outShape[2];

    final rawOutput = List.generate(
      1, (_) => List.generate(dim1, (_) => List<double>.filled(dim2, 0.0)),
    );

    try {
      if (_inputIsFloat) {
        // Ultralytics INT8 export keeps float32 input despite the "INT8" label.
        // Pass raw bytes via ByteBuffer — tflite_flutter's fast path that skips
        // per-element conversion and copies the buffer directly into the tensor.
        final float32Input = Float32List(rgbInput.length);
        for (int i = 0; i < rgbInput.length; i++) {
          float32Input[i] = rgbInput[i] / 255.0;
        }
        _interpreter!.run(float32Input.buffer, rawOutput);
      } else {
        _interpreter!.run(rgbInput, rawOutput);
      }
    } catch (e) {
      debugPrint('TFLite: inference error: $e');
      return [];
    }

    // parseYolo expects [rows][anchors] where rows = 4 + numClasses.
    // If the model output is transposed ([anchors][rows]), fix it here.
    final List<List<double>> raw2d;
    if (_outputTransposed) {
      final anchors = dim1;
      final rows    = dim2;
      raw2d = List.generate(
        rows, (r) => List.generate(anchors, (a) => rawOutput[0][a][r]),
      );
    } else {
      raw2d = rawOutput[0];
    }

    return Postprocess.parseYolo(raw: raw2d, labels: _labels);
  }

  void close() {
    _interpreter?.close();
    _ready = false;
  }
}
