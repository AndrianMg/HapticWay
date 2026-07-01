import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/core/constants.dart';
import 'package:hapticway/ui/home_screen.dart';
import 'package:hapticway/ui/onboarding_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/ar_depth_channel_mocks.dart';
import '../support/fake_detection_source.dart';
import '../support/fake_permission_platform.dart';

const _agreeButtonText = '✓  I AGREE — GET STARTED';

void main() {
  late FakePermissionHandlerPlatform fakePermission;
  late ArDepthChannelMock depthMock;
  late FakeDetectionSource fakeDetectionSource;

  setUp(() {
    fakePermission = FakePermissionHandlerPlatform();
    PermissionHandlerPlatform.instance = fakePermission;
    depthMock = ArDepthChannelMock()..install();
    fakeDetectionSource = FakeDetectionSource();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => depthMock.uninstall());

  Widget buildApp() => MaterialApp(
        home: OnboardingScreen(homeDetectionSource: fakeDetectionSource),
      );

  testWidgets('safety notice is present with an accessible label', (tester) async {
    await tester.pumpWidget(buildApp());
    expect(find.bySemanticsLabel(RegExp(r'^Safety notice\.')), findsOneWidget);
  });

  testWidgets('onboarding sections have an ascending focus order', (tester) async {
    await tester.pumpWidget(buildApp());
    final numbers = tester
        .widgetList<FocusTraversalOrder>(find.byType(FocusTraversalOrder))
        .map((w) => (w.order as NumericFocusOrder).order)
        .toList();
    expect(numbers, isNotEmpty);
    for (var i = 1; i < numbers.length; i++) {
      expect(numbers[i], greaterThan(numbers[i - 1]));
    }
  });

  testWidgets(
    'grant path persists onboarding-complete and navigates to HomeScreen',
    (tester) async {
      fakePermission.statusToReturn = PermissionStatus.granted;
      await tester.pumpWidget(buildApp());

      await tester.ensureVisible(find.text(_agreeButtonText));
      await tester.tap(find.text(_agreeButtonText));
      await tester.pump(); // resolve the permission request + prefs write
      await tester.pump(const Duration(milliseconds: 500)); // finish route transition

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefKeyOnboardingComplete), isTrue);

      // Unmount so HomeScreen.dispose() cancels its depth-poll timer.
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('denial path shows an error and does not navigate', (tester) async {
    fakePermission.statusToReturn = PermissionStatus.denied;
    await tester.pumpWidget(buildApp());

    await tester.ensureVisible(find.text(_agreeButtonText));
    await tester.tap(find.text(_agreeButtonText));
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.textContaining('Camera permission is required'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPrefKeyOnboardingComplete), isNot(true));
  });
}
