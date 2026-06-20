import 'dart:math' as math;
import 'dart:ui';

import '../core/constants.dart';
import 'detection.dart';

// Parses YOLOv8 TFLite output into a filtered, NMS-deduplicated Detection list.
class Postprocess {
  static const _targetClasses = {
    'person', 'bicycle', 'bench', 'chair',
    'door', 'staircase',
  };

  // Parses YOLOv8n output tensor: raw[4+numClasses][numAnchors].
  // Layout per anchor i: [cx, cy, w, h, score_class0, score_class1, ...]
  // Box coords are normalised [0, 1] in the **letterboxed model space**.
  //
  // [scale], [padX], [padY], [frameW], [frameH] are the exact letterbox params
  // from FramePreprocessor; output boxes are inverted back to normalised [0, 1]
  // in the **original camera frame** space (the contract Detection.bbox expects).
  static List<Detection> parseYolo({
    required List<List<double>> raw,  // [4+numClasses][numAnchors]
    required List<String> labels,
    required double scale,
    required int padX,
    required int padY,
    required int frameW,
    required int frameH,
    int modelSize = 320,
  }) {
    final numAnchors = raw[0].length;
    final numClasses = raw.length - 4;

    final candidates = <_YoloDet>[];

    for (int i = 0; i < numAnchors; i++) {
      // Find the highest-scoring class for this anchor
      int bestCls = 0;
      double bestScore = raw[4][i];
      for (int c = 1; c < numClasses; c++) {
        final s = raw[4 + c][i];
        if (s > bestScore) { bestScore = s; bestCls = c; }
      }
      if (bestScore < kMinConfidence) continue;
      if (bestCls >= labels.length) continue;

      final label = labels[bestCls]; // YOLOv8: 0-indexed, no background class
      if (!_targetClasses.contains(label)) continue;

      // Convert [cx, cy, w, h] → [x1, y1, x2, y2]
      final cx = raw[0][i]; final cy = raw[1][i];
      final hw = raw[2][i] / 2; final hh = raw[3][i] / 2;
      candidates.add(_YoloDet(
        label: label,
        score: bestScore,
        x1: (cx - hw).clamp(0.0, 1.0),
        y1: (cy - hh).clamp(0.0, 1.0),
        x2: (cx + hw).clamp(0.0, 1.0),
        y2: (cy + hh).clamp(0.0, 1.0),
      ));
    }

    // Greedy NMS — suppress overlapping boxes with IoU > 0.45
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_YoloDet>[];
    final suppressed = List.filled(candidates.length, false);
    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;
      kept.add(candidates[i]);
      for (int j = i + 1; j < candidates.length; j++) {
        if (!suppressed[j] && _iou(candidates[i], candidates[j]) > 0.45) {
          suppressed[j] = true;
        }
      }
    }

    // Letterbox inverse: model-space normalised [0,1] → frame-space normalised
    // [0,1]. xModelPx = xNorm * S; xFramePx = (xModelPx - pad) / scale;
    // xFrameNorm = xFramePx / frameDim. Uses the exact scale/pad from Task 1.
    final S = modelSize.toDouble();
    double toFrameX(double xNorm) =>
        (((xNorm * S - padX) / scale) / frameW).clamp(0.0, 1.0);
    double toFrameY(double yNorm) =>
        (((yNorm * S - padY) / scale) / frameH).clamp(0.0, 1.0);

    final now = DateTime.now();
    final result = kept.map((d) => Detection(
      label: d.label,
      confidence: d.score,
      bbox: Rect.fromLTRB(
        toFrameX(d.x1), toFrameY(d.y1), toFrameX(d.x2), toFrameY(d.y2),
      ),
      timestamp: now,
    )).toList();

    // Sort closest-first: larger bbox area = nearer proxy until ARCore §6
    result.sort((a, b) {
      final aArea = a.bbox.width * a.bbox.height;
      final bArea = b.bbox.width * b.bbox.height;
      return bArea.compareTo(aArea);
    });
    return result;
  }

  static double _iou(_YoloDet a, _YoloDet b) {
    final ix1 = math.max(a.x1, b.x1);
    final iy1 = math.max(a.y1, b.y1);
    final ix2 = math.min(a.x2, b.x2);
    final iy2 = math.min(a.y2, b.y2);
    final inter = math.max(0.0, ix2 - ix1) * math.max(0.0, iy2 - iy1);
    if (inter == 0) return 0;
    final aArea = (a.x2 - a.x1) * (a.y2 - a.y1);
    final bArea = (b.x2 - b.x1) * (b.y2 - b.y1);
    return inter / (aArea + bArea - inter);
  }
}

class _YoloDet {
  final String label;
  final double score, x1, y1, x2, y2;
  const _YoloDet({
    required this.label, required this.score,
    required this.x1, required this.y1,
    required this.x2, required this.y2,
  });
}
