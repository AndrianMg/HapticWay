import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/inference/frame_preprocessor.dart';

// Builds a fully-planar (uvPixelStride=1) YUV420 frame where every pixel
// shares the same Y/U/V value, except an optional single marker pixel with
// its own Y value (chroma left at [uVal]/[vVal] so only luma changes there).
({Uint8List y, Uint8List u, Uint8List v}) _buildFrame({
  required int width,
  required int height,
  required int yVal,
  required int uVal,
  required int vVal,
  (int row, int col, int markerY)? marker,
}) {
  final y = Uint8List(width * height)..fillRange(0, width * height, yVal);
  final chromaW = width ~/ 2;
  final chromaH = height ~/ 2;
  final u = Uint8List(chromaW * chromaH)..fillRange(0, chromaW * chromaH, uVal);
  final v = Uint8List(chromaW * chromaH)..fillRange(0, chromaW * chromaH, vVal);
  if (marker != null) {
    final (row, col, markerY) = marker;
    y[row * width + col] = markerY;
  }
  return (y: y, u: u, v: v);
}

LetterboxResult _process({
  required int width,
  required int height,
  required int yVal,
  required int uVal,
  required int vVal,
  int rotationDegrees = 0,
  (int row, int col, int markerY)? marker,
}) {
  final frame = _buildFrame(
    width: width, height: height, yVal: yVal, uVal: uVal, vVal: vVal,
    marker: marker,
  );
  return FramePreprocessor.process(
    yPlane: frame.y, uPlane: frame.u, vPlane: frame.v,
    width: width, height: height,
    yRowStride: width, uvRowStride: width ~/ 2, uvPixelStride: 1,
    rotationDegrees: rotationDegrees,
  );
}

// Reads the RGB triple for tensor pixel (row, col) out of the flat NHWC
// Uint8List (320x320x3) returned by FramePreprocessor.process.
(int r, int g, int b) _pixelAt(Uint8List tensor, int row, int col) {
  final i = (row * FramePreprocessor.modelSize + col) * 3;
  return (tensor[i], tensor[i + 1], tensor[i + 2]);
}

void main() {
  test('flat mid-grey YUV converts to RGB (128, 128, 128)', () {
    final result = _process(
      width: FramePreprocessor.modelSize,
      height: FramePreprocessor.modelSize,
      yVal: 128, uVal: 128, vVal: 128,
    );
    expect(_pixelAt(result.tensor, 0, 0), (128, 128, 128));
    expect(_pixelAt(result.tensor, 160, 160), (128, 128, 128));
    expect(_pixelAt(result.tensor, 319, 319), (128, 128, 128));
  });

  test('a known non-grey YUV triple converts via the fixed-point BT.601 coefficients', () {
    // Y=150, U=100, V=160 (u128=-28, v128=32), no clamping triggered — chosen
    // so the test exercises the raw arithmetic, not the 0/255 clamp path.
    // r = 150 + (359*v128>>8)          = 150 + 44        = 194
    // g = 150 - (88*u128>>8) - (183*v128>>8) = 150 + 10 - 22 = 138
    // b = 150 + (454*u128>>8)          = 150 + (-50)     = 100
    final result = _process(
      width: 4, height: 4, yVal: 150, uVal: 100, vVal: 160,
    );
    expect(_pixelAt(result.tensor, 100, 100), (194, 138, 100));
  });

  test('90-degree rotation maps (row, col) to (col, height-1-row)', () {
    const size = FramePreprocessor.modelSize; // square input -> no letterbox distortion
    const row = 50, col = 10;
    final result = _process(
      width: size, height: size, yVal: 128, uVal: 128, vVal: 128,
      rotationDegrees: 90,
      marker: (row, col, 200),
    );
    // Documented mapping: dest (new_row=col, new_col=height-1-row).
    expect(_pixelAt(result.tensor, col, size - 1 - row), (200, 200, 200));
    // Sanity: the un-rotated location is not where the marker landed.
    expect(_pixelAt(result.tensor, row, col), (128, 128, 128));
  });

  test('non-square input is letterboxed to 320x320x3 with grey-114 padding', () {
    final result = _process(
      width: 640, height: 480, yVal: 50, uVal: 128, vVal: 128,
    );
    expect(result.tensor.length, FramePreprocessor.modelSize * FramePreprocessor.modelSize * 3);
    expect(result.scale, closeTo(0.5, 1e-9));
    expect(result.padX, 0);
    expect(result.padY, 40);
    expect(result.frameW, 640);
    expect(result.frameH, 480);

    // Top pad band (rows 0-39) and bottom pad band (rows 280-319) are grey-114.
    expect(_pixelAt(result.tensor, 0, 160), (114, 114, 114));
    expect(_pixelAt(result.tensor, 319, 160), (114, 114, 114));
    // Content band (rows 40-279) holds the converted frame, uniform Y=50.
    expect(_pixelAt(result.tensor, 200, 160), (50, 50, 50));
  });

  test('zero-dimension frames are rejected instead of dividing by zero', () {
    expect(
      () => FramePreprocessor.process(
        yPlane: Uint8List(0), uPlane: Uint8List(0), vPlane: Uint8List(0),
        width: 0, height: 480,
        yRowStride: 0, uvRowStride: 0, uvPixelStride: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => FramePreprocessor.process(
        yPlane: Uint8List(0), uPlane: Uint8List(0), vPlane: Uint8List(0),
        width: 640, height: 0,
        yRowStride: 640, uvRowStride: 320, uvPixelStride: 1,
      ),
      throwsArgumentError,
    );
  });
}
