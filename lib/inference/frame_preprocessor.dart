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
    int rotationDegrees = 0,
  }) {
    // Step 1: YUV → RGB with optional 90° CW rotation fused into the same pass.
    // The S20 Ultra sensor delivers landscape frames (640×480) regardless of
    // device orientation. In portrait the model sees the world sideways, causing
    // door→bench / texture→staircase misclassification. Fusing the rotation here
    // avoids a second allocation and copy pass (keeps P95 within budget).
    //
    // 90° CW mapping: source (row, col) → dest (new_row=col, new_col=height−1−row)
    // Post-rotation dims: frameW = height (480), frameH = width (640).
    final bool rotate90 = rotationDegrees == 90;
    final int frameW = rotate90 ? height : width;
    final int frameH = rotate90 ? width  : height;
    final Uint8List rgbSrc = Uint8List(frameW * frameH * 3);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yVal = yPlane[row * yRowStride + col];
        final uvCol = col ~/ 2;
        final uvRow = row ~/ 2;
        final uvIdx = uvRow * uvRowStride + uvCol * uvPixelStride;
        final uVal = uPlane[uvIdx];
        final vVal = vPlane[uvIdx];

        // ITU-R BT.601 full-swing — fixed-point ×256 (coefficients pre-scaled,
        // bit-shifted instead of float multiply; eliminates .round() on doubles).
        // 1.402→359  0.344→88  0.714→183  1.772→454  (max rounding error <1/255)
        final int u128 = uVal - 128;
        final int v128 = vVal - 128;
        final int r = (yVal + ((359 * v128) >> 8)).clamp(0, 255);
        final int g = (yVal - ((88  * u128) >> 8) - ((183 * v128) >> 8)).clamp(0, 255);
        final int b = (yVal + ((454 * u128) >> 8)).clamp(0, 255);

        final int dstIdx = rotate90
            ? (col * frameW + (height - 1 - row)) * 3
            : (row * frameW + col) * 3;
        rgbSrc[dstIdx]     = r.clamp(0, 255);
        rgbSrc[dstIdx + 1] = g.clamp(0, 255);
        rgbSrc[dstIdx + 2] = b.clamp(0, 255);
      }
    }

    // Step 2: letterbox — single uniform scale, centred, padded to a square.
    final double scale = math.min(modelSize / frameW, modelSize / frameH);
    final int newW = (frameW * scale).round();
    final int newH = (frameH * scale).round();
    final int padX = ((modelSize - newW) / 2).floor();
    final int padY = ((modelSize - newH) / 2).floor();

    // Fill the whole canvas with the pad value; the resized image overwrites
    // the central newW × newH region, leaving grey bars on the short axis.
    _outBuffer.fillRange(0, _outBuffer.length, _padValue);

    // Bilinear resize rgbSrc(frameW×frameH) → newW×newH, written at (padX, padY).
    // Half-pixel-centre sampling matches OpenCV/Ultralytics INTER_LINEAR.
    final double fxScale = frameW / newW;
    final double fyScale = frameH / newH;

    for (int dy = 0; dy < newH; dy++) {
      double fy = (dy + 0.5) * fyScale - 0.5;
      int y0 = fy.floor();
      final double wy = fy - y0;
      final int y0c = y0.clamp(0, frameH - 1);
      final int y1c = (y0 + 1).clamp(0, frameH - 1);
      final int canvasRow = (padY + dy) * modelSize;

      for (int dx = 0; dx < newW; dx++) {
        double fx = (dx + 0.5) * fxScale - 0.5;
        int x0 = fx.floor();
        final double wx = fx - x0;
        final int x0c = x0.clamp(0, frameW - 1);
        final int x1c = (x0 + 1).clamp(0, frameW - 1);

        final int i00 = (y0c * frameW + x0c) * 3;
        final int i01 = (y0c * frameW + x1c) * 3;
        final int i10 = (y1c * frameW + x0c) * 3;
        final int i11 = (y1c * frameW + x1c) * 3;

        final int outIdx = (canvasRow + padX + dx) * 3;
        for (int c = 0; c < 3; c++) {
          final double top = rgbSrc[i00 + c] * (1 - wx) + rgbSrc[i01 + c] * wx;
          final double bot = rgbSrc[i10 + c] * (1 - wx) + rgbSrc[i11 + c] * wx;
          _outBuffer[outIdx + c] = (top * (1 - wy) + bot * wy).round().clamp(0, 255);
        }
      }
    }

    return LetterboxResult(
      tensor: _outBuffer,
      scale: scale,
      padX: padX,
      padY: padY,
      frameW: frameW,
      frameH: frameH,
    );
  }
}
