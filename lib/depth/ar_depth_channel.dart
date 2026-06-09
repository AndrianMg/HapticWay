import 'package:flutter/services.dart';

/// Flutter wrapper for the Kotlin ArDepthChannel.
///
/// Call [start] once at app launch; it returns the Flutter texture ID
/// that backs the [Texture] widget used as camera preview.
/// [frameStream] delivers YUV_420_888 maps for on-device TFLite inference.
/// [sampleDepth] queries the latest cached ARCore depth image.
class ArDepthChannel {
  ArDepthChannel._();
  static final ArDepthChannel instance = ArDepthChannel._();

  static const _method = MethodChannel('hapticway/depth');
  static const _frames = EventChannel('hapticway/frames');

  Stream<Map<String, dynamic>>? _frameStream;

  /// Starts the ARCore session.
  /// Returns the Flutter texture ID for the [Texture] camera-preview widget.
  /// Throws [PlatformException] if ARCore is unavailable.
  Future<int> start() async {
    final id = await _method.invokeMethod<int>('start');
    return id!;
  }

  Future<void> stop() => _method.invokeMethod('stop');

  /// Live YUV_420_888 camera frame maps, one per ARCore frame (~30 fps).
  /// Each map contains: y, u, v (Uint8List), width, height (int),
  /// yRowStride, uvRowStride, uvPixelStride (int).
  Stream<Map<String, dynamic>> get frameStream {
    _frameStream ??= _frames
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
    return _frameStream!;
  }

  /// Returns depth in metres at a normalised (0–1) image coordinate.
  /// Returns -1.0 if depth is unavailable or confidence is too low.
  Future<double> sampleDepth(double nx, double ny) async {
    final d = await _method.invokeMethod<double>(
      'sampleDepth',
      {'nx': nx, 'ny': ny},
    );
    return d ?? -1.0;
  }
}
