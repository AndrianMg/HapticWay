import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detection.dart';
import 'frame_preprocessor.dart';
import 'postprocess.dart';

class TfliteRunner {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _ready = false;
  bool _outputTransposed = false; // true when output is [1, anchors, rows]
  bool _inputIsFloat = false;    // Ultralytics INT8 export keeps float32 input
  bool _inputIsNchw  = false;    // true when input is [1, 3, H, W] (channel-first)
  int  _inH = 0, _inW = 0;

  bool get isReady => _ready;

  void initializeFromBuffer(Uint8List modelBytes, List<String> labels) {
    _labels = labels;
    // YOLOv8 custom ops are not supported by NNAPI — run on CPU threads only.
    final options = InterpreterOptions()..threads = 4;
    try {
      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter!.allocateTensors();

      final inTensor  = _interpreter!.getInputTensor(0);
      final inShape   = inTensor.shape;   // [1, H, W, 3] or [1, 3, H, W]
      final outShape  = _interpreter!.getOutputTensor(0).shape;
      _inputIsFloat   = inTensor.type == TensorType.float32;

      // Detect NCHW [1, 3, H, W] vs NHWC [1, H, W, 3] by checking dim 1.
      // C=3 in dim 1 → NCHW; C=3 in dim 3 → NHWC.
      _inputIsNchw = inShape.length == 4 && inShape[1] == 3;
      _inH = _inputIsNchw ? inShape[2] : inShape[1];
      _inW = _inputIsNchw ? inShape[3] : inShape[2];

      // YOLOv8 output is either [1, 4+N, anchors] or [1, anchors, 4+N].
      // For imgsz=320, anchors=2100 >> 4+N (≤12), so the larger dim is anchors.
      _outputTransposed = outShape[1] > outShape[2];
      _ready = true;

      debugPrint(
        'TFLite: ready  in=$inShape(${inTensor.type.name})'
        '  nchw=$_inputIsNchw  out=$outShape  transposed=$_outputTransposed',
      );
    } catch (e) {
      _ready = false;
      debugPrint('TFLite: init failed: $e');
    }
  }

  List<Detection> run(LetterboxResult input) {
    if (!_ready || _interpreter == null) return [];

    final rgbInput = input.tensor;

    final outShape = _interpreter!.getOutputTensor(0).shape;
    final dim1 = outShape[1];
    final dim2 = outShape[2];

    // Use flat ByteBuffer I/O — the fast path in tflite_flutter that avoids
    // the slow nested-list recursion in the generic copyTo path.
    final outFlat = Float32List(dim1 * dim2);

    // Build the input ByteBuffer in the format the model expects.
    // rgbInput is always HWC (row-major R,G,B per pixel from FramePreprocessor).
    final Object inputBuffer;
    if (_inputIsFloat) {
      final inFloat = Float32List(rgbInput.length);
      if (_inputIsNchw) {
        // NCHW [1, 3, H, W]: write all R, then all G, then all B.
        final hw = _inH * _inW;
        for (int r = 0; r < _inH; r++) {
          for (int c = 0; c < _inW; c++) {
            final src = (r * _inW + c) * 3;
            final dst = r * _inW + c;
            inFloat[dst]          = rgbInput[src]     / 255.0; // R plane
            inFloat[hw + dst]     = rgbInput[src + 1] / 255.0; // G plane
            inFloat[2 * hw + dst] = rgbInput[src + 2] / 255.0; // B plane
          }
        }
      } else {
        // NHWC [1, H, W, 3]: HWC order matches directly.
        for (int i = 0; i < rgbInput.length; i++) {
          inFloat[i] = rgbInput[i] / 255.0;
        }
      }
      inputBuffer = inFloat.buffer;
    } else {
      // Fully-quantised uint8 input: pass raw bytes directly.
      // For NCHW uint8 we'd need to transpose too, but all known Ultralytics
      // uint8 exports are NHWC, so skip that complexity for now.
      inputBuffer = rgbInput.buffer;
    }

    try {
      _interpreter!.runForMultipleInputs(
        [inputBuffer],
        {0: outFlat.buffer},
      );
    } catch (e) {
      debugPrint('TFLite: inference error: $e');
      return [];
    }

    // Build raw2d[rows][anchors] for parseYolo.
    // outFlat layout: row-major [dim1][dim2] → outFlat[r * dim2 + a].
    final List<List<double>> raw2d;
    if (_outputTransposed) {
      // Tensor is [1, anchors, rows] → transpose to [rows][anchors].
      final anchors = dim1;
      final rows    = dim2;
      raw2d = List.generate(
        rows, (r) => List.generate(anchors, (a) => outFlat[a * rows + r].toDouble()),
      );
    } else {
      raw2d = List.generate(
        dim1, (r) => List.generate(dim2, (a) => outFlat[r * dim2 + a].toDouble()),
      );
    }

    return Postprocess.parseYolo(
      raw: raw2d,
      labels: _labels,
      scale: input.scale,
      padX: input.padX,
      padY: input.padY,
      frameW: input.frameW,
      frameH: input.frameH,
      modelSize: FramePreprocessor.modelSize,
    );
  }

  void close() {
    _interpreter?.close();
    _ready = false;
  }
}
