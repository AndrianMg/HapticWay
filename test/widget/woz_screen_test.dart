import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/haptics/haptic_engine.dart';
import 'package:hapticway/research/session_export.dart';
import 'package:hapticway/research/woz_screen.dart';
import 'package:hapticway/research/woz_session_log.dart';
import 'package:hapticway/ui/widgets/status_announcer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/fake_vibration_platform.dart';
import '../support/fake_woz_session_log.dart';

void main() {
  late FakeVibrationPlatform fakeVibration;
  late FakeWozSessionLog fakeLog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HapticEngine.reset();
    StatusAnnouncer.reset();
    SessionExport.reset();
    fakeVibration = FakeVibrationPlatform();
    VibrationPlatform.instance = fakeVibration;
    fakeLog = FakeWozSessionLog();
    WozSessionLog.instance = fakeLog;
  });

  tearDown(WozSessionLog.reset);

  Widget buildApp() => const MaterialApp(home: WozScreen());

  Finder exportButton() => find.ancestor(
        of: find.byIcon(Icons.ios_share),
        matching: find.byType(IconButton),
      );

  testWidgets('injecting with LEFT selected fires the two-pulse tacton and announces', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump(); // drain _loadK

    await tester.tap(find.text('LEFT'));
    await tester.pump();
    await tester.tap(find.text('person'));
    await tester.pump();

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.pattern, [0, 80, 80, 80]);
    // Default distance chip is 1.0 m — the injection speaks it, matching the
    // live pipeline's announcement format.
    expect(StatusAnnouncer.lastAnnounced, 'person on your left, 1 metre');
    expect(find.textContaining('SIM  person LEFT'), findsOneWidget);
  });

  testWidgets('default direction AHEAD fires the single throttled pulse', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text('person'));
    await tester.pump();

    expect(fakeVibration.calls, hasLength(1));
    expect(fakeVibration.calls.single.duration, 200);
    expect(StatusAnnouncer.lastAnnounced, 'person ahead, 1 metre');
  });

  testWidgets('START prompts for a participant ID; cancel starts no session', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    expect(find.text('Anonymous participant ID'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(fakeLog.isOpen, isFalse);
    expect(fakeLog.events, isEmpty);
    expect(find.text('START'), findsOneWidget);
  });

  testWidgets('entering an ID and BEGIN opens the session with that participant', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text('START'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'P3');
    await tester.tap(find.text('BEGIN'));
    await tester.pump(); // pop the dialog, resume _toggleSession
    await tester.pump(); // rebuild with the session active
    await tester.pump(const Duration(milliseconds: 300)); // dialog exit animation

    expect(fakeLog.isOpen, isTrue);
    expect(fakeLog.events.single, {
      'event': 'session_start',
      'k': 0.5,
      'participant': 'P3',
      'condition': 'woz',
    });
    expect(find.text('END'), findsOneWidget);
    expect(find.text('Session started'), findsOneWidget);

    await tester.tap(find.text('END')); // cancel the elapsed clock
    await tester.pump();
    expect(fakeLog.isOpen, isFalse);
  });

  testWidgets('re-attaches to a running session; false positive is logged', (tester) async {
    fakeLog.seedOpen();
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // Re-attach: END button back, segment boundary marked.
    expect(find.text('END'), findsOneWidget);
    expect(fakeLog.events.last, {'event': 'phase', 'mode': 'woz'});

    final falsePositive = find.text('false positive');
    await tester.dragUntilVisible(
      falsePositive, find.byType(Scrollable).first, const Offset(0, -300),
    );
    await tester.pump();
    await tester.tap(falsePositive);
    await tester.pump();
    expect(fakeLog.events.last, {'event': 'action', 'action': 'false_positive'});

    // The drag scrolled the header away — bring END back before tapping it.
    await tester.dragUntilVisible(
      find.text('END'), find.byType(Scrollable).first, const Offset(0, 300),
    );
    await tester.pump();
    await tester.tap(find.text('END'));
    await tester.pump();
    expect(fakeLog.isOpen, isFalse);
  });

  testWidgets('participant actions stay disabled without a session', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    final falsePositive = find.widgetWithText(OutlinedButton, 'false positive');
    await tester.dragUntilVisible(
      falsePositive, find.byType(Scrollable).first, const Offset(0, -300),
    );
    await tester.pump();

    expect(tester.widget<OutlinedButton>(falsePositive).onPressed, isNull);
  });

  testWidgets('EXPORT is disabled mid-session, shares after END, KEEP retains the file', (tester) async {
    final shared = <String>[];
    SessionExport.overrideShare = (path) async {
      shared.add(path);
      return const ShareResult('ok', ShareResultStatus.success);
    };
    fakeLog.seedOpen(path: 'fake/hapticway_woz_P3_stamp.jsonl');
    await tester.pumpWidget(buildApp());
    await tester.pump();

    // Mid-session the file is incomplete — the button must be dead.
    expect(tester.widget<IconButton>(exportButton()).onPressed, isNull);

    await tester.tap(find.text('END'));
    await tester.pump();
    expect(tester.widget<IconButton>(exportButton()).onPressed, isNotNull);

    await tester.tap(exportButton());
    await tester.pumpAndSettle();
    expect(shared.single, 'fake/hapticway_woz_P3_stamp.jsonl');

    // A confirmed share surfaces the DPIA wipe prompt; KEEP deletes nothing.
    expect(find.text('Log shared'), findsOneWidget);
    await tester.tap(find.text('KEEP'));
    await tester.pumpAndSettle();
    expect(find.text('Log shared'), findsNothing);
    expect(find.text('Log deleted'), findsNothing);
  });

  testWidgets('a dismissed share sheet never reaches the delete prompt', (tester) async {
    SessionExport.overrideShare =
        (path) async => const ShareResult('', ShareResultStatus.dismissed);
    fakeLog.seedOpen();
    await tester.pumpWidget(buildApp());
    await tester.pump();

    await tester.tap(find.text('END'));
    await tester.pump();
    await tester.tap(exportButton());
    await tester.pumpAndSettle();

    expect(find.text('Log shared'), findsNothing);
  });
}
