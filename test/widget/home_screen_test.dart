import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/haptics/haptic_engine.dart';
import 'package:hapticway/inference/detection.dart';
import 'package:hapticway/ui/home_screen.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';
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

Detection _offCentreDetection(double left, double right) => Detection(
      label: 'door',
      confidence: 0.9,
      bbox: Rect.fromLTRB(left, 0.4, right, 0.6),
      timestamp: DateTime.now(),
    );

void main() {
  late ArDepthChannelMock depthMock;
  late FakeDetectionSource fakeDetectionSource;
  late FakeVibrationPlatform fakeVibration;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HapticEngine.reset(); // static throttle window must not bleed across tests
    StatusAnnouncer.reset(); // static last-announced label must not bleed across tests
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

  // ── Directional tactons (off-centre detections) ───────────────────────────

  testWidgets('a left-third stable detection fires the two-pulse tacton', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]); // centre-x 0.15
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.pattern, [0, 80, 80, 80]); // 2 pulses = left
    expect(find.textContaining('left'), findsOneWidget); // status shows direction

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a right-third stable detection fires the three-pulse tacton', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.75, 0.95)]); // centre-x 0.85
      await tester.pump();
    }
    await tester.pump();

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.pattern, [0, 60, 60, 60, 60, 60]); // 3 = right
    expect(find.textContaining('right'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a centre detection fires no directional pattern', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_personDetection()]); // centre-x 0.5
      await tester.pump();
    }
    await tester.pump();

    expect(fakeVibration.calls.where((c) => c.pattern.isNotEmpty), isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a far off-centre detection fires its pattern at the legibility floor', (tester) async {
    depthMock.depthMeters = 3.0; // plain curve gives 0.056 — uncountable pulses
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]);
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.pattern, [0, 80, 80, 80]);
    expect(fakeVibration.calls.single.intensities,
        [0, 153, 0, 153]); // kDirectionalAmplitudeFloor 0.6 * 255
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('radar ticks inside the quiet window cannot stomp on a directional pattern', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]);
      await tester.pump();
    }
    await tester.pump(); // directional pattern fires
    expect(fakeVibration.calls, hasLength(1));

    // Two radar ticks land within the pattern's quiet window (HapticEngine
    // runs on the real stopwatch, so pumped time is near-instant for it):
    // both must be dropped — Android vibrate() would cancel the playing
    // pattern and the count would become unreadable.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeVibration.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('override on suppresses the directional tacton but keeps the info', (tester) async {
    SharedPreferences.setMockInitialValues({kPrefKeyOverride: true});
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]);
      await tester.pump();
    }
    await tester.pump();

    expect(fakeVibration.calls, isEmpty); // no haptic of any kind
    expect(find.textContaining('left'), findsOneWidget); // status/TTS still inform

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a WoZ session in progress mutes real directional tactons', (tester) async {
    // depthMock.depthMeters stays at its default (-1.0, no valid reading)
    // through the 3-finger hold below, so the still-live 300ms centre-window
    // depth-poll radar cannot fire a legitimate pulse in that window and
    // contaminate the isEmpty assertion — this test is about the directional
    // tacton path specifically.
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    // Simulate a researcher's 3-finger long press: three simultaneous
    // pointers held for the 800ms trigger window, opening the WoZ panel.
    final pointers = [
      await tester.startGesture(const Offset(100, 200)),
      await tester.startGesture(const Offset(400, 200)),
      await tester.startGesture(const Offset(700, 200)),
    ];
    await tester.pump(const Duration(milliseconds: 800)); // crosses the long-press trigger
    await tester.pump(); // Navigator.push starts building the WozScreen route
    await tester.pump(); // WozScreen's _loadK() prefs await resolves
    for (final p in pointers) {
      await p.up();
    }
    await tester.pump();

    // Now that the WoZ panel is open (and the depth-poll timer cancelled),
    // give depth a real reading so the off-centre detections below have
    // everything they need to fire a directional tacton if the _wozOpen gate
    // were missing.
    depthMock.depthMeters = 1.0;

    // Real off-centre detections keep arriving under the pushed route.
    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]);
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve

    expect(fakeVibration.calls, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  // ── Settings route mutes live haptics (same contract as the WoZ panel) ────

  testWidgets('opening Settings pauses the depth-poll radar and resumes on return', (tester) async {
    // depthMock.depthMeters stays at its default (-1.0) until Settings is
    // open, so the radar cannot fire during navigation and contaminate the
    // isEmpty assertion below.
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    await tester.tap(find.bySemanticsLabel('Open settings').first);
    await tester.pump(); // Navigator.push starts building the Settings route
    await tester.pump(); // SettingsScreen's _loadPrefs await resolves

    // A close obstacle appears while Settings is open: the radar must stay
    // silent — the user is configuring haptics, often mid TEST VIBRATION.
    depthMock.depthMeters = 0.5;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(fakeVibration.calls, isEmpty);

    // Returning to home restarts the radar. (Tapped by icon: inside the
    // Settings ListView the back button's semantics merge with the title
    // into one node, so a label finder cannot target the button itself.)
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump(); // pop completes the route future
    await tester.pump(); // .then callback restarts the poll timer
    await tester.pump(const Duration(milliseconds: 300)); // next radar tick
    expect(fakeVibration.calls, hasLength(1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Settings open mutes real directional tactons', (tester) async {
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    await tester.tap(find.bySemanticsLabel('Open settings').first);
    await tester.pump();
    await tester.pump();

    // Off-centre detections keep arriving under the pushed route; without a
    // settings gate on _applyDetection they would fire the directional tacton.
    depthMock.depthMeters = 1.0;
    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.05, 0.25)]);
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve

    expect(fakeVibration.calls, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('boundary jitter within the hysteresis margin cannot flip the direction announcement', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    // Establish a stable left detection (centre-x 0.30).
    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_offCentreDetection(0.20, 0.40)]);
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve
    expect(StatusAnnouncer.lastAnnounced, 'door on your left');

    // Jitter across the 0.35 boundary but inside the hysteresis margin
    // (0.34 and 0.36) — without hysteresis, the 0.36 frame reclassifies as
    // 'ahead' and announces 'door ahead'.
    for (var i = 0; i < 4; i++) {
      final centerX = i.isEven ? 0.34 : 0.36;
      fakeDetectionSource.addDetections(
          [_offCentreDetection(centerX - 0.10, centerX + 0.10)]);
      await tester.pump();
    }
    await tester.pump();

    expect(StatusAnnouncer.lastAnnounced, 'door on your left');

    await tester.pumpWidget(const SizedBox());
  });

  // ── TalkBack announcement flood (§7.4 pre-audit finding) ──────────────────
  // The status card was a liveRegion bound to text that mutates at frame rate
  // (EMA'd confidence %, depth, and an instant flip back to 'Scanning…' on any
  // empty frame). TalkBack speaks every live-region label change with no
  // throttle, so the speech queue backed up: delayed, repeated announcements.
  // Spoken status must flow ONLY through StatusAnnouncer's 1500 ms funnel.

  testWidgets('status card is not a live region — churning text cannot bypass the announcer', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Scanning')));
    expect(node.flagsCollection.isLiveRegion, isFalse);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a brief detection dropout does not flip the status back to Scanning', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_personDetection()]);
      await tester.pump();
    }
    await tester.pump(); // let _applyDetection's depth-channel await resolve
    expect(find.textContaining('person detected'), findsOneWidget);

    // A single empty frame is bbox jitter, not a departed obstacle.
    fakeDetectionSource.addDetections([]);
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild with whatever the handler decided
    expect(find.textContaining('person detected'), findsOneWidget);

    // kDetectionLossFrames consecutive empties cross the loss threshold.
    for (var i = 1; i < kDetectionLossFrames; i++) {
      fakeDetectionSource.addDetections([]);
      await tester.pump();
    }
    await tester.pump(); // deliver + rebuild after the threshold frame
    expect(find.textContaining('person detected'), findsNothing);
    expect(find.textContaining('Scanning'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning to Scanning announces once through the throttled announcer', (tester) async {
    depthMock.depthMeters = 1.0;
    await tester.pumpWidget(buildApp());
    await settleInit(tester);

    for (var i = 0; i < kDetectionStabilityFrames; i++) {
      fakeDetectionSource.addDetections([_personDetection()]);
      await tester.pump();
    }
    await tester.pump();
    expect(StatusAnnouncer.lastAnnounced, 'person ahead');

    for (var i = 0; i < kDetectionLossFrames; i++) {
      fakeDetectionSource.addDetections([]);
      await tester.pump();
    }
    await tester.pump(); // deliver the final stream event
    expect(StatusAnnouncer.lastAnnounced, 'Scanning…');

    await tester.pumpWidget(const SizedBox());
  });
}
