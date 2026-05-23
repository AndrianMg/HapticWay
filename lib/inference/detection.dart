import 'dart:ui';

class Detection {
  final String label;
  final double confidence;
  final Rect bbox; // normalised [0,1]: left, top, right, bottom
  final DateTime timestamp;

  const Detection({
    required this.label,
    required this.confidence,
    required this.bbox,
    required this.timestamp,
  });

  // Isolate-safe serialisation — Rect cannot cross isolate boundaries directly.
  Map<String, dynamic> toMap() => {
        'label': label,
        'confidence': confidence,
        'l': bbox.left,
        't': bbox.top,
        'r': bbox.right,
        'b': bbox.bottom,
        'ts': timestamp.millisecondsSinceEpoch,
      };

  factory Detection.fromMap(Map<String, dynamic> m) => Detection(
        label: m['label'] as String,
        confidence: (m['confidence'] as num).toDouble(),
        bbox: Rect.fromLTRB(
          (m['l'] as num).toDouble(),
          (m['t'] as num).toDouble(),
          (m['r'] as num).toDouble(),
          (m['b'] as num).toDouble(),
        ),
        timestamp: DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
      );

  // Proxy for distance until ARCore depth is wired in §6.
  // Larger bbox area → object closer → higher amplitude.
  double get proximityAmplitude {
    final area = bbox.width * bbox.height;
    // sqrt spreads the curve — gives response even for medium-sized detections
    return (area * 4).clamp(0.0, 1.0); // *4 so 50% screen = amplitude 1.0
  }
}
