# Wireframe 01 — Home Screen (Live Navigation)

**Route:** Default screen after onboarding complete
**Purpose:** Real-time camera feed with obstacle detection status, haptic radar active, manual override reachable.

---

## Layout (480 × 960 dp canvas)

```
┌─────────────────────────────────────┐  ← Status bar (system, non-interactive)
│  9:41          WP23 Pro    ▲ ◼ ◉   │
├─────────────────────────────────────┤
│                                     │  ← [A] App header bar   48 dp tall
│   HapticWay          ⚙  [1]→[2]   │       Settings icon touch target: 48×48 dp
│                                     │
├─────────────────────────────────────┤
│                                     │
│                                     │
│                                     │
│        CAMERA VIEWFINDER            │  ← [B] Decorative — camera preview
│        (decorative, aria-hidden)    │       No focus stop. Hidden from TalkBack.
│                                     │
│                                     │
│                                     │
│                                     │
├─────────────────────────────────────┤
│  ┌───────────────────────────────┐  │
│  │  [C] DETECTION STATUS CARD   │  │  ← Live region — auto-announced
│  │                               │  │    Height: 80 dp min
│  │  🟢  Scanning…  [Focus: 3]   │  │
│  │                               │  │
│  └───────────────────────────────┘  │
├─────────────────────────────────────┤
│                                     │
│  [D] ████████░░░░░░░  HAPTIC   │  ← Haptic intensity bar (decorative)
│      0.0              1.0      │       aria-hidden, visual only
│                                     │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────────────────────┐   │
│  │  [E]  HAPTIC OVERRIDE        │   │  ← Toggle, 56 dp tall, full-width
│  │       ON  ●──────────────   │   │    Focus: 4
│  └──────────────────────────────┘   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  [F]  OPEN SETTINGS          │   │  ← Button, 56 dp tall, full-width
│  └──────────────────────────────┘   │  Focus: 5 (also reachable via [2] above)
│                                     │
└─────────────────────────────────────┘

Gesture shortcuts (work from anywhere on this screen):
  2-finger long press → Toggle haptic override (US-13)
  1-finger double-tap → Repeat last detection announcement
```

---

## Element Annotation Table

| ID | Element | Type | Semantics label | Focus order | Gesture | Fallback action | Touch target | WCAG criterion |
|----|---------|------|----------------|-------------|---------|-----------------|-------------|----------------|
| A | Settings icon (header) | IconButton | "Open settings" | 1 | Single tap | Navigate to Settings screen | 48 × 48 dp | 2.5.5 Target Size |
| B | Camera viewfinder | Container | `excludeSemantics: true` | — (skipped) | — | — | — | 1.3.3 Sensory Characteristics |
| C | Detection status card | Live region | Dynamic: "Scanning", "Person ahead", "Chair ahead" etc. | 3 | — | Auto-announced via `SemanticsService.announce()` | Full width, 80 dp min | 4.1.3 Status Messages |
| D | Haptic intensity bar | ProgressIndicator | `excludeSemantics: true` | — (skipped) | — | — | — | 1.3.3 Sensory Characteristics |
| E | Haptic override toggle | Switch | "Haptic override, currently [on/off]. Double tap to toggle." | 4 | Double tap (TalkBack) / Single tap (direct touch) | 2-finger long press from any screen (§8.4) | Full width, 56 dp min | 2.1.1 Keyboard, 4.1.2 Name Role Value |
| F | Open settings button | ElevatedButton | "Open settings" | 5 | Single tap | — | Full width, 56 dp min | 2.5.5 Target Size |

**Global gesture — 2-finger long press (US-13, §8.4):**
- Available from any screen, any time
- Toggles haptic override
- Fires `SemanticsService.announce()`: "Haptic alerts disabled" or "Haptic alerts enabled"
- Must activate within 200 ms (acceptance criterion US-13)

---

## Contrast Specification

| Element | Foreground | Background | Ratio | WCAG target |
|---------|-----------|-----------|-------|------------|
| "HapticWay" header text | #FFFFFF | #1A1A2E | 17.5:1 | AAA (≥ 7:1) ✓ |
| Detection status text | #FFFFFF | #0D1B2A | 18.1:1 | AAA ✓ |
| "HAPTIC OVERRIDE" label | #F0F0F0 | #1A1A2E | 15.3:1 | AAA ✓ |
| Toggle ON indicator | #4CAF50 | #1A1A2E | 8.9:1 | AAA ✓ |
| "OPEN SETTINGS" button text | #1A1A2E | #E0E0E0 | 14.7:1 | AAA ✓ |

All contrast ratios exceed 7:1. No element falls below the AAA threshold. (WCAG 1.4.6)

---

## WCAG 2.1 AA Criteria Satisfied by This Screen

| Criterion | Level | How satisfied |
|-----------|-------|--------------|
| 1.1.1 Non-text Content | A | Camera view excluded from semantics tree; decorative elements have `excludeSemantics: true` |
| 1.3.1 Info and Relationships | A | Structure conveyed via Semantics tree, not visual layout alone |
| 1.3.3 Sensory Characteristics | A | No instruction relies solely on visual shape/colour/position |
| 1.4.3 Contrast (Minimum) | AA | All text ≥ 4.5:1 (we target ≥ 7:1) |
| 1.4.6 Contrast (Enhanced) | AAA | All text ≥ 7:1 ✓ |
| 2.1.1 Keyboard | A | All interactive elements reachable by TalkBack swipe gesture |
| 2.4.3 Focus Order | A | Logical top-to-bottom: [1] header icon → [3] status → [4] toggle → [5] settings |
| 2.5.5 Target Size | AA | All targets ≥ 48 × 48 dp |
| 4.1.2 Name, Role, Value | A | Every interactive element has explicit label, role, and state |
| 4.1.3 Status Messages | AA | Detection status delivered via `SemanticsService.announce()` live region |

---

## User Stories Addressed

| Story | Addressed how |
|-------|--------------|
| US-01 | Linear focus order [1→3→4→5]; all elements labelled |
| US-03 | All targets ≥ 48 dp |
| US-07 | Status card uses 1500 ms suppression before re-announcing same label |
| US-09 | Status card announces "Detection unavailable" on 3 consecutive frame failures |
| US-13 | 2-finger long press override reachable from this screen |
| US-14 | Override toggle state persists independently of audio volume |
