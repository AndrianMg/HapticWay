import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/haptics/intensity_curve.dart';

void main() {
  group('IntensityCurve.amplitudeFor', () {
    test('distance <= 0 returns full amplitude', () {
      expect(IntensityCurve.amplitudeFor(0, k: 0.5), 1.0);
      expect(IntensityCurve.amplitudeFor(-1, k: 0.5), 1.0);
    });

    test('never exceeds 1.0 even at very small distances', () {
      final a = IntensityCurve.amplitudeFor(0.01, k: 2.0);
      expect(a, lessThanOrEqualTo(1.0));
      expect(a, 1.0); // k/d^2 = 20000 here, clamped
    });

    test('approaches but never reaches exactly 0 at very large distances', () {
      final a = IntensityCurve.amplitudeFor(1000, k: 0.5);
      expect(a, greaterThan(0.0));
      expect(a, lessThan(0.001));
    });

    test('is monotonically non-increasing as distance grows', () {
      const k = 0.5;
      const distances = [0.3, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0];
      for (var i = 1; i < distances.length; i++) {
        final prev = IntensityCurve.amplitudeFor(distances[i - 1], k: k);
        final next = IntensityCurve.amplitudeFor(distances[i], k: k);
        expect(next, lessThanOrEqualTo(prev));
      }
    });

    // Saturation boundary: at d = sqrt(k), k/d^2 == 1.0 exactly, so this is
    // the closest distance where amplitude is still uncapped from below.
    for (final k in [0.2, 0.5, 2.0]) {
      test('saturates to 1.0 right at d = sqrt(k=$k)', () {
        final d = math.sqrt(k);
        expect(IntensityCurve.amplitudeFor(d, k: k), closeTo(1.0, 1e-9));
        expect(
          IntensityCurve.amplitudeFor(d + 0.05, k: k),
          lessThan(1.0),
        );
      });
    }

    test('matches documented values for the live default k', () {
      // Doc comment: k=0.5 -> 0.5 at 1m, 0.03 at 4m.
      expect(
        IntensityCurve.amplitudeFor(1.0, k: kHapticConstantK),
        closeTo(0.5, 1e-9),
      );
      expect(
        IntensityCurve.amplitudeFor(4.0, k: kHapticConstantK),
        closeTo(0.5 / 16, 1e-9),
      );
    });
  });

  group('IntensityCurve.directionalAmplitudeFor', () {
    test('far obstacles are floored for pulse-count legibility', () {
      // Plain curve at 3m with the default k is 0.056 — pulses that weak
      // cannot be counted, and the count IS the direction information.
      expect(
        IntensityCurve.directionalAmplitudeFor(3.0, k: kHapticConstantK),
        kDirectionalAmplitudeFloor,
      );
    });

    test('close obstacles follow the plain curve above the floor', () {
      // k=0.5 at 0.8m -> 0.78, already legible: identical to amplitudeFor.
      expect(
        IntensityCurve.directionalAmplitudeFor(0.8, k: kHapticConstantK),
        closeTo(IntensityCurve.amplitudeFor(0.8, k: kHapticConstantK), 1e-9),
      );
    });
  });
}
