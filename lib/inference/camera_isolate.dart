import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

import '../benchmark/timing_data.dart';
import 'detection.dart';
import 'frame_preprocessor.dart';
import 'tflite_runner.dart';

// Manages a long-running background isolate that runs TFLite inference.
// The camera stream stays on the main isolate; only preprocessed pixel
// data crosses the isolate boundary — never raw frames, never images.
class CameraIsolate {
  Isolate? _isolate;
  SendPort? _toIsolate;
  bool _busy = false;

  final _detectionController =
      StreamController<List<Detection>>.broadcast();
  final _timingController =
      StreamController<TimingData>.broadcast();

  Stream<List<Detection>> get detections => _detectionController.stream;
  Stream<TimingData> get timing => _timingController.stream;

  Future<void> start() async {
    // Load assets here on the main isolate — rootBundle is unavailable in background isolates.
    final modelData = await rootBundle.load('assets/models/ssd_mobilenet_v2_int8.tflite');
    final modelBytes = modelData.buffer.asUint8List();
    final labelsRaw = await rootBundle.loadString('assets/labels/coco_labels_filtered.txt');
    final labels = labelsRaw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final fromIsolate = ReceivePort();
    final token = RootIsolateToken.instance!;

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateArgs(token, fromIsolate.sendPort, modelBytes, labels),
    );

    final completer = Completer<void>();

    fromIsolate.listen((msg) {
      if (msg == _IsolateCmd.ready) {
        completer.complete();
      } else if (msg is SendPort) {
        _toIsolate = msg;
      } else if (msg is Map) {
        final detections = (msg['detections'] as List)
            .map((m) => Detection.fromMap(Map<String, dynamic>.from(m as Map)))
            .toList();
        _detectionController.add(detections);
        _timingController.add(TimingData(
          preprocessMs: msg['preprocess_ms'] as int,
          inferMs: msg['infer_ms'] as int,
        ));
        _busy = false;
      }
    });

    await completer.future;
  }

  // Called from the camera image stream callback on the main isolate.
  // Drops the frame silently if inference is still running.
  void processFrame(CameraImage image) {
    if (_toIsolate == null || _busy) return;
    if (image.planes.length < 3) return;

    _busy = true;
    _toIsolate!.send(_FrameMsg(
      y: Uint8List.fromList(image.planes[0].bytes),
      u: Uint8List.fromList(image.planes[1].bytes),
      v: Uint8List.fromList(image.planes[2].bytes),
      width: image.width,
      height: image.height,
      yRowStride: image.planes[0].bytesPerRow,
      uvRowStride: image.planes[1].bytesPerRow,
      uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
    ));
  }

  Future<void> stop() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    _busy = false;
    await _detectionController.close();
    await _timingController.close();
  }
}

// ── Isolate entry ──────────────────────────────────────────────────────────

class _IsolateArgs {
  final RootIsolateToken token;
  final SendPort sendPort;
  final Uint8List modelBytes;
  final List<String> labels;
  _IsolateArgs(this.token, this.sendPort, this.modelBytes, this.labels);
}

class _FrameMsg {
  final Uint8List y, u, v;
  final int width, height, yRowStride, uvRowStride, uvPixelStride;
  const _FrameMsg({
    required this.y, required this.u, required this.v,
    required this.width, required this.height,
    required this.yRowStride, required this.uvRowStride,
    required this.uvPixelStride,
  });
}

enum _IsolateCmd { ready }

@pragma('vm:entry-point')
Future<void> _isolateEntry(_IsolateArgs args) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);

  final fromMain = ReceivePort();
  args.sendPort.send(fromMain.sendPort);

  final runner = TfliteRunner();
  runner.initializeFromBuffer(args.modelBytes, args.labels);
  args.sendPort.send(_IsolateCmd.ready);

  await for (final msg in fromMain) {
    if (msg is _FrameMsg) {
      if (!runner.isReady) {
        args.sendPort.send({'detections': <Map>[], 'preprocess_ms': 0, 'infer_ms': 0});
        continue;
      }

      final prepSw = Stopwatch()..start();
      final rgb = FramePreprocessor.process(
        yPlane: msg.y,
        uPlane: msg.u,
        vPlane: msg.v,
        width: msg.width,
        height: msg.height,
        yRowStride: msg.yRowStride,
        uvRowStride: msg.uvRowStride,
        uvPixelStride: msg.uvPixelStride,
      );
      final prepMs = (prepSw..stop()).elapsedMilliseconds;

      final inferSw = Stopwatch()..start();
      final detections = runner.run(rgb);
      final inferMs = (inferSw..stop()).elapsedMilliseconds;

      args.sendPort.send({
        'detections': detections.map((d) => d.toMap()).toList(),
        'preprocess_ms': prepMs,
        'infer_ms': inferMs,
      });
    }
  }
}
