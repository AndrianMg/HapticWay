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
      await Tacton.obstacleRight(0.6);
      expect(HapticEngine.consecutiveFailures, 3);
      expect(StatusAnnouncer.lastAnnounced, 'Haptic feedback unavailable');
    });
  });
}
