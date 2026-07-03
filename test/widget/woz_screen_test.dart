import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/haptics/haptic_engine.dart';
import 'package:hapticway/research/woz_screen.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/fake_vibration_platform.dart';

void main() {
  late FakeVibrationPlatform fakeVibration;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HapticEngine.reset();
    StatusAnnouncer.reset();
    fakeVibration = FakeVibrationPlatform();
    VibrationPlatform.instance = fakeVibration;
  });

  Widget buildApp() => const MaterialApp(home: WozScreen());

  testWidgets('injecting with LEFT selected fires the two-pulse tacton and announces', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump(); // drain _loadK

    await tester.tap(find.text('LEFT'));
    await tester.pump();
    await tester.tap(find.text('person'));
    await tester.pump();

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.pattern, [0, 80, 80, 80]);
    expect(StatusAnnouncer.lastAnnounced, 'person on your left');
    expect(find.textContaining('SIM  person LEFT'), findsOneWidget);
  });

  testWidgets('default direction AHEAD fires the single throttled pulse', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text('person'));
    await tester.pump();

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.duration, 200);
    expect(StatusAnnouncer.lastAnnounced, 'person ahead');
  });
}
