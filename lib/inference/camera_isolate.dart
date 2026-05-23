import 'dart:async';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

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

  Stream<List<Detection>> get detections => _detectionController.stream;

  Future<void> start() async {
    final fromIsolate = ReceivePort();
    final token = RootIsolateToken.instance!;

    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateArgs(token, fromIsolate.sendPort),
    );

    final completer = Completer<void>();

    fromIsolate.listen((msg) {
      if (msg is SendPort) {
        _toIsolate = msg;
        _toIsolate!.send(_IsolateCmd.init);
      } else if (msg == _IsolateCmd.ready) {
        completer.complete();
      } else if (msg is List) {
        final detections =
            msg.map((m) => Detection.fromMap(Map<String, dynamic>.from(m as Map))).toList();
        _detectionController.add(detections);
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
  }
}

// ── Isolate entry ──────────────────────────────────────────────────────────

class _IsolateArgs {
  final RootIsolateToken token;
  final SendPort sendPort;
  const _IsolateArgs(this.token, this.sendPort);
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

enum _IsolateCmd { init, ready }

@pragma('vm:entry-point')
Future<void> _isolateEntry(_IsolateArgs args) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(args.token);

  final fromMain = ReceivePort();
  args.sendPort.send(fromMain.sendPort);

  final runner = TfliteRunner();

  await for (final msg in fromMain) {
    if (msg == _IsolateCmd.init) {
      await runner.initialize();
      args.sendPort.send(_IsolateCmd.ready);
    } else if (msg is _FrameMsg) {
      if (!runner.isReady) {
        args.sendPort.send(<Map>[]);
        continue;
      }
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
      final detections = runner.run(rgb);
      args.sendPort.send(detections.map((d) => d.toMap()).toList());
    }
  }
}
