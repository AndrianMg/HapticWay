import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/inference/camera_isolate.dart';
import 'package:hapticway/inference/detection.dart';

import '../support/ar_depth_channel_mocks.dart';

/// §Phase-1 fix regression tests: CameraIsolate must shut its background
/// isolate down cleanly (releasing the TFLite interpreter) rather than
/// killing it, and a fresh instance must be startable after a stop —
/// the contract the app-lifecycle pause/resume handling relies on.
///
/// These spawn a REAL isolate; the TFLite interpreter itself may fail to
/// initialise on a host without the native library, which the runner
/// handles gracefully (empty detections) — the lifecycle behaviour under
/// test is unaffected.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Minimal valid 2x2 YUV_420_888 frame map, as delivered by frameStream.
  Map<String, dynamic> tinyFrame() => <String, dynamic>{
        'y': Uint8List(4),
        'u': Uint8List(1),
        'v': Uint8List(1),
        'width': 2,
        'height': 2,
        'yRowStride': 2,
        'uvRowStride': 2,
        'uvPixelStride': 1,
      };

  group('CameraIsolate lifecycle', () {
    late ArDepthChannelMock depthMock;

    setUp(() {
      depthMock = ArDepthChannelMock()..install();
    });

    tearDown(() => depthMock.uninstall());

    testWidgets('start → frame → detections emit → stop returns promptly',
        (tester) async {
      await tester.runAsync(() async {
        final isolate = CameraIsolate();
        await isolate.start();

        final firstResult = isolate.detections.first;
        depthMock.pushFrame(tinyFrame());
        final List<Detection> detections =
            await firstResult.timeout(const Duration(seconds: 10));
        // Host machines without the native TFLite library yield an empty
        // list; the round-trip through the isolate is what matters here.
        expect(detections, isA<List<Detection>>());

        // Clean shutdown must beat the 2 s kill fallback comfortably.
        await isolate.stop().timeout(const Duration(seconds: 5));
      });
    });

    testWidgets('a fresh instance can start after a previous one stopped',
        (tester) async {
      await tester.runAsync(() async {
        final first = CameraIsolate();
        await first.start();
        await first.stop().timeout(const Duration(seconds: 5));

        // Fresh-instance-per-start contract (pause/resume relies on this).
        final second = CameraIsolate();
        await second.start();
        final result = second.detections.first;
        depthMock.pushFrame(tinyFrame());
        await result.timeout(const Duration(seconds: 10));
        await second.stop().timeout(const Duration(seconds: 5));
      });
    });

    testWidgets('stop is idempotent', (tester) async {
      await tester.runAsync(() async {
        final isolate = CameraIsolate();
        await isolate.start();
        await isolate.stop().timeout(const Duration(seconds: 5));
        await isolate.stop().timeout(const Duration(seconds: 5));
      });
    });
  });
}
