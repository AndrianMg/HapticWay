import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/haptics/tacton.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/fake_vibration_platform.dart';

void main() {
  late FakeVibrationPlatform fake;

  setUp(() {
    fake = FakeVibrationPlatform();
    VibrationPlatform.instance = fake;
  });

  group('Tacton.obstacleAhead rate limiting (via HapticEngine)', () {
    // HapticEngine._lastPulse is a static field shared across tests in this
    // file, so each test starts with a >500ms real delay to guarantee it
    // isn't still inside a previous test's throttle window.
    test('a second call within 500ms is throttled', () async {
      await Future.delayed(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(1));
    });

    test('calls more than 500ms apart both go through', () async {
      await Future.delayed(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      await Future.delayed(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls, hasLength(2));
    });

    test('sends a 200ms pulse with amplitude scaled to the 1-255 motor range', () async {
      await Future.delayed(const Duration(milliseconds: 600));
      await Tacton.obstacleAhead(0.6);
      expect(fake.calls.single.duration, 200);
      expect(fake.calls.single.amplitude, 153); // (0.6 * 255).round()
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
      await Future.delayed(const Duration(milliseconds: 600));
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
}
