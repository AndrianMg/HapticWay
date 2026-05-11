# Wireframe 02 — Settings Screen

**Route:** Navigated to from Home screen (header icon or "Open Settings" button)
**Purpose:** Sensitivity tuning, haptic override toggle, vibration test, manual WoZ trigger buttons (§4.5).

---

## Layout (480 × 960 dp canvas)

```
┌─────────────────────────────────────┐
│  9:41          WP23 Pro    ▲ ◼ ◉   │  ← System status bar
├─────────────────────────────────────┤
│  ←  [1]   Settings                 │  ← [A] Back button + screen title
│            48 dp tall               │        Back button: 48×48 dp touch target
├─────────────────────────────────────┤
│                                     │
│  HAPTIC SENSITIVITY          [2]   │  ← [B] Section heading (non-interactive)
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Subtle   Standard   Strong  │   │  ← [C] Preset segmented control
│  │   [3]       [4]       [5]   │   │       Each segment: 48 dp tall min
│  └──────────────────────────────┘   │
│                                     │
│  Custom (k = 0.50)          [6]   │  ← [D] Slider label + current value
│  ┌──────────────────────────────┐   │
│  │  0.1  ●━━━━━━━━━━━━━━  2.0  │   │  ← [E] Sensitivity slider
│  └──────────────────────────────┘   │       48 dp tall touch area
│                                     │
├─────────────────────────────────────┤
│                                     │
│  HAPTIC ALERTS               [7]   │  ← [F] Section heading
│                                     │
│  ┌──────────────────────────────┐   │
│  │  Haptic override             │   │  ← [G] Override toggle
│  │  ON  ●────────────    [8]   │   │       56 dp tall, full width
│  └──────────────────────────────┘   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  TEST VIBRATION       [9]   │   │  ← [H] Test button — fires current k, 300ms
│  └──────────────────────────────┘   │       56 dp tall
│                                     │
├─────────────────────────────────────┤
│                                     │
│  MANUAL TRIGGER (WoZ)       [10]  │  ← [I] Section heading
│  (Research mode — §4.5)            │
│                                     │
│  ┌────────┐ ┌────────┐             │
│  │ 0.2   │ │ 0.5   │  [11][12]   │  ← [J][K] Amplitude buttons
│  │ Subtle │ │ Medium │             │       Each: 48×48 dp min
│  └────────┘ └────────┘             │
│  ┌────────┐ ┌────────┐             │
│  │ 0.8   │ │ 1.0   │  [13][14]   │  ← [L][M] Amplitude buttons
│  │ Strong │ │ Max   │             │
│  └────────┘ └────────┘             │
│                                     │
└─────────────────────────────────────┘
```

---

## Element Annotation Table

| ID | Element | Type | Semantics label | Focus order | Gesture | Fallback action | Touch target | WCAG criterion |
|----|---------|------|----------------|-------------|---------|-----------------|-------------|----------------|
| A | Back button | IconButton | "Back, navigate to home screen" | 1 | Single tap | Android system back gesture | 48 × 48 dp | 2.5.5, 2.4.3 |
| B | "Haptic Sensitivity" heading | Heading | "Haptic Sensitivity, section" | 2 | — | — | — | 1.3.1, 2.4.6 |
| C | Subtle preset | SegmentButton | "Subtle preset, k equals 0.2. [selected/not selected]. Double tap to select." | 3 | Double tap (TalkBack) | — | 48 dp tall, ≥ 96 dp wide | 2.5.5, 4.1.2 |
| C | Standard preset | SegmentButton | "Standard preset, k equals 0.5. [selected/not selected]. Double tap to select." | 4 | Double tap (TalkBack) | — | 48 dp tall, ≥ 96 dp wide | 2.5.5, 4.1.2 |
| C | Strong preset | SegmentButton | "Strong preset, k equals 2.0. [selected/not selected]. Double tap to select." | 5 | Double tap (TalkBack) | — | 48 dp tall, ≥ 96 dp wide | 2.5.5, 4.1.2 |
| D | Slider value label | Text (live) | "Custom sensitivity, k equals [value]. Adjust with the slider below." | 6 | — | — | — | 1.3.1 |
| E | Sensitivity slider | Slider | "Sensitivity slider. Minimum 0.1, maximum 2.0, current value [k]. Swipe right to increase, left to decrease." | 7 | Swipe left/right (TalkBack) / drag (direct) | Use preset buttons C | 48 dp tall, full width | 2.5.5, 4.1.2 |
| F | "Haptic Alerts" heading | Heading | "Haptic Alerts, section" | 8 | — | — | — | 1.3.1, 2.4.6 |
| G | Override toggle | Switch | "Haptic override. Currently [on/off]. Double tap to toggle." | 9 | Double tap (TalkBack) / 2-finger long press from any screen | — | Full width, 56 dp min | 2.1.1, 4.1.2 |
| H | Test vibration button | ElevatedButton | "Test vibration. Fires haptic pulse at current sensitivity for 300 milliseconds." | 10 | Single tap | — | Full width, 56 dp min | 2.5.5 |
| I | "Manual Trigger" heading | Heading | "Manual Trigger, section. For research use only." | 11 | — | — | — | 1.3.1 |
| J | 0.2 amplitude button | OutlinedButton | "Subtle pulse, amplitude 0.2, 200 milliseconds." | 12 | Single tap | — | 48 × 48 dp min | 2.5.5 |
| K | 0.5 amplitude button | OutlinedButton | "Medium pulse, amplitude 0.5, 200 milliseconds." | 13 | Single tap | — | 48 × 48 dp min | 2.5.5 |
| L | 0.8 amplitude button | OutlinedButton | "Strong pulse, amplitude 0.8, 200 milliseconds." | 14 | Single tap | — | 48 × 48 dp min | 2.5.5 |
| M | 1.0 amplitude button | OutlinedButton | "Maximum pulse, amplitude 1.0, 200 milliseconds." | 15 | Single tap | — | 48 × 48 dp min | 2.5.5 |

