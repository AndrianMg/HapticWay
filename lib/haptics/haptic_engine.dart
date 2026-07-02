import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../ui/widgets/status_announcer.dart';

/// Single guarded funnel for every vibration call in the app.
///
/// All `Vibration.*` calls go through here so a failing haptic path can never
/// die silently: platform errors are caught and counted, and after
/// [kFailureThreshold] consecutive failures the user is told via
/// [StatusAnnouncer] — for a blind user, silent loss of haptic feedback is
/// the worst failure mode this app has.
class HapticEngine {
  static const int _maxPulsesPerSecond = 2;

  /// Consecutive failures before 'Haptic feedback unavailable' is announced.
  static const int kFailureThreshold = 3;

  // Monotonic clock — a wall-clock (DateTime.now) throttle silently drops
  // pulses when NTP/DST adjusts the clock backwards.
  static final Stopwatch _clock = Stopwatch()..start();

  /// Elapsed-time source, injectable so tests don't need real sleeps.
  @visibleForTesting
  static Duration Function() elapsed = () => _clock.elapsed;

  static Duration? _lastPulse;
  static int _consecutiveFailures = 0;

  @visibleForTesting
  static int get consecutiveFailures => _consecutiveFailures;

  /// Rate-limited single pulse — the inference/depth-driven proximity alert.
  static Future<void> vibrate(double amplitude, Duration duration) async {
    final now = elapsed();
    if (_lastPulse != null &&
        (now - _lastPulse!).inMilliseconds < 1000 ~/ _maxPulsesPerSecond) {
      return;
    }
    try {
      // Before consuming the throttle window — a no-vibrator device must not
      // block a pulse that a later call could deliver.
      if (!await Vibration.hasVibrator()) return;
      _lastPulse = now;
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      final amplitudeInt = hasAmplitude
          ? (amplitude * 255).round().clamp(1, 255)
          : -1; // -1 = device default amplitude
      await Vibration.vibrate(
        duration: duration.inMilliseconds,
        amplitude: amplitudeInt,
      );
      _consecutiveFailures = 0;
    } catch (e) {
      _recordFailure(e);
    }
  }

  /// Un-throttled multi-pulse pattern — directional tactons whose timing the
  /// per-call rate limiter would corrupt.
  static Future<void> vibratePattern({
    required List<int> pattern,
    required List<int> intensities,
  }) async {
    try {
      if (!await Vibration.hasVibrator()) return;
      await Vibration.vibrate(pattern: pattern, intensities: intensities);
      _consecutiveFailures = 0;
    } catch (e) {
      _recordFailure(e);
    }
  }

  /// Un-throttled fixed one-shot pulse — user-initiated confirmations
  /// (manual-override on/off), not inference-driven.
  static Future<void> vibrateFixed({
    required int durationMs,
    required int amplitude,
  }) async {
    try {
      if (!await Vibration.hasVibrator()) return;
      await Vibration.vibrate(duration: durationMs, amplitude: amplitude);
      _consecutiveFailures = 0;
    } catch (e) {
      _recordFailure(e);
    }
  }

  static void _recordFailure(Object e) {
    _consecutiveFailures++;
    debugPrint('HapticEngine: vibrate failed ($_consecutiveFailures): $e');
    // Announce only at the exact threshold transition, never per failure —
    // StatusAnnouncer throttles/dedupes, but the counter keeps climbing.
    if (_consecutiveFailures == kFailureThreshold) {
      StatusAnnouncer.announce('Haptic feedback unavailable');
    }
  }

  /// Clears static throttle/failure state so tests don't bleed into each
  /// other.
  @visibleForTesting
  static void reset() {
    _lastPulse = null;
    _consecutiveFailures = 0;
    elapsed = () => _clock.elapsed;
  }
}
