import 'dart:typed_data';

// Converts an Android YUV_420_888 camera frame to a flat RGB Uint8List
// of exactly 320 × 320 × 3 bytes (NHWC, matching the YOLOv8n model input).
// All operations reuse pre-allocated buffers — no per-frame heap allocation.
class FramePreprocessor {
  static const int modelSize = 320;

  static final Uint8List _outBuffer = Uint8List(modelSize * modelSize * 3);

  static Uint8List process({
    required Uint8List yPlane,
    required Uint8List uPlane,
    required Uint8List vPlane,
    required int width,
    required int height,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
  }) {
    // Step 1: YUV → RGB into a (width × height × 3) scratch buffer.
    // We allocate a new buffer here because width/height can vary between devices.
    final rgb = Uint8List(width * height * 3);
    int rgbIdx = 0;

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yVal = yPlane[row * yRowStride + col];
        final uvCol = col ~/ 2;
        final uvRow = row ~/ 2;
        final uvIdx = uvRow * uvRowStride + uvCol * uvPixelStride;
        final uVal = uPlane[uvIdx];
        final vVal = vPlane[uvIdx];

        // ITU-R BT.601 coefficients (full-swing)
        int r = (yVal + 1.402 * (vVal - 128)).round();
        int g = (yVal - 0.344 * (uVal - 128) - 0.714 * (vVal - 128)).round();
        int b = (yVal + 1.772 * (uVal - 128)).round();

        rgb[rgbIdx++] = r.clamp(0, 255);
        rgb[rgbIdx++] = g.clamp(0, 255);
        rgb[rgbIdx++] = b.clamp(0, 255);
      }
    }

    // Step 2: Nearest-neighbour resize → 320 × 320.
    final xRatio = width / modelSize;
    final yRatio = height / modelSize;
    int outIdx = 0;

    for (int row = 0; row < modelSize; row++) {
      for (int col = 0; col < modelSize; col++) {
        final srcCol = (col * xRatio).floor().clamp(0, width - 1);
        final srcRow = (row * yRatio).floor().clamp(0, height - 1);
        final srcIdx = (srcRow * width + srcCol) * 3;
        _outBuffer[outIdx++] = rgb[srcIdx];
        _outBuffer[outIdx++] = rgb[srcIdx + 1];
        _outBuffer[outIdx++] = rgb[srcIdx + 2];
      }
    }

    return _outBuffer;
  }
}
