import 'package:vibration/vibration.dart';

import 'haptic_engine.dart';

/// Named vibration patterns for the Haptic Radar.
///
/// obstacleAhead goes through [HapticEngine] (respects rate limiter).
/// Directional patterns use Vibration.vibrate(pattern:) directly so the
/// multi-pulse timing isn't disrupted by the per-call rate limiter.
/// Override confirmation patterns bypass the rate limiter intentionally —
/// they are one-shot user-initiated events, not inference-driven pulses.
abstract final class Tacton {
  /// Single 200 ms pulse — main proximity alert, scaled by distance.
  static Future<void> obstacleAhead(double amplitude) =>
      HapticEngine.vibrate(amplitude, const Duration(milliseconds: 200));

  /// Two short pulses — obstacle to the left (for future directional use).
  static Future<void> obstacleLeft(double amplitude) async {
    if (!await Vibration.hasVibrator()) return;
    await Vibration.vibrate(
      pattern: [0, 80, 80, 80],
      intensities: [0, _toInt(amplitude), 0, _toInt(amplitude)],
    );
  }

  /// Three short pulses — obstacle to the right (for future directional use).
  static Future<void> obstacleRight(double amplitude) async {
    if (!await Vibration.hasVibrator()) return;
    await Vibration.vibrate(
      pattern: [0, 60, 60, 60, 60, 60],
      intensities: [0, _toInt(amplitude), 0, _toInt(amplitude), 0, _toInt(amplitude)],
    );
  }

  /// Long strong buzz — confirms haptic alerts have been DISABLED.
  static Future<void> manualOverrideOn() async {
    if (!await Vibration.hasVibrator()) return;
    await Vibration.vibrate(duration: 400, amplitude: 230);
  }

  /// Long gentle buzz — confirms haptic alerts have been RE-ENABLED.
  static Future<void> manualOverrideOff() async {
    if (!await Vibration.hasVibrator()) return;
    await Vibration.vibrate(duration: 400, amplitude: 80);
  }

  static int _toInt(double amplitude) =>
      (amplitude * 255).round().clamp(1, 255);
}
