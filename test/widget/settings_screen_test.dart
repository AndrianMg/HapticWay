import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/research/woz_session_log.dart';
import 'package:hapticway/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/fake_vibration_platform.dart';
import '../support/fake_woz_session_log.dart';

// Finds the Semantics widget wrapping the sensitivity slider so tests can
// invoke its onIncrease/onDecrease callbacks directly — this exercises the
// exact production wiring without depending on the semantics-tree action
// dispatch machinery (SemanticsOwner.performAction + node id), which proved
// flaky under test-runner load since node ids aren't guaranteed stable
// across the same-frame get-then-act sequence.
Semantics _sliderSemantics(WidgetTester tester) => tester.widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Sensitivity slider',
      ),
    );

void main() {
  late FakeVibrationPlatform fakeVibration;

  setUp(() {
    fakeVibration = FakeVibrationPlatform();
    VibrationPlatform.instance = fakeVibration;
  });

  Widget buildApp() => const MaterialApp(home: SettingsScreen());

  group('sensitivity presets', () {
    for (final preset in const [('Subtle', 0.2), ('Standard', 0.5), ('Strong', 2.0)]) {
      testWidgets('tapping ${preset.$1} persists k=${preset.$2}', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        await tester.tap(find.bySemanticsLabel(RegExp('^${preset.$1} preset')));
        await tester.pumpAndSettle();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getDouble(kPrefKeyHapticK), preset.$2);
      });
    }
  });

  group('custom slider', () {
    testWidgets('onChanged rounds to 1 decimal and persists it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(0.7899999);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kPrefKeyHapticK), 0.8);
    });

    testWidgets('accessibility onIncrease clamps at the 2.0 maximum', (tester) async {
      SharedPreferences.setMockInitialValues({kPrefKeyHapticK: 2.0});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      _sliderSemantics(tester).properties.onIncrease!();
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kPrefKeyHapticK), 2.0);
    });

    testWidgets('accessibility onDecrease clamps at the 0.1 minimum', (tester) async {
      SharedPreferences.setMockInitialValues({kPrefKeyHapticK: 0.1});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      _sliderSemantics(tester).properties.onDecrease!();
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kPrefKeyHapticK), 0.1);
    });

    testWidgets('accessibility onIncrease steps by 0.1 within range', (tester) async {
      SharedPreferences.setMockInitialValues({kPrefKeyHapticK: 0.5});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      _sliderSemantics(tester).properties.onIncrease!();
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kPrefKeyHapticK), closeTo(0.6, 1e-9));
    });
  });

  testWidgets('alerts toggle persists kPrefKeyOverride (inverted)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Alerts default to on; one tap turns them off, which the pref stores
    // with the historic override polarity (true = alerts off).
    await tester.tap(find.bySemanticsLabel(RegExp('^Vibration alerts')));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPrefKeyOverride), isTrue);
  });

  group('haptic trigger buttons', () {
    testWidgets('TEST VIBRATION fires HapticEngine at current k for 300ms', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      // HapticEngine's rate limiter reads real DateTime.now(), which fake_async
      // pumping doesn't advance — runAsync forces a genuine wall-clock wait so
      // any throttle window left over from a previous test has really elapsed.
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 600)));

      await tester.tap(find.bySemanticsLabel(RegExp('^Test vibration')));
      await tester.pumpAndSettle();

      expect(fakeVibration.calls, hasLength(1));
      expect(fakeVibration.calls.single.duration, 300);
      expect(fakeVibration.calls.single.amplitude, 128); // (0.5 * 255).round()
    });

    testWidgets('WoZ Strong pulse button fires 0.8 amplitude for 200ms', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 600)));

      final strongPulse = find.bySemanticsLabel(RegExp('^Strong pulse'));
      await tester.dragUntilVisible(
        strongPulse, find.byType(Scrollable).first, const Offset(0, -300),
      );
      await tester.pumpAndSettle(); // let the ensureVisible scroll animation finish
      await tester.tap(strongPulse);
      await tester.pumpAndSettle();

      expect(fakeVibration.calls, hasLength(1));
      expect(fakeVibration.calls.single.duration, 200);
      expect(fakeVibration.calls.single.amplitude, 204); // (0.8 * 255).round()
    });

    testWidgets('manual pulse lands in an active WoZ session log (§7.2)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeLog = FakeWozSessionLog()..seedOpen();
      WozSessionLog.instance = fakeLog;
      addTearDown(WozSessionLog.reset);

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 600)));

      final maxPulse = find.bySemanticsLabel(RegExp('^Max pulse'));
      await tester.dragUntilVisible(
        maxPulse, find.byType(Scrollable).first, const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(maxPulse);
      await tester.pumpAndSettle();

      expect(fakeVibration.calls, hasLength(1)); // still vibrates
      expect(fakeLog.events.single,
          {'event': 'manual_pulse', 'amplitude': 1.0, 'duration_ms': 200});
    });
  });

  testWidgets('benchmark button pops the selected lighting_scene condition', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? popped;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            popped = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    final dimChip = find.widgetWithText(ChoiceChip, 'dim');
    await tester.dragUntilVisible(dimChip, scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(dimChip);
    await tester.pumpAndSettle();

    final crowdedChip = find.widgetWithText(ChoiceChip, 'crowded');
    await tester.dragUntilVisible(crowdedChip, scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(crowdedChip);
    await tester.pumpAndSettle();

    final benchmarkButton = find.textContaining('START BENCHMARK');
    await tester.dragUntilVisible(benchmarkButton, scrollable, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(benchmarkButton);
    await tester.pumpAndSettle();

    expect(popped, 'dim_crowded');
  });
}
