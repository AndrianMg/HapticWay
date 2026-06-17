# HapticWay

An offline-first Android navigation aid for visually impaired university students. The app uses the rear camera and a depth/obstacle detection model to deliver real-time haptic (vibration) feedback — stronger vibration as obstacles get closer, no internet required.

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
| 2 | §4.6 | Manual WCAG 2.1 audit (`docs/wcag_audit.md`) | ✅ Done |
| 3 | §5.1–§5.5 | Inference pipeline (camera isolate + TFLite + latency benchmark) | ✅ Done |
| 3 | §5.6 | Custom YOLOv8n model — 7 navigation classes | ✅ Done |
| 4 | §6.1 | ARCore depth integration | ✅ Done |
| 4 | §6.2 | Inverse-square haptic mapping + depth-poll radar | ✅ Done |
| 4 | §6.3 | Obstacle class set (7 classes) | ✅ Done |
| 4 | §6.4 | Wizard-of-Oz blindfold testing harness | ✅ Done |
| 4 | §6.5 | Haptic tuning (sensitivity slider, presets) | ✅ Done |
| 4 | §6.6 | Phase 4 exit checks (offline, latency, memory soak) | ✅ Done |
| 5 | §7.1 | Ethics, DPIA & consent | 📝 Awaiting signatures |
| 5 | §7.2 | User testing sessions | ⏳ Blocked on §7.1 |
| 5 | §7.3 | Latency benchmark report (condition grid) | ✅ Done |

### In progress / known issues

- **Model retraining** — the custom YOLOv8n has weak per-class accuracy
  (dead-classes training failure); retraining on Colab is the open item. The
  detection *pipeline* is correct (preprocessing + depth recently fixed below).
- **Pipeline correctness fixes (resolved):** on-device letterbox preprocessing
  (was stretching frames), and the ARCore depth sampler (coordinate mapping +
  DEPTH16 decode + robust percentile statistic).

---

## Requirements

- Android device, API 29+ (Android 10)
- ARCore-compatible device (for depth features in §6)
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
    ar_depth_channel.dart    # ARCore session bridge (preview + depth sampling)
  inference/
    camera_isolate.dart      # Background isolate running TFLite inference
    frame_preprocessor.dart  # YUV→RGB + letterbox to 320×320 model input
    tflite_runner.dart       # YOLOv8n interpreter wrapper
    postprocess.dart         # YOLO decode, NMS, letterbox-inverse box mapping
    detection.dart           # Detection model (label, confidence, bbox)
  haptics/
    haptic_engine.dart       # Vibration wrapper (rate limiter)
    intensity_curve.dart     # Inverse-square amplitude A(d) = min(1, k/d²)
    tacton.dart              # Named vibration patterns
  benchmark/
    benchmark_runner.dart    # Condition-tagged latency runs
    report_writer.dart       # Per-run CSV + cumulative summary
    timing_data.dart
  research/
    woz_screen.dart          # Hidden Wizard-of-Oz researcher panel
    woz_session_log.dart     # JSONL session logger (no PII)
  ui/
    home_screen.dart         # ARCore viewfinder, detection status, override toggle
    settings_screen.dart     # Sensitivity slider, presets, benchmark conditions
    onboarding_screen.dart   # Safety notice, consent, camera permission request
    widgets/
      status_announcer.dart  # TalkBack announcement throttle (1500 ms)
      accessible_button.dart # 48 dp min-touch Semantics wrapper

android/app/src/main/kotlin/com/hapticway/hapticway/
  ArDepthChannel.kt          # ARCore EGL/GL preview + depth16 decode + sampling

ml/
  train_custom_model.ipynb   # YOLOv8n training (Colab, Open Images v7)
  hapticway_custom.tflite    # Trained INT8 model (7 classes, 320×320)

docs/
  personas.md                # User personas (Amara, David, Priya) + user stories
  wcag_audit.md              # Manual WCAG 2.1 audit
  ethics_approval.md         # Form RE1 record (§7.1)
  DPIA.md                    # Data Protection Impact Assessment (§7.1)
  consent_form.md            # Participant consent form (§7.1)
  latency_benchmark_summary.csv  # §7.3 results across the condition grid
  wireframes/                # ASCII wireframes with accessibility annotations
```

---

## Accessibility

- **TalkBack** focus order enforced via `FocusTraversalGroup` + `NumericFocusOrder` on all screens
- **Live regions** (`Semantics(liveRegion: true)`) on detection status — auto-announced without user navigation
- **Touch targets** ≥ 48 dp throughout; agree button is 72 dp
- **Contrast** ≥ 7:1 (WCAG 2.1 AAA) across all text/background combinations
- All decorative elements wrapped in `ExcludeSemantics`

---

## Key design decisions

| Decision | Reason |
| --- | --- |
| Offline-only, no cloud | Privacy — no images leave the device |
| Haptic feedback only (no audio) | Works without headphones; audio narration handled by TalkBack |
| 20 Hz haptic rate limit | Prevents motor saturation; stays within Android vibrator budget |
| minSdk = 29 (Android 10) | Required for `vibration` amplitude control and ARCore depth API |
