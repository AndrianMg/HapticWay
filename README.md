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
| 3 | §5 | Inference pipeline (camera + TFLite) | 🔜 Next |
| 3 | §6 | ARCore depth integration | 🔜 Planned |

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
  haptics/
    haptic_engine.dart       # Vibration wrapper (20 Hz rate limiter)
  ui/
    home_screen.dart         # Camera viewfinder, detection status, override toggle
    settings_screen.dart     # Sensitivity slider, presets, Wizard-of-Oz buttons
    onboarding_screen.dart   # Safety notice, consent, camera permission request
    widgets/
      status_announcer.dart  # TalkBack announcement throttle (1500 ms)
      accessible_button.dart # 48 dp min-touch Semantics wrapper

docs/
  personas.md                # User personas (Amara, David, Priya) + 14 user stories
  wireframes/                # ASCII wireframes with accessibility annotations
    01_home_screen.md
    02_settings_screen.md
    03_onboarding_screen.md
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
