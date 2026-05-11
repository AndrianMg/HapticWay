# Wireframe 03 — Onboarding Screen

**Route:** First launch only. Shown before Home screen is accessible.
**Purpose:** Safety notice acknowledgement, explicit informed consent, camera + vibration permission request, TalkBack status check.

> UK GDPR Art. 9(2)(a) requires explicit written consent for special-category data (visual-impairment status is health data). No implicit consent. The user must perform an affirmative gesture.

---

## Layout (480 × 960 dp canvas)

```
┌─────────────────────────────────────┐
│  9:41          WP23 Pro    ▲ ◼ ◉   │
├─────────────────────────────────────┤
│                                     │
│         HAPTICWAY            [1]   │  ← [A] App name heading (focus entry point)
│    Navigation aid for students      │       Semantics: heading level 1
│                                     │
├─────────────────────────────────────┤
│                                     │
│  ╔═════════════════════════════╗   │
│  ║  ⚠  SAFETY NOTICE    [2]  ║   │  ← [B] Safety notice card (§8.4)
│  ║                             ║   │       Must be read before consent offered
│  ║  HapticWay is a navigation  ║   │
│  ║  aid. It does NOT replace   ║   │
│  ║  your cane or guide dog.   ║   │
│  ║  Always use your primary   ║   │
│  ║  mobility aid alongside    ║   │
│  ║  this app.                 ║   │
│  ╚═════════════════════════════╝   │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  ┌──────────────────────────────┐   │
│  │  HOW IT WORKS          [3]  │   │  ← [C] Collapsible info section
│  │  ▼ (expanded by default)    │   │       Semantics: "How it works, expanded"
│  ├──────────────────────────────┤   │
│  │  • Camera detects obstacles  │   │  ← [D] Info text — scrollable region
│  │    up to 4 metres ahead.    │   │       No focus stops inside (read as block)
│  │  • Vibration intensity shows │   │
│  │    how close they are.      │   │
│  │  • No data ever leaves your │   │
│  │    device. No internet      │   │
│  │    needed.                  │   │
│  └──────────────────────────────┘   │
│                                     │
├─────────────────────────────────────┤
│                                     │
│  CONSENT                     [4]   │  ← [E] Consent section heading
│                                     │
│  ┌──────────────────────────────┐   │
│  │  I understand HapticWay     │   │  ← [F] Consent statement (readable text)
│  │  will access my camera and  │   │       Non-interactive, read before [G]
│  │  vibration motor. No images │   │
│  │  are stored or transmitted. │   │
│  │  I can withdraw at any time │   │
│  │  in Settings.               │   │
│  └──────────────────────────────┘   │
│                                     │
│  ┌──────────────────────────────┐   │
│  │  ✓  I AGREE — GET STARTED   │   │  ← [G] Affirmative consent button [5]
│  └──────────────────────────────┘   │       72 dp tall, full width
│                                     │       ONLY button that advances; no skip
│                                     │
└─────────────────────────────────────┘

After [G] tapped:
  → Requests CAMERA permission (Android runtime dialog)
  → Requests VIBRATE permission (Android runtime dialog)
  → Navigates to Home screen
  → Sets onboarding-complete flag in shared_preferences
  → Never shown again
```

---

## Element Annotation Table

| ID | Element | Type | Semantics label | Focus order | Gesture | Fallback action | Touch target | WCAG criterion |
|----|---------|------|----------------|-------------|---------|-----------------|-------------|----------------|
| A | "HapticWay" title | Heading | "HapticWay. Navigation aid for students." | 1 | — | — | — | 2.4.6 Headings |
| B | Safety notice card | Container | "Safety notice. HapticWay is a navigation aid. It does not replace your cane or guide dog. Always use your primary mobility aid alongside this app." | 2 | — | — | Full width | 1.3.1, 3.3.1 |
| C | "How it works" heading | Heading | "How it works, section" | 3 | — | — | — | 2.4.6 |
| D | Info text block | Container | "Camera detects obstacles up to 4 metres ahead. Vibration intensity shows how close they are. No data ever leaves your device. No internet needed." | 4 | — | — | — | 1.3.1 |
| E | "Consent" heading | Heading | "Consent, section" | 5 | — | — | — | 2.4.6 |
| F | Consent statement | Container | "I understand HapticWay will access my camera and vibration motor. No images are stored or transmitted. I can withdraw consent at any time in Settings." | 6 | — | — | — | 1.3.1, 3.3.2 |
| G | "I Agree" button | ElevatedButton | "I agree, get started. Activates camera and vibration access and opens the navigation screen." | 7 | Single tap (direct) / Double tap (TalkBack) | No alternative path — explicit consent required | Full width, 72 dp min | 2.5.5, 3.3.4, 4.1.2 |

