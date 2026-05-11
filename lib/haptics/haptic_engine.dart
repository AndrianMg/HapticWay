import 'package:vibration/vibration.dart';

class HapticEngine {
  static const int _maxPulsesPerSecond = 20;
  static DateTime? _lastPulse;

  static Future<void> vibrate(double amplitude, Duration duration) async {
    final now = DateTime.now();
    if (_lastPulse != null) {
      final elapsed = now.difference(_lastPulse!);
      if (elapsed.inMilliseconds < (1000 / _maxPulsesPerSecond)) return;
    }
    _lastPulse = now;

    final hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    final amplitudeInt = (amplitude * 255).round().clamp(1, 255);
    await Vibration.vibrate(
      duration: duration.inMilliseconds,
      amplitude: amplitudeInt,
    );
  }
}
