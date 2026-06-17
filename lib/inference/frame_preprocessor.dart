import 'dart:math' as math;
import 'dart:typed_data';

/// Result of [FramePreprocessor.process]: the model input tensor plus the exact
/// letterbox transform applied, so postprocess can invert it with identical
/// numbers (no downstream recomputation / rounding drift).
class LetterboxResult {
  final Uint8List tensor; // modelSize × modelSize × 3, NHWC RGB uint8
  final double scale; // uniform scale applied to the source frame
  final int padX; // left pad in model pixels
  final int padY; // top pad in model pixels
  final int frameW; // original frame width
  final int frameH; // original frame height

  const LetterboxResult({
    required this.tensor,
    required this.scale,
    required this.padX,
    required this.padY,
    required this.frameW,
    required this.frameH,
  });
}

// Converts an Android YUV_420_888 camera frame to a flat RGB Uint8List
// of exactly 320 × 320 × 3 bytes (NHWC, matching the YOLOv8n model input).
//
// The frame is resized with an aspect-preserving **letterbox** (uniform scale +
// centred grey padding), matching Ultralytics' training / validation / INT8
// calibration preprocessing. This replaces the previous anisotropic stretch,
// which distorted object aspect ratio and was off-distribution for the model.
// All large operations reuse pre-allocated buffers — no per-frame heap churn.
class FramePreprocessor {
  static const int modelSize = 320;

  // Grey pad value — must match the value Ultralytics letterbox uses (114) so
  // the padded bars look the same as during training/calibration.
  static const int _padValue = 114;

  static final Uint8List _outBuffer = Uint8List(modelSize * modelSize * 3);

  static LetterboxResult process({
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

    // Step 2: letterbox — single uniform scale, centred, padded to a square.
    final double scale = math.min(modelSize / width, modelSize / height);
    final int newW = (width * scale).round();
    final int newH = (height * scale).round();
    final int padX = ((modelSize - newW) / 2).floor();
    final int padY = ((modelSize - newH) / 2).floor();

    // Fill the whole canvas with the pad value; the resized image overwrites
    // the central newW × newH region, leaving grey bars on the short axis.
    _outBuffer.fillRange(0, _outBuffer.length, _padValue);

    // Bilinear resize rgb(width×height) → newW×newH, written at (padX, padY).
    // Half-pixel-centre sampling matches OpenCV/Ultralytics INTER_LINEAR.
    final double fxScale = width / newW;
    final double fyScale = height / newH;

    for (int dy = 0; dy < newH; dy++) {
      double fy = (dy + 0.5) * fyScale - 0.5;
      int y0 = fy.floor();
      final double wy = fy - y0;
      final int y0c = y0.clamp(0, height - 1);
      final int y1c = (y0 + 1).clamp(0, height - 1);
      final int canvasRow = (padY + dy) * modelSize;

      for (int dx = 0; dx < newW; dx++) {
        double fx = (dx + 0.5) * fxScale - 0.5;
        int x0 = fx.floor();
        final double wx = fx - x0;
        final int x0c = x0.clamp(0, width - 1);
        final int x1c = (x0 + 1).clamp(0, width - 1);

        final int i00 = (y0c * width + x0c) * 3;
        final int i01 = (y0c * width + x1c) * 3;
        final int i10 = (y1c * width + x0c) * 3;
        final int i11 = (y1c * width + x1c) * 3;

        final int outIdx = (canvasRow + padX + dx) * 3;
        for (int c = 0; c < 3; c++) {
          final double top = rgb[i00 + c] * (1 - wx) + rgb[i01 + c] * wx;
          final double bot = rgb[i10 + c] * (1 - wx) + rgb[i11 + c] * wx;
          _outBuffer[outIdx + c] = (top * (1 - wy) + bot * wy).round().clamp(0, 255);
        }
      }
    }

    return LetterboxResult(
      tensor: _outBuffer,
      scale: scale,
      padX: padX,
      padY: padY,
      frameW: width,
      frameH: height,
    );
  }
}
