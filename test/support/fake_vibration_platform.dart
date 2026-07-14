import 'package:vibration_platform_interface/vibration_platform_interface.dart';

/// Record of a single `vibrate(...)` call made through [FakeVibrationPlatform].
class VibrateCall {
  final int duration;
  final List<int> pattern;
  final int repeat;
  final List<int> intensities;
  final int amplitude;

  const VibrateCall({
    required this.duration,
    required this.pattern,
    required this.repeat,
    required this.intensities,
    required this.amplitude,
  });
}

/// Test double for [VibrationPlatform] — records every vibrate call instead
/// of touching real vibration hardware. Install with
/// `VibrationPlatform.instance = FakeVibrationPlatform()` in setUp.
class FakeVibrationPlatform extends VibrationPlatform {
  bool hasVibratorValue = true;
  bool hasAmplitudeControlValue = true;
  final List<VibrateCall> calls = [];

  // Probe counters — let tests assert HapticEngine's capability cache keeps
  // these platform-channel round-trips off the per-pulse path.
  int hasVibratorCallCount = 0;
  int hasAmplitudeControlCallCount = 0;

  /// When set, every `vibrate(...)` call throws this instead of recording.
  Object? vibrateError;

  @override
  Future<bool> hasVibrator() async {
    hasVibratorCallCount++;
    return hasVibratorValue;
  }

  @override
  Future<bool> hasAmplitudeControl() async {
    hasAmplitudeControlCallCount++;
    return hasAmplitudeControlValue;
  }

  @override
  Future<bool> hasCustomVibrationsSupport() async => true;

  @override
  Future<void> vibrate({
    int duration = 500,
    List<int> pattern = const [],
    int repeat = -1,
    List<int> intensities = const [],
    int amplitude = -1,
  }) async {
    if (vibrateError != null) throw vibrateError!;
    calls.add(VibrateCall(
      duration: duration,
      pattern: pattern,
      repeat: repeat,
      intensities: intensities,
      amplitude: amplitude,
    ));
  }

  @override
  Future<void> cancel() async {}
}