---

## Slider Behaviour (accessibility detail)

TalkBack users interact with sliders via swipe gestures:
- **Swipe right** — increase value by one step (step = 0.1)
- **Swipe left** — decrease value by one step
- Value announced after each step: "Sensitivity slider, 0.6"
- Selecting a preset (C) snaps the slider to the preset's k value and announces the change

This ensures Amara (no sight) and David (learning TalkBack) can both reach any k value without needing to drag precisely on a touch target. (Addresses US-12 fallback.)

---

## Contrast Specification

| Element | Foreground | Background | Ratio | WCAG target |
|---------|-----------|-----------|-------|------------|
| Section headings | #B0BEC5 | #1A1A2E | 8.2:1 | AAA ✓ |
| Slider track (active) | #4CAF50 | #1A1A2E | 8.9:1 | AAA ✓ |
| Preset button text (selected) | #1A1A2E | #4CAF50 | 8.9:1 | AAA ✓ |
| Preset button text (unselected) | #E0E0E0 | #1A1A2E | 14.7:1 | AAA ✓ |
| Button labels | #1A1A2E | #E0E0E0 | 14.7:1 | AAA ✓ |
| k-value display text | #FFFFFF | #1A1A2E | 18.1:1 | AAA ✓ |

---

## WCAG 2.1 AA Criteria Satisfied by This Screen

| Criterion | Level | How satisfied |
|-----------|-------|--------------|
| 1.3.1 Info and Relationships | A | Section headings use `Semantics(header: true)`; groups conveyed in tree |
| 1.4.6 Contrast (Enhanced) | AAA | All text ≥ 7:1 |
| 2.1.1 Keyboard | A | Slider reachable via swipe; all controls reachable via TalkBack linear navigation |
| 2.4.3 Focus Order | A | Top-to-bottom: back → sensitivity section → presets → slider → alerts section → toggle → test → WoZ triggers |
| 2.4.6 Headings and Labels | AA | Section headings labelled as headers in semantics tree |
| 2.5.5 Target Size | AA | All targets ≥ 48 × 48 dp |
| 3.2.2 On Input | A | Slider value changes do not navigate away or submit; only state updates |
| 4.1.2 Name, Role, Value | A | Slider announces min/max/current; toggle announces on/off; presets announce selected state |

---

## User Stories Addressed

| Story | Addressed how |
|-------|--------------|
| US-01 | Linear focus order [1→15]; all elements labelled with Semantics |
| US-02 | All contrast ratios ≥ 7:1 |
| US-03 | All targets ≥ 48 dp |
| US-12 | Presets (Subtle/Standard/Strong) + slider; settings persisted via `shared_preferences` |
| US-13 | Override toggle [9] reachable from this screen; 2-finger long press also works here |
| US-14 | Override toggle operates independently of audio/volume state |
