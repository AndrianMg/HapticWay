import 'dart:math' as math;

import '../core/constants.dart';

// Maps obstacle distance to vibration strength — the mathematical core of
// the haptic feedback loop. Both the depth-poll radar (HomeScreen._pollDepth)
// and the directional tactons (Tacton) call into this; the actual vibration
// call happens one layer down, in HapticEngine.
//
// Shape: A(d) = min(1.0, k/d²), an inverse-square falloff rather than a
// linear one. This is a deliberate design choice (not an empirically
// validated result — see the VIVA prep note), chosen because it concentrates
// the intensity gradient near the user, where reaction time is shortest,
// instead of spreading it evenly across the whole sensing range.
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
