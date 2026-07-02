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
    if (id == null) {
      throw PlatformException(
        code: 'AR_NO_TEXTURE',
        message: 'native start returned no texture id',
      );
    }
    return id;
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

  /// Scans the depth image over the bbox region and returns the minimum
  /// valid depth in metres, or -1.0 if unavailable / low confidence.
  Future<double> sampleDepth(double x1, double y1, double x2, double y2) async {
    final d = await _method.invokeMethod<double>(
      'sampleDepth',
      {'x1': x1, 'y1': y1, 'x2': x2, 'y2': y2},
    );
    return d ?? -1.0;
  }
}
