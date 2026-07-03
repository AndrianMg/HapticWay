import 'haptic_engine.dart';

/// Named vibration patterns for the Haptic Radar.
///
/// Every pattern routes through [HapticEngine] so platform failures are
/// caught and surfaced instead of dying silently. [obstacleAhead] is
/// rate-limited per pulse; directional patterns share the longer
/// [HapticEngine.kPatternCooldown] window (intra-pattern timing is never
/// disrupted); override confirmations are un-throttled one-shot
/// user-initiated events.
abstract final class Tacton {
  /// Single 200 ms pulse — main proximity alert, scaled by distance.
  static Future<void> obstacleAhead(double amplitude) =>
      HapticEngine.vibrate(amplitude, const Duration(milliseconds: 200));

  /// Two short pulses — obstacle to the left (for future directional use).
  static Future<void> obstacleLeft(double amplitude) =>
      HapticEngine.vibratePattern(
        pattern: const [0, 80, 80, 80],
        intensities: [0, _toInt(amplitude), 0, _toInt(amplitude)],
      );

  /// Three short pulses — obstacle to the right (for future directional use).
  static Future<void> obstacleRight(double amplitude) =>
      HapticEngine.vibratePattern(
        pattern: const [0, 60, 60, 60, 60, 60],
        intensities: [
          0,
          _toInt(amplitude),
          0,
          _toInt(amplitude),
          0,
          _toInt(amplitude),
        ],
      );

  /// Long strong buzz — confirms haptic alerts have been DISABLED.
  static Future<void> manualOverrideOn() =>
      HapticEngine.vibrateFixed(durationMs: 400, amplitude: 230);

  /// Long gentle buzz — confirms haptic alerts have been RE-ENABLED.
  static Future<void> manualOverrideOff() =>
      HapticEngine.vibrateFixed(durationMs: 400, amplitude: 80);

  static int _toInt(double amplitude) =>
      (amplitude * 255).round().clamp(1, 255);
}
