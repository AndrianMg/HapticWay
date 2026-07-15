import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hapticway/ui/home_screen.dart';
import 'package:hapticway/ui/onboarding_screen.dart';
import 'package:hapticway/ui/settings_screen.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration_platform_interface/vibration_platform_interface.dart';

import '../support/ar_depth_channel_mocks.dart';
import '../support/fake_detection_source.dart';
import '../support/fake_permission_platform.dart';
import '../support/fake_vibration_platform.dart';

// Field finding (§7.4 family): a control whose Semantics wrapper uses
// excludeSemantics discards the child's tap action — the node then claims to
// be a button/toggle but TalkBack's double-tap (SemanticsAction.tap on the
// focused node) has nothing to invoke. Pointer-tap tests never catch this,
// so every screen gets a sweep: any node presented as activatable must carry
// an explicit tap action.
void main() {
  late ArDepthChannelMock depthMock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    depthMock = ArDepthChannelMock()..install();
    VibrationPlatform.instance = FakeVibrationPlatform();
    PermissionHandlerPlatform.instance = FakePermissionHandlerPlatform();
  });

  tearDown(() => depthMock.uninstall());

  void expectAllControlsActivatable(WidgetTester tester) {
    var controls = 0;
    for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
      final data = node.getSemanticsData();
      // Toggled state is a Tristate in the flags collection: `none` means
      // "not a toggle", isTrue/isFalse mean the node presents as a switch.
      final activatable = data.flagsCollection.isButton ||
          data.flagsCollection.isToggled != Tristate.none;
      if (!activatable) continue;
      controls++;
      expect(data.hasAction(SemanticsAction.tap), isTrue,
          reason: 'Control "${data.label}" has no semantics tap action — '
              'dead under TalkBack double-tap');
    }
    expect(controls, greaterThan(0),
        reason: 'sweep found no controls — traversal is broken');
  }

  testWidgets('every home-screen control has a semantics tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(detectionSource: FakeDetectionSource()),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expectAllControlsActivatable(tester);

    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every settings-screen control has a semantics tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();

    expectAllControlsActivatable(tester);

    semantics.dispose();
  });

  testWidgets('every onboarding-screen control has a semantics tap action', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(homeDetectionSource: FakeDetectionSource()),
    ));
    await tester.pumpAndSettle();

    expectAllControlsActivatable(tester);

    semantics.dispose();
  });
}
