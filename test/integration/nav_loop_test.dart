// Full onboarding -> home -> settings -> back nav loop with every platform
// channel faked (depth, vibration, permission, prefs). This is a fast,
// repeatable complement to the test matrix in HAPTICWAY_CODING_TODO.md §9 —
// it does NOT satisfy hard constraint C8 (airplane-mode nav loop). That
// requires one manual run on the physical Samsung Galaxy S20 Ultra with real
// ARCore depth, real vibration hardware, and true radio-off state, which
// can't be meaningfully faked. C4 (no network calls in the nav loop) is
// separately enforced by the `git grep` exit check in §5.7; this test's
// contribution to that is simply that the whole loop below completes without
// ever hitting an unmocked platform channel.
//
// Run on a connected Android device/emulator:
//   flutter test integration_test/nav_loop_test.dart -d <device-id>

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/ui/home_screen.dart';
import 'package:hapticway/ui/onboarding_screen.dart';
import 'package:hapticway/ui/settings_screen.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/ar_depth_channel_mocks.dart';
import '../support/fake_detection_source.dart';
import '../support/fake_permission_platform.dart';
import '../support/fake_vibration_platform.dart';

const _agreeButtonText = '✓  I AGREE — GET STARTED';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakePermissionHandlerPlatform fakePermission;

  setUp(() {
    fakePermission = FakePermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = fakePermission;
    VibrationPlatform.instance = FakeVibrationPlatform();
    ArDepthChannelMock().install();
    SharedPreferences.setMockInitialValues({});
  });

  // Deliberately no tearDown() uninstalling the depth mock: HomeScreen's
  // depth-poll timer can still have a call in flight at dispose time, and
  // each test's setUp() already installs a fresh handler that overwrites the
  // previous one, so leaving the last handler in place between tests is
  // harmless and avoids a stray post-dispose MissingPluginException.

  testWidgets(
    'onboarding grant -> home -> settings persists a change -> back, fully offline',
    (tester) async {
      fakePermission.statusToReturn = PermissionStatus.granted;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingScreen(homeDetectionSource: FakeDetectionSource()),
      ));

      await tester.ensureVisible(find.text(_agreeButtonText));
      await tester.tap(find.text(_agreeButtonText));
      await tester.pump(); // resolve permission grant + prefs write
      await tester.pump(const Duration(milliseconds: 500)); // finish route transition

      expect(find.byType(HomeScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Open settings'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^Standard preset')));
      await tester.pump();

      // Settings persistence (spec §9 "settings persistence"): the choice
      // must be written through immediately, independent of when/whether the
      // user navigates back — check the same mock SharedPreferences store
      // HomeScreen will re-read from on the next _loadPrefs() call.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kPrefKeyHapticK), 0.5);

      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pump(const Duration(milliseconds: 500)); // finish pop transition
      // skipOffstage:false — a covered route is legitimately reported as
      // "offstage" by the default finder while merely obscured; what matters
      // here is that Settings is actually popped (removed), not just hidden.
      expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);
      expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // dispose -> cancel HomeScreen's timers
    },
  );

  testWidgets('permission denial keeps the user on onboarding', (tester) async {
    fakePermission.statusToReturn = PermissionStatus.denied;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(homeDetectionSource: FakeDetectionSource()),
    ));

    await tester.ensureVisible(find.text(_agreeButtonText));
    await tester.tap(find.text(_agreeButtonText));
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });
}
