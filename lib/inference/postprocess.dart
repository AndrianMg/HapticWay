import 'dart:ui';

import '../core/constants.dart';
import 'detection.dart';

// Parses raw SSD MobileNet v2 output tensors into a filtered Detection list.
// NMS is already applied inside the TFLite model — we only filter by
// confidence threshold and restrict to the 8 navigation-relevant classes.
class Postprocess {
  // Classes available in the stock COCO model.
  // door, staircase, pole, wet_floor_sign are added after custom training (§5.6).
  static const _targetClasses = {
    'person', 'bicycle', 'bench', 'chair',
    'door', 'staircase', 'pole', 'wet_floor_sign',
  };

  static List<Detection> parse({
    required List<List<double>> boxes,  // [n, 4] — [top, left, bottom, right]
    required List<double> classes,      // [n] — float class index
    required List<double> scores,       // [n] — confidence 0–1
    required int count,
    required List<String> labels,
  }) {
    final result = <Detection>[];
    final now = DateTime.now();
    final n = count.clamp(0, boxes.length);

    for (int i = 0; i < n; i++) {
      if (scores[i] < kMinConfidence) continue;

      final classIdx = classes[i].round();
      if (classIdx < 0 || classIdx >= labels.length) continue;

      final label = labels[classIdx];
      if (!_targetClasses.contains(label)) continue;

      final box = boxes[i];
      // SSD output: [top, left, bottom, right], all normalised [0, 1]
      result.add(Detection(
        label: label,
        confidence: scores[i],
        bbox: Rect.fromLTRB(
          box[1].clamp(0.0, 1.0), // left
          box[0].clamp(0.0, 1.0), // top
          box[3].clamp(0.0, 1.0), // right
          box[2].clamp(0.0, 1.0), // bottom
        ),
        timestamp: now,
      ));
    }

    // Sort closest-first: larger bbox area = nearer proxy until ARCore §6
    result.sort((a, b) {
      final aArea = a.bbox.width * a.bbox.height;
      final bArea = b.bbox.width * b.bbox.height;
      return bArea.compareTo(aArea);
    });

    return result;
  }
}
