import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/haptics/haptic_engine.dart';
import 'package:hapticway/haptics/tacton.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/fake_vibration_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVibrationPlatform fake;

  // Fake monotonic clock injected into HapticEngine — no real sleeps needed,
  // and no static throttle state bleeding between tests.
  var fakeNow = Duration.zero;
  void advance(Duration d) => fakeNow += d;

  setUp(() {
    fake = FakeVibrationPlatform();
    VibrationPlatform.instance = fake;
    HapticEngine.reset();
    StatusAnnouncer.reset();
    fakeNow = Duration.zero;
    HapticEngine.elapsed = () => fakeNow;
  });

  tearDown(HapticEngine.reset);

  group('Tacton.obstacleAhead rate limiting (via HapticEngine)', () {
    test('a second call within 500ms is throttled', () async {
      await Tacton.obstacleAhead(0.6);
      advance(const Duration(milliseconds: 100));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(1));
    });

    test('calls more than 500ms apart both go through', () async {
      await Tacton.obstacleAhead(0.6);
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(2));
    });

    test('sends a 200ms pulse with amplitude scaled to the 1-255 motor range', () async {
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls.single.duration, 200);
      expect(fake.calls.single.amplitude, 153); // (0.6 * 255).round()
    });

    test('a no-vibrator probe does not consume the throttle window', () async {
      fake.hasVibratorValue = false;
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, isEmpty);

      // Same instant, vibrator now available: the pulse must still fire.
      fake.hasVibratorValue = true;
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(1));
    });
  });

  group('Tacton directional patterns bypass the rate limiter', () {
    test('obstacleLeft sends a two-pulse pattern', () async {
      await Tacton.obstacleLeft(0.6);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.pattern, [0, 80, 80, 80]);
      expect(fake.calls.single.intensities, [0, 153, 0, 153]);
    });

    test('obstacleRight sends a three-pulse pattern', () async {
      await Tacton.obstacleRight(0.6);
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.pattern, [0, 60, 60, 60, 60, 60]);
      expect(fake.calls.single.intensities, [0, 153, 0, 153, 0, 153]);
    });

    test('obstacleLeft immediately after a throttled obstacleAhead still fires', () async {
      await Tacton.obstacleAhead(0.6); // consumes the throttle window
      await Tacton.obstacleLeft(0.6); // unaffected — different code path
      expect(fake.calls, hasLength(2));
    });
  });

  group('Tacton manual override confirmation patterns', () {
    test('manualOverrideOn sends a fixed 400ms/230 pulse', () async {
      await Tacton.manualOverrideOn();
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.duration, 400);
      expect(fake.calls.single.amplitude, 230);
    });

    test('manualOverrideOff sends a fixed 400ms/80 pulse', () async {
      await Tacton.manualOverrideOff();
      expect(fake.calls, hasLength(1));
      expect(fake.calls.single.duration, 400);
      expect(fake.calls.single.amplitude, 80);
    });
  });

  group('HapticEngine capability caching', () {
    test('capability probes hit the platform channel once across pulses', () async {
      await Tacton.obstacleAhead(0.6);
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(2));
      expect(fake.hasVibratorCallCount, 1);
      expect(fake.hasAmplitudeControlCallCount, 1);
    });

    test('a no-vibrator result is never cached', () async {
      // A device does not grow a vibrator at runtime, but a transiently
      // failing probe must not permanently silence the app.
      fake.hasVibratorValue = false;
      await Tacton.obstacleAhead(0.6);
      expect(fake.hasVibratorCallCount, 1);

      fake.hasVibratorValue = true;
      await Tacton.obstacleAhead(0.6);
      expect(fake.hasVibratorCallCount, 2); // re-probed, then cached
      expect(fake.calls, hasLength(1));
    });
  });

  group('HapticEngine failure surfacing', () {
    test('3 consecutive failures announce "Haptic feedback unavailable"', () async {
      fake.vibrateError = PlatformException(code: 'VIBRATE_FAIL');

      await Tacton.obstacleAhead(0.6); // failure 1 — no unhandled error
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6); // failure 2
      expect(StatusAnnouncer.lastAnnounced, isNull);

      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6); // failure 3 — threshold
      expect(HapticEngine.consecutiveFailures, 3);
      expect(StatusAnnouncer.lastAnnounced, 'Haptic feedback unavailable');
    });

    test('a success resets the failure counter', () async {
      fake.vibrateError = PlatformException(code: 'VIBRATE_FAIL');
      await Tacton.obstacleAhead(0.6);
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(HapticEngine.consecutiveFailures, 2);

      fake.vibrateError = null;
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6); // success
      expect(HapticEngine.consecutiveFailures, 0);

      fake.vibrateError = PlatformException(code: 'VIBRATE_FAIL');
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      advance(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(StatusAnnouncer.lastAnnounced, isNull); // 2 < threshold again
    });

    test('pattern and fixed pulses also count failures', () async {
      fake.vibrateError = PlatformException(code: 'VIBRATE_FAIL');
      await Tacton.obstacleLeft(0.6);
      await Tacton.manualOverrideOn();
      advance(const Duration(milliseconds: 1600)); // clear the pattern cooldown
      await Tacton.obstacleRight(0.6);
      expect(HapticEngine.consecutiveFailures, 3);
      expect(StatusAnnouncer.lastAnnounced, 'Haptic feedback unavailable');
    });
  });

  group('Pattern cooldown', () {
    test('a second pattern within 1500ms is dropped', () async {
      await Tacton.obstacleLeft(0.6);
      advance(const Duration(milliseconds: 500));
      await Tacton.obstacleRight(0.6); // left and right share the window
      expect(fake.calls, hasLength(1));
    });

    test('patterns more than 1500ms apart both fire', () async {
      await Tacton.obstacleLeft(0.6);
      advance(const Duration(milliseconds: 1600));
      await Tacton.obstacleLeft(0.6);
      expect(fake.calls, hasLength(2));
    });

    test('a no-vibrator probe does not consume the pattern window', () async {
      fake.hasVibratorValue = false;
      await Tacton.obstacleLeft(0.6);
      expect(fake.calls, isEmpty);

      fake.hasVibratorValue = true;
      await Tacton.obstacleLeft(0.6);
      expect(fake.calls, hasLength(1));
    });
  });

  group('Pattern quiet window', () {
    test('a single pulse within the quiet window of a pattern is dropped', () async {
      await Tacton.obstacleLeft(0.6);
      advance(const Duration(milliseconds: 500));
      // A radar tick just after the pattern: Android vibrate() would cancel
      // the playing pattern and blur its pulse count — it must be dropped.
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(1)); // the pattern only
    });

    test('a single pulse after the quiet window fires normally', () async {
      await Tacton.obstacleLeft(0.6);
      advance(const Duration(milliseconds: 900));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(2));
    });

    test('a dropped pulse does not consume the pulse throttle window', () async {
      await Tacton.obstacleLeft(0.6);
      advance(const Duration(milliseconds: 500));
      await Tacton.obstacleAhead(0.6); // dropped by the quiet window
      advance(const Duration(milliseconds: 400)); // 900ms after the pattern
      await Tacton.obstacleAhead(0.6); // must not be throttled by the drop
      expect(fake.calls, hasLength(2));
    });
  });

  group('ObstacleDirection', () {
    test('directionForCenterX splits at the 0.35/0.65 radar-window bounds', () {
      expect(directionForCenterX(0.20), ObstacleDirection.left);
      expect(directionForCenterX(0.35), ObstacleDirection.ahead); // boundary is ahead
      expect(directionForCenterX(0.50), ObstacleDirection.ahead);
      expect(directionForCenterX(0.65), ObstacleDirection.ahead); // boundary is ahead
      expect(directionForCenterX(0.80), ObstacleDirection.right);
    });

    test('announcement phrases say where the obstacle is', () {
      expect(ObstacleDirection.left.announcement('door'), 'door on your left');
      expect(ObstacleDirection.ahead.announcement('door'), 'door ahead');
      expect(ObstacleDirection.right.announcement('door'), 'door on your right');
    });

    test('Tacton.obstacle dispatches to the matching pattern', () async {
      await Tacton.obstacle(ObstacleDirection.left, 0.6);
      expect(fake.calls.single.pattern, [0, 80, 80, 80]);

      advance(const Duration(milliseconds: 1600)); // clear pattern cooldown
      await Tacton.obstacle(ObstacleDirection.right, 0.6);
      expect(fake.calls.last.pattern, [0, 60, 60, 60, 60, 60]);

      advance(const Duration(milliseconds: 900)); // clear the quiet window
      await Tacton.obstacle(ObstacleDirection.ahead, 0.6);
      expect(fake.calls.last.duration, 200); // single throttled pulse
      expect(fake.calls, hasLength(3));
    });
  });

  group('directionWithHysteresis', () {
    test('a null previous classifies plainly (no stickiness)', () {
      expect(directionWithHysteresis(0.20, null), ObstacleDirection.left);
      expect(directionWithHysteresis(0.50, null), ObstacleDirection.ahead);
      expect(directionWithHysteresis(0.80, null), ObstacleDirection.right);
    });

    test('stays with previous while inside the hysteresis margin', () {
      expect(directionWithHysteresis(0.34, ObstacleDirection.ahead),
          ObstacleDirection.ahead);
      expect(directionWithHysteresis(0.36, ObstacleDirection.left),
          ObstacleDirection.left);
      expect(directionWithHysteresis(0.66, ObstacleDirection.ahead),
          ObstacleDirection.ahead);
      expect(directionWithHysteresis(0.64, ObstacleDirection.right),
          ObstacleDirection.right);
    });

    test('switches once the crossing is decisive (beyond the margin)', () {
      expect(directionWithHysteresis(0.30, ObstacleDirection.ahead),
          ObstacleDirection.left);
      expect(directionWithHysteresis(0.40, ObstacleDirection.left),
          ObstacleDirection.ahead);
      expect(directionWithHysteresis(0.70, ObstacleDirection.ahead),
          ObstacleDirection.right);
      expect(directionWithHysteresis(0.60, ObstacleDirection.right),
          ObstacleDirection.ahead);
    });
  });
}
