import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _depthChannel = MethodChannel('hapticway/depth');
const _framesChannel = EventChannel('hapticway/frames');

/// Installs mock handlers for the app-owned `hapticway/depth` MethodChannel
/// and `hapticway/frames` EventChannel, so [ArDepthChannel] and
/// [CameraIsolate] never touch real ARCore/platform code in tests.
class ArDepthChannelMock {
  int textureId = 1;
  double depthMeters = -1.0;
  final List<MethodCall> calls = [];

  MockStreamHandlerEventSink? _frameSink;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_depthChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'start':
          return textureId;
        case 'sampleDepth':
          return depthMeters;
        case 'stop':
          return null;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      _framesChannel,
      // Block bodies, not arrows: an arrow's expression value would flow
      // through as the mock method reply, and the codec can't encode a
      // MockStreamHandlerEventSink.
      MockStreamHandler.inline(
        onListen: (args, events) {
          _frameSink = events;
        },
        onCancel: (args) {
          _frameSink = null;
        },
      ),
    );
  }

  /// Pushes a fake YUV frame map to anything subscribed to `frameStream`.
  void pushFrame(Map<String, dynamic> frame) => _frameSink?.success(frame);

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_depthChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(_framesChannel, null);
    _frameSink = null;
  }
}
