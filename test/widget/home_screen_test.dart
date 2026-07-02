import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/haptics/haptic_engine.dart';
import 'package:hapticway/inference/detection.dart';
import 'package:hapticway/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/ar_depth_channel_mocks.dart';
import '../support/fake_detection_source.dart';
import '../support/fake_vibration_platform.dart';

Detection _personDetection() => Detection(
      label: 'person',
      confidence: 0.9,
      bbox: const Rect.fromLTRB(0.4, 0.4, 0.6, 0.6),
      timestamp: DateTime.now(),
    );

void main() {
  late ArDepthChannelMock depthMock;
  late FakeDetectionSource fakeDetectionSource;
  late FakeVibrationPlatform fakeVibration;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HapticEngine.reset(); // static throttle window must not bleed across tests
    depthMock = ArDepthChannelMock()..install();
    fakeDetectionSource = FakeDetectionSource();
    fakeVibration = FakeVibrationPlatform();
    VibrationPlatform.instance = fakeVibration;
  });

  tearDown(() => depthMock.uninstall());

  Widget buildApp() => MaterialApp(
        home: HomeScreen(detectionSource: fakeDetectionSource),
      );

  // Drains the _initAr()/_loadPrefs() async chain without pumpAndSettle,
  // which would loop forever against the 300ms depth-poll periodic timer.
  Future<void> settleInit(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('viewfinder, status card, and haptic bar build correctly', (tester) async {
    depthMock.textureId = 7;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    expect(find.byType(Texture), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Scanning')), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // dispose -> cancel timers
  });

  testWidgets('status only updates after kDetectionStabilityFrames identical labels', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    // 3 frames of the same label: below the stability threshold (4).
    for (var i = 0; i < 3; i++) {
      fakeDetectionSource.addDetections([_personDetection()]);
      await tester.pump();
    }
    expect(find.textContaining('person'), findsNothing);

    // 4th consecutive frame crosses the threshold.
    fakeDetectionSource.addDetections([_personDetection()]);
    await tester.pump();
    await tester.pump(); // let _applyDetection's depth-channel await resolve

    expect(find.textContaining('person detected'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the depth-poll timer fires Tacton.obstacleAhead scaled by distance', (tester) async {
    depthMock.depthMeters = 0.5; // close range -> saturated amplitude
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    await tester.pump(const Duration(milliseconds: 300)); // one depth-poll tick

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.duration, 200);
    expect(fakeVibration.calls.single.amplitude, 255); // amplitudeFor(0.5, k=0.5) saturates to 1.0

    await tester.pumpWidget(const SizedBox());
  });

  // ── App-lifecycle handling (the pocket-vibration fix) ─────────────────────

  testWidgets('backgrounding the app stops the pipeline and all haptics', (tester) async {
    depthMock.depthMeters = 0.5; // close range -> vibrates every allowed tick
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    await tester.pump(const Duration(milliseconds: 300)); // one depth-poll tick
    expect(fakeVibration.calls, hasLength(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(); // drain _stopPipeline's async teardown

    // Two more would-be poll ticks: nothing may vibrate in the pocket.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeVibration.calls, hasLength(1));
    expect(fakeDetectionSource.stopped, isTrue);
    expect(depthMock.calls.where((c) => c.method == 'stop'), isNotEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resuming the app restarts the pipeline', (tester) async {
    depthMock.depthMeters = 0.5;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleInit(tester);

    expect(fakeDetectionSource.startCount, 2);
    expect(depthMock.calls.where((c) => c.method == 'start').length, 2);

    // Depth polling resumes: the haptic bar level rises on the next tick.
    // (Asserted via UI state, not the vibration call, because HapticEngine's
    // 500 ms wall-clock throttle may still cover this instant.)
    await tester.pump(const Duration(milliseconds: 300));
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator));
    expect(bar.value, greaterThan(0));

    await tester.pumpWidget(const SizedBox());
  });

  // ── Init failure surfaces an error UI instead of an eternal spinner ───────

  testWidgets('native start failure shows the no-camera icon, not the spinner', (tester) async {
    depthMock.startError = PlatformException(code: 'AR_UNAVAILABLE');
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    expect(find.byIcon(Icons.no_photography_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('null texture id from native start shows the error UI', (tester) async {
    depthMock.startReturnsNull = true;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    expect(find.byIcon(Icons.no_photography_outlined), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a detection stream error updates status instead of crashing', (tester) async {
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    fakeDetectionSource.addDetectionError(StateError('isolate died'));
    await tester.pump(); // deliver the stream error (microtask)
    await tester.pump(); // rebuild with the updated status

    expect(find.textContaining('Detection unavailable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('override toggle persists the pref and suppresses obstacleAhead at close range', (tester) async {
    depthMock.depthMeters = 0.5; // close range -> would otherwise fire every tick
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    await tester.tap(find.bySemanticsLabel(RegExp('^Haptic override')));
    await tester.pump(); // manualOverrideOn's vibrate call + pref write

    expect(fakeVibration.calls, hasLength(1)); // only the toggle's confirmation buzz
    expect(fakeVibration.calls.single.duration, 400);
    expect(fakeVibration.calls.single.amplitude, 230);

    await tester.pump(const Duration(milliseconds: 300)); // a depth-poll tick while override is on
    expect(fakeVibration.calls, hasLength(1)); // no obstacleAhead added

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPrefKeyOverride), isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
