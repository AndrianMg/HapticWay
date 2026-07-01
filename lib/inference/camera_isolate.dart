import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../benchmark/timing_data.dart';
import '../depth/ar_depth_channel.dart';
import 'detection.dart';
import 'frame_preprocessor.dart';
import 'tflite_runner.dart';

/// Detection/timing stream contract implemented by [CameraIsolate]. Lets
/// tests inject a fake in place of a real background isolate.
abstract class DetectionSource {
  Stream<List<Detection>> get detections;
  Stream<TimingData> get timing;
  Future<void> start();
  Future<void> stop();
}

/// Manages a long-running background isolate that runs TFLite inference.
///
/// §6.1 change: camera frames now come from [ArDepthChannel.frameStream]
/// (ARCore EventChannel) instead of the Flutter camera plugin image stream.
/// The isolate boundary contract is unchanged — only preprocessed pixel data
/// crosses; the YUV bytes are copied once into [_FrameMsg] before sending.
class CameraIsolate implements DetectionSource {
  Isolate? _isolate;
  SendPort? _toIsolate;
  bool _busy = false;
  StreamSubscription<Map<String, dynamic>>? _frameSub;

  final _detectionController = StreamController<List<Detection>>.broadcast();
  final _timingController    = StreamController<TimingData>.broadcast();

  @override
  Stream<List<Detection>> get detections => _detectionController.stream;
  @override
  Stream<TimingData>      get timing     => _timingController.stream;

  @override
  Future<void> start() async {
    // Load model assets on the main isolate — rootBundle is unavailable
    // in background isolates (constraint established in §5.2).
    final modelData  = await rootBundle.load('assets/models/hapticway_custom.tflite');
    final modelBytes = modelData.buffer.asUint8List();
    final labelsRaw  = await rootBundle.loadString('assets/labels/hapticway_labels.txt');
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
          inferMs:      msg['infer_ms']      as int,
        ));
        _busy = false;
      }
    });

    await completer.future;

    // Subscribe to ARCore frame stream — replaces CameraController.startImageStream.
    _frameSub = ArDepthChannel.instance.frameStream.listen(_onArFrame);
  }

  void _onArFrame(Map<String, dynamic> frame) {
    if (_toIsolate == null || _busy) return;
    _busy = true;
    _toIsolate!.send(_FrameMsg(
      y:             frame['y']             as Uint8List,
      u:             frame['u']             as Uint8List,
      v:             frame['v']             as Uint8List,
      width:         frame['width']         as int,
      height:        frame['height']        as int,
      yRowStride:    frame['yRowStride']    as int,
      uvRowStride:   frame['uvRowStride']   as int,
      uvPixelStride: frame['uvPixelStride'] as int,
    ));
  }

  @override
  Future<void> stop() async {
    await _frameSub?.cancel();
    _frameSub = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _toIsolate = null;
    _busy = false;
    await _detectionController.close();
    await _timingController.close();
  }
}

// ── Isolate entry ─────────────────────────────────────────────────────────────

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
  // S20 Ultra sensor orientation is 90° CW; portrait deployment always needs
  // the frame rotated 90° CW to upright before inference.
  final int rotationDegrees;
  const _FrameMsg({
    required this.y, required this.u, required this.v,
    required this.width, required this.height,
    required this.yRowStride, required this.uvRowStride,
    required this.uvPixelStride,
    this.rotationDegrees = 90,
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
      final letterboxed = FramePreprocessor.process(
        yPlane:          msg.y,
        uPlane:          msg.u,
        vPlane:          msg.v,
        width:           msg.width,
        height:          msg.height,
        yRowStride:      msg.yRowStride,
        uvRowStride:     msg.uvRowStride,
        uvPixelStride:   msg.uvPixelStride,
        rotationDegrees: msg.rotationDegrees,
      );
      final prepMs = (prepSw..stop()).elapsedMilliseconds;

      final inferSw = Stopwatch()..start();
      final detections = runner.run(letterboxed);
      final inferMs = (inferSw..stop()).elapsedMilliseconds;

      args.sendPort.send({
        'detections':    detections.map((d) => d.toMap()).toList(),
        'preprocess_ms': prepMs,
        'infer_ms':      inferMs,
      });
    }
  }
}
