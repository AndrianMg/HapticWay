# HapticWay

An offline-first Android navigation aid for visually impaired university students. The app uses the rear camera and ARCore depth sensing to detect six navigation-relevant obstacle classes, then delivers real-time haptic (vibration) feedback — stronger vibration as obstacles get closer — plus spoken announcements through the platform screen reader. No network connection is used or required; all processing happens on the device.

**University project** — developed as part of a 15-week research & implementation proposal.

---

## Status

| Phase | Section | Description | Status |
| --- | --- | --- | --- |
| 2 | §4.1 | Flutter scaffold, dependencies, AndroidManifest | ✅ Done |
| 2 | §4.2 | Personas & user stories | ✅ Done |
| 2 | §4.3 | Accessibility-first wireframes | ✅ Done |
| 2 | §4.4 | Clickable prototype (three screens) | ✅ Done |
| 2 | §4.5 | Wizard-of-Oz haptic prototype | ✅ Done |
| 2 | §4.6 | Manual WCAG 2.1 audit — 12/12 cells passing, code-referenced (`docs/wcag_audit.md`) | ✅ Done |
| 3 | §5.1–§5.5 | Inference pipeline (camera isolate + TFLite + latency benchmark) | ✅ Done |
| 3 | §5.6 | Custom YOLOv8n model — 6 navigation classes | ✅ Done |
| 4 | §6.1 | ARCore depth integration (hardware time-of-flight) | ✅ Done |
| 4 | §6.2 | Inverse-square haptic mapping + depth-poll radar | ✅ Done |
| 4 | §6.3 | Domain-capture retrain (mAP50 0.370) + rotation/letterbox preprocessing fixes | ✅ Done |
| 4 | §6.4 | Wizard-of-Oz blindfold testing harness | ✅ Done |
| 4 | §6.5 | Haptic tuning (sensitivity slider, presets) + directional tactons | ✅ Done |
| 4 | §6.6 | Phase 4 exit checks (offline, latency, memory soak) | ✅ Done |
| — | — | Security & QA audit — app-lifecycle fix, guarded haptic funnel, hardened release build | ✅ Done |
| 5 | §7.1 | Ethics, DPIA & consent (Form RE1) | 📝 Submitted, awaiting sign-off |
| 5 | §7.2 | User testing sessions (visually impaired participants) | ⏳ Not started — blocked on §7.1 |
| 5 | §7.3 | Latency benchmark report (profile build, condition grid) | ✅ Done |
| 5 | §7.4 | Live accessibility pass with TalkBack | ✅ Informal on-device passes done — see [Accessibility](#accessibility) |

### Automated tests & verification

- **132 unit and widget tests**, plus 2 device-only integration tests, all green (`flutter test test/unit test/widget`; `flutter analyze` clean)
- Every field-found defect (screen-timeout pipeline stall, TalkBack announcement flood, detection speech leaking under Settings, dead controls under TalkBack, the app-backgrounding "pocket vibration" bug) was reproduced as a failing test before being fixed
- The release build was verified directly, not just its source: the merged and packaged release manifests request only `CAMERA` and `VIBRATE`, `android.permission.INTERNET` is absent from every release-variant artefact (including the compiled `AndroidManifest.xml` inside the APK itself), and `android:allowBackup="false"` is set

### Known limitations

- No evaluation has yet been conducted with visually impaired participants. The Wizard-of-Oz protocol, consent materials and Data Protection Impact Assessment are complete; recruitment depends on departmental ethics sign-off (§7.1).
- The `bench` (6 validation images) and `staircase` (38) classes have small validation sets — their per-class accuracy figures are indicative, not statistically conclusive.
- The §7.4 accessibility pass was carried out by the developer with TalkBack enabled across several on-device sessions, not as a single formal walkthrough with recorded transcripts.

---

## Requirements

- Android device, API 29+ (Android 10)
- ARCore-compatible device (required for depth sensing)
- Flutter 3.24+, Dart ≥ 3.5.0

---

## Running the app

```bash
flutter pub get
flutter run
```

Camera permission is requested on first launch via the onboarding screen.

---

## Project structure

```text
lib/
  main.dart                  # Entry point
  app.dart                   # HapticWayApp + startup router (onboarding gate)
  core/
    constants.dart           # Haptic k, distance bounds, SharedPrefs keys
    permissions.dart         # Camera permission helper
    logger.dart              # JSONL benchmark logger (debug-only, no PII)
  depth/
    ar_depth_channel.dart    # Dart-side ARCore bridge (preview texture + depth sampling)
  inference/
    camera_isolate.dart      # Background isolate running TFLite inference
    frame_preprocessor.dart  # YUV→RGB + letterbox to 320×320 model input
    tflite_runner.dart       # YOLOv8n interpreter wrapper
    postprocess.dart         # YOLO decode, confidence filter, NMS, letterbox-inverse mapping
    detection.dart           # Detection model (label, confidence, bbox)
  haptics/
    haptic_engine.dart       # Single guarded vibration funnel (throttle, failure handling)
    intensity_curve.dart     # Inverse-square amplitude A(d) = min(1, k/d²)
    tacton.dart               # Directional vibration pattern vocabulary (1/2/3-pulse)
  benchmark/
    benchmark_runner.dart    # Condition-tagged latency runs
    report_writer.dart       # Per-run CSV + cumulative summary
    timing_data.dart
  research/
    woz_screen.dart          # Hidden Wizard-of-Oz researcher panel
    woz_session_log.dart     # JSONL session logger (no PII)
    session_export.dart      # WoZ session export/share (share_plus)
  ui/
    home_screen.dart         # ARCore viewfinder, detection status, depth radar, controls
    settings_screen.dart     # Sensitivity slider, presets, benchmark conditions
    onboarding_screen.dart   # Safety notice, consent, camera permission request
    widgets/
      status_announcer.dart  # TalkBack announcement throttle (1500 ms)
      accessible_button.dart # 48 dp min-touch Semantics wrapper

android/app/src/main/kotlin/com/hapticway/hapticway/
  ArDepthChannel.kt          # ARCore EGL/GL preview + DEPTH16 decode + depth sampling
  MainActivity.kt            # Wires ArDepthChannel to the Flutter engine, keeps screen on

ml/                           # training-only, not bundled into the app (kept local)
  train_custom_model_v2.ipynb  # YOLOv8n training + domain-capture retrain (Colab)
  convert_to_tflite.py         # Export trained weights to INT8 TFLite

assets/
  models/hapticway_custom.tflite  # Shipped INT8 model — 6 classes, 320×320 input
  labels/hapticway_labels.txt     # person, bicycle, bench, chair, door, staircase

docs/
  personas.md                # User personas (Amara, David, Priya) + user stories
  wcag_audit.md               # Manual WCAG 2.1 audit (12/12 cells)
  ethics_approval.md          # Form RE1 record (§7.1)
  DPIA.md                     # Data Protection Impact Assessment (§7.1)
  consent_form.md             # Participant consent form (§7.1)
  interview_guide.md          # Pre/post-session interview protocol (§7.2)
  questionnaire.md            # System Usability Scale instrument (§7.2)
  latency_benchmark_summary_profile_20260716.csv  # §7.3 results, profile build
  resource_usage_*.csv        # CPU/memory sampling, before/after pause comparison
  wireframes/                 # ASCII wireframes with accessibility annotations

test/
  unit/       # Pure-logic tests (intensity curve, postprocess, tactons, isolate lifecycle…)
  widget/     # Screen tests including a11y semantics-action sweep
  integration/  # Full navigation-loop test — needs a physical device
  support/    # Hand-written fakes (no mockito): vibration, permissions, path provider…

tool/
  record_resources.ps1       # CPU/memory/battery sampling script
  mem_soak.ps1                # Long-running memory soak test
```

---

## Accessibility

- **WCAG 2.1 Level AA** — manual audit, 12/12 screen × POUR-principle cells passing, every verdict backed by a `file:line` code reference (`docs/wcag_audit.md`)
- **Live TalkBack use** on the physical test device surfaced and closed three defects that a static code audit cannot catch: an unthrottled live-region status card flooding the speech queue, detections speaking over the screen reader while Settings was open, and controls whose semantics carried no tap action. All three are now guarded by regression tests, including a semantics-action sweep (`test/widget/a11y_actions_test.dart`) asserting that every button/toggle exposes a tap action
- **Focus order** enforced via `FocusTraversalGroup` + `OrderedTraversalPolicy` on every screen
- **Status announcements** route through a single throttled funnel (`StatusAnnouncer`, 1500 ms identical-string suppression) — the visible status card is deliberately not a live region
- **Touch targets** ≥ 48 dp throughout; agree button is 72 dp
- **Contrast** ≥ 7:1 (WCAG 2.1 AAA) across all text/background combinations
- All decorative elements wrapped in `ExcludeSemantics`

---

## Key design decisions

| Decision | Reason |
| --- | --- |
| Offline-only, no cloud | Privacy — no images ever leave the device; verified against the built release APK, not just asserted |
| Two independent feedback channels | The haptic radar (depth-poll) never waits on ML inference, so a plain wall — which the six-class detector doesn't recognise — still triggers a warning |
| Haptic feedback + TalkBack (no custom audio) | Works without headphones; screen-reader narration is handled by the platform, not duplicated by the app |
| Inverse-square haptic curve, A(d) = min(1, k/d²) | Concentrates the intensity gradient near the user, where reaction time is shortest — a design choice, not an empirically validated result (see the VIVA prep notes) |
| Background isolate for inference | Keeps the UI thread responsive; blocking it would freeze the interface for a user navigating largely by touch and screen reader |
| minSdk = 29 (Android 10) | Required for `vibration` amplitude control and the ARCore Depth API |
