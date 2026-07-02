import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/inference/postprocess.dart';

// labels[0..5] are the current 6-class allowlist; labels[6] ('pole') is
// intentionally outside it — a recent commit removed pole from detection.
const _labels = [
  'person', 'bicycle', 'bench', 'chair', 'door', 'staircase', 'pole',
];

// Builds a raw[4+numClasses][numAnchors] matrix for parseYolo. classScores[i]
// maps classIndex -> score for anchor i; any class not listed defaults to 0.
List<List<double>> _buildRaw({
  required List<double> cx,
  required List<double> cy,
  required List<double> w,
  required List<double> h,
  required List<Map<int, double>> classScores,
  int numClasses = 7,
}) {
  final n = cx.length;
  final raw = List.generate(4 + numClasses, (_) => List<double>.filled(n, 0.0));
  for (var i = 0; i < n; i++) {
    raw[0][i] = cx[i];
    raw[1][i] = cy[i];
    raw[2][i] = w[i];
    raw[3][i] = h[i];
    classScores[i].forEach((c, s) => raw[4 + c][i] = s);
  }
  return raw;
}

// Identity letterbox params (modelSize=320, scale=1, no padding, 320x320
// frame) so bbox output equals model-space coords directly, for tests that
// aren't specifically about the letterbox transform.
const _identityArgs = (scale: 1.0, padX: 0, padY: 0, frameW: 320, frameH: 320);

void main() {
  group('Postprocess.parseYolo confidence threshold', () {
    test('anchor scoring just below kMinConfidence is dropped', () {
      final raw = _buildRaw(
        cx: [0.5], cy: [0.5], w: [0.2], h: [0.2],
        classScores: [
          {0: kMinConfidence - 0.01},
        ],
      );
      final result = Postprocess.parseYolo(
        raw: raw, labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, isEmpty);
    });

    test('anchor scoring at or above kMinConfidence is kept', () {
      final raw = _buildRaw(
        cx: [0.5], cy: [0.5], w: [0.2], h: [0.2],
        classScores: [
          {0: kMinConfidence + 0.01},
        ],
      );
      final result = Postprocess.parseYolo(
        raw: raw, labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, hasLength(1));
      expect(result.single.label, 'person');
    });
  });

  group('Postprocess.parseYolo target-class allowlist', () {
    test('a class outside _targetClasses (pole) is excluded even at high confidence', () {
      final raw = _buildRaw(
        cx: [0.5], cy: [0.5], w: [0.2], h: [0.2],
        classScores: [
          {6: 0.95}, // 'pole' — not in the current 6-class allowlist
        ],
      );
      final result = Postprocess.parseYolo(
        raw: raw, labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, isEmpty);
    });
  });

  group('Postprocess.parseYolo NMS', () {
    test('suppresses a heavily-overlapping lower-score box (IoU > 0.45)', () {
      final raw = _buildRaw(
        cx: [0.5, 0.52], cy: [0.5, 0.52], w: [0.3, 0.3], h: [0.3, 0.3],
        classScores: [
          {0: 0.9},
          {0: 0.6},
        ],
      );
      final result = Postprocess.parseYolo(
        raw: raw, labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, hasLength(1));
      expect(result.single.confidence, closeTo(0.9, 1e-9));
    });

    test('keeps two boxes with low overlap (IoU < 0.45)', () {
      final raw = _buildRaw(
        cx: [0.2, 0.8], cy: [0.2, 0.8], w: [0.2, 0.2], h: [0.2, 0.2],
        classScores: [
          {0: 0.9},
          {0: 0.6},
        ],
      );
      final result = Postprocess.parseYolo(
        raw: raw, labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, hasLength(2));
    });
  });

  test('inverts the letterbox transform back to frame-space coordinates', () {
    // scale=0.4, padX=32, padY=48, frame 700x560 — non-trivial, non-square
    // letterbox params so all four terms of the inverse are exercised.
    final raw = _buildRaw(
      cx: [0.5], cy: [0.5], w: [0.25], h: [0.15],
      classScores: [
        {0: 0.9},
      ],
    );
    final result = Postprocess.parseYolo(
      raw: raw, labels: _labels,
      scale: 0.4, padX: 32, padY: 48, frameW: 700, frameH: 560,
    );
    expect(result, hasLength(1));
    final bbox = result.single.bbox;
    expect(bbox.left, closeTo(220 / 700, 1e-9));
    expect(bbox.right, closeTo(420 / 700, 1e-9));
    expect(bbox.top, closeTo(220 / 560, 1e-9));
    expect(bbox.bottom, closeTo(340 / 560, 1e-9));
  });

  test('sorts results descending by bbox area (closest-first proxy)', () {
    final raw = _buildRaw(
      cx: [0.2, 0.8], cy: [0.2, 0.8], w: [0.1, 0.5], h: [0.1, 0.5],
      classScores: [
        {0: 0.9}, // small box
        {1: 0.9}, // large box ('bicycle')
      ],
    );
    final result = Postprocess.parseYolo(
      raw: raw, labels: _labels,
      scale: _identityArgs.scale, padX: _identityArgs.padX,
      padY: _identityArgs.padY, frameW: _identityArgs.frameW,
      frameH: _identityArgs.frameH,
    );
    expect(result, hasLength(2));
    expect(result.first.label, 'bicycle'); // larger area comes first
    expect(result.last.label, 'person');
  });

  group('malformed output tensors', () {
    test('a truncated raw matrix (fewer than 5 rows) returns empty', () {
      final result = Postprocess.parseYolo(
        raw: [
          [0.5],
          [0.5],
          [0.2],
          [0.2],
        ], // only box rows, no class scores
        labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, isEmpty);
    });

    test('a zero-anchor raw matrix returns empty', () {
      final result = Postprocess.parseYolo(
        raw: List.generate(11, (_) => const <double>[]),
        labels: _labels,
        scale: _identityArgs.scale, padX: _identityArgs.padX,
        padY: _identityArgs.padY, frameW: _identityArgs.frameW,
        frameH: _identityArgs.frameH,
      );
      expect(result, isEmpty);
    });
  });
}
