import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

class HapticEngine {
  static const int _maxPulsesPerSecond = 2;
  static DateTime? _lastPulse;

  /// Clears static throttle state so tests don't bleed into each other.
  @visibleForTesting
  static void reset() {
    _lastPulse = null;
  }

  static Future<void> vibrate(double amplitude, Duration duration) async {
    final now = DateTime.now();
    if (_lastPulse != null) {
      final elapsed = now.difference(_lastPulse!);
      if (elapsed.inMilliseconds < (1000 / _maxPulsesPerSecond)) return;
    }
    _lastPulse = now;

    if (!await Vibration.hasVibrator()) return;

    final hasAmplitude = await Vibration.hasAmplitudeControl();
    final amplitudeInt = hasAmplitude
        ? (amplitude * 255).round().clamp(1, 255)
        : -1; // -1 = device default amplitude

    await Vibration.vibrate(
      duration: duration.inMilliseconds,
      amplitude: amplitudeInt,
    );
  }
}