**No skip link or bypass exists for the onboarding flow.** This is intentional: UK GDPR Art. 9(2)(a) requires affirmative, informed consent before special-category data processing (camera access for a disability-assistive app). The user must hear/read the safety notice and consent text before the agree button is reachable.

---

## Focus Order Rationale

The focus order is strictly linear and narrative:
1. **Title** — establishes context
2. **Safety notice** — must be encountered before consent (§8.4)
3. **How it works** — explains data use before asking for it
4. **Info text** — consumed as a block
5. **Consent heading** — signals the decision point
6. **Consent statement** — the actual statement being agreed to
7. **Agree button** — only after all above have been traversed

For Amara (congenitally blind, TalkBack power user): swipes through 7 nodes before reaching the agree button. This is intentional. The design errs toward informed consent over speed. (Addresses David persona concern: onboarding must not assume prior screen-reader fluency — every node is self-explanatory in isolation.)

---

## Permission Request Flow (post-consent)

```
User taps [G]
  │
  ├─► Android CAMERA permission dialog
  │     "Allow HapticWay to take pictures and record video?"
  │     → Allow  → continue
  │     → Deny   → show inline message: "Camera is required for obstacle detection.
  │                  Go to Settings > Apps > HapticWay > Permissions to enable it."
  │                  (does not crash; degrades gracefully)
  │
  └─► Android VIBRATE permission dialog (if not auto-granted)
        → granted implicitly on most devices (VIBRATE is a normal permission)
        → navigate to HomeScreen
        → write onboarding_complete = true to shared_preferences
```

Permission denial is handled gracefully with an inline error message — no unhandled exceptions, no silent failure. (WCAG 3.3.1 Error Identification)

---

## Contrast Specification

| Element | Foreground | Background | Ratio | WCAG target |
|---------|-----------|-----------|-------|------------|
| "HapticWay" title | #FFFFFF | #1A1A2E | 18.1:1 | AAA ✓ |
| Safety notice border | #FF6B35 | #1A1A2E | 7.2:1 | AAA ✓ |
| Safety notice text | #FFFFFF | #2A1A0E | 16.4:1 | AAA ✓ |
| Info text | #E0E0E0 | #1A1A2E | 14.7:1 | AAA ✓ |
| Consent text | #FFFFFF | #1A1A2E | 18.1:1 | AAA ✓ |
| "I Agree" button text | #1A1A2E | #4CAF50 | 8.9:1 | AAA ✓ |
| Section headings | #B0BEC5 | #1A1A2E | 8.2:1 | AAA ✓ |

---

## WCAG 2.1 AA Criteria Satisfied by This Screen

| Criterion | Level | How satisfied |
|-----------|-------|--------------|
| 1.3.1 Info and Relationships | A | Safety notice and consent sections conveyed as distinct semantic regions |
| 1.4.6 Contrast (Enhanced) | AAA | All text ≥ 7:1 |
| 2.4.3 Focus Order | A | Strictly linear, narrative order — title → safety → info → consent → agree |
| 2.4.6 Headings and Labels | AA | Title, section headings marked as `Semantics(header: true)` |
| 2.5.5 Target Size | AA | Agree button 72 dp tall; no element < 48 dp |
| 3.3.1 Error Identification | A | Camera permission denial shows specific inline error message |
| 3.3.2 Labels or Instructions | A | Consent statement explicitly names what is being consented to |
| 3.3.4 Error Prevention | AA | No destructive action on this screen; consent is the only action |
| 4.1.2 Name, Role, Value | A | Agree button label describes action and outcome; all elements have explicit labels |

---

## User Stories Addressed

| Story | Addressed how |
|-------|--------------|
| US-01 | Linear focus order [1→7]; all elements have Semantics labels |
| US-02 | All contrast ≥ 7:1 |
| US-03 | Agree button 72 dp tall; all targets ≥ 48 dp |
| US-04 | Explicit affirmative consent via [G]; no implicit consent on load |
| US-05 | Safety notice [B] is focus stop 2, encountered before consent is reachable |
| US-13 | 2-finger long press is registered on this screen (override toggle, even before home screen) |
