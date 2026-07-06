import 'dart:math' as math;

import '../core/constants.dart';

abstract final class IntensityCurve {
  /// Inverse-square haptic amplitude: A(d) = min(1.0, k / d²)
  ///
  /// With k=0.5 (default): 0.03 at 4 m, 0.5 at 1 m, saturates at ≈0.7 m.
  /// With k=2.0 (max): saturates at ≈1.4 m.
  /// With k=0.1 (min): saturates at ≈0.3 m (arm's length only).
  static double amplitudeFor(double distanceMeters, {required double k}) {
    if (distanceMeters <= 0) return 1.0;
    return math.min(1.0, k / (distanceMeters * distanceMeters));
  }

  /// [amplitudeFor] with a legibility floor for the live directional
  /// tactons: their information is the pulse count, and pulses below
  /// [kDirectionalAmplitudeFloor] cannot be counted at all — a far door on
  /// the right would buzz identically to the radar's faint ahead-pulses.
  static double directionalAmplitudeFor(double distanceMeters,
          {required double k}) =>
      math.max(
          kDirectionalAmplitudeFloor, amplitudeFor(distanceMeters, k: k));
}
