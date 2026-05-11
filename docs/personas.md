# HapticWay — Personas & User Stories

> Source: §4.2 of HAPTICWAY_CODING_TODO.md
> Research basis: *The Latency Trap and the Haptic Void* (proposal PDF) + *HapticWay_Report_2500w.docx*

---

## Personas

### Persona A — Amara: The Screen-Reader Native

| Field | Detail |
|---|---|
| Age | 20 |
| Year | 2nd year, BSc Computer Science |
| Sight loss | Congenitally blind — no prior sighted experience |
| Primary AT | TalkBack (Android) power user since childhood |
| Secondary AT | Long white cane for campus navigation |
| Tech fluency | High — navigates entirely by swipe gestures and focus order |
| Frustration | Apps that break linear focus order or ship unlabelled icon buttons; any element that is "silent" under TalkBack |
| Goal | A campus navigation aid that supplements her cane with pre-collision warnings so she can walk confidently in unfamiliar corridors, basements, and lifts where her cane gives no advance warning |
| Key quote | *"My cane tells me what's already there. I need something that tells me what's coming."* |

**Design implication:** Every interactive element must carry a `Semantics(label: ...)`. Focus traversal order must be strictly linear. No time-limited elements. No visual-only cues.

---

### Persona B — David: The Recently Sight-Lost Adaptor

| Field | Detail |
|---|---|
| Age | 23 |
| Year | MSc Data Science, 1st year |
| Sight loss | Progressive condition; lost functional sight 9 months ago |
| Primary AT | TalkBack — still learning; sometimes reverts to touch exploration |
| Secondary AT | White cane — recently trained |
| Tech fluency | Medium — was a sighted smartphone power user, now relearning |
| Frustration | Clunky onboarding flows that assume prior screen-reader knowledge; cloud navigation aids that lag or fail in the campus library basement |
| Goal | Regain confidence navigating his new campus. Needs the app to be self-explanatory on first launch and to work offline in dead zones (the library underground stack is where he studies) |
| Key quote | *"I know the campus from when I could see it, but everything feels different now. I need something I can trust."* |

**Design implication:** Onboarding must require no prior TalkBack knowledge. Consent flow must be explicit and paced. App must pass the airplane-mode test (C8). Haptic feedback gives him a non-auditory channel that does not require perfect screen-reader fluency.

---

### Persona C — Priya: The Low-Vision Residual User

| Field | Detail |
|---|---|
| Age | 21 |
| Year | 3rd year, BSc Biomedical Engineering |
| Sight loss | Tunnel vision (retinitis pigmentosa) — residual central vision at ~15% field |
| Primary AT | High contrast mode + large text; TalkBack for navigation in dark/crowded areas |
| Secondary AT | Occasional cane in unfamiliar or low-light environments |
| Tech fluency | High — uses visual UI partially, supplements with TalkBack gestures |
| Frustration | Low-contrast UIs that disappear in bright outdoor light; haptic feedback that is either too subtle or painfully strong in a lecture theatre |
| Goal | Use HapticWay as a *supplement* in high-risk situations (crowded canteen, wet corridors) without it overwhelming her residual vision workflow |
| Key quote | *"I can see something is there, I just can't always tell what it is or how far. A gentle buzz would help without distracting me."* |

**Design implication:** Contrast ratio ≥ 7:1 (AAA target, §8.3). Touch targets ≥ 48 dp. Haptic sensitivity must be user-tunable with presets. Announcements must be suppressible so they don't compete with her partial visual processing.

---

## User Stories

Format: *"As [persona], I need [function] so that [outcome], measured by [acceptance criterion]."*

Each story is tagged: `[Phase N]` = the phase in which it is implemented.

---

### Accessibility & Interface (Phase 2)

**US-01** `[Phase 2]`
As **Amara**, I need every interactive element in the app to have a TalkBack-readable label and appear in a logical linear focus order, so that I can complete any task without visual cues, measured by a TalkBack walkthrough (screen curtain on) completing all tasks on all three screens with zero silent elements and no out-of-order focus jumps.

**US-02** `[Phase 2]`
As **Priya**, I need all on-screen text and interactive controls to meet a contrast ratio of at least 7:1, so that I can read them with my residual tunnel vision under outdoor lighting, measured by an automated contrast audit plus manual inspection across Home, Settings, and Onboarding screens.

**US-03** `[Phase 2]`
As **Priya**, I need all touch targets to be at minimum 48 × 48 dp, so that my reduced field of view and imprecise tapping do not cause accidental activations, measured by an automated widget-size check across every interactive element.

**US-04** `[Phase 2]`
As **David**, I need an onboarding screen that clearly explains what the app does and requires an explicit affirmative gesture to grant consent before any camera access begins, so that I understand the app's purpose and data use before it starts, measured by completing onboarding with only the affirmative gesture (no implicit consent on load).

**US-05** `[Phase 2]` *(Cross-cutting §8.4)*
As **David**, I need a "Safety Notice" on first launch stating that HapticWay is an aid and not a replacement for my cane or guide dog, so that I understand the app's limitations before relying on it, measured by the notice appearing before any navigation screen is reachable and requiring an acknowledgement tap.

---

### Obstacle Detection & Announcements (Phase 3)

**US-06** `[Phase 3]`
As **Amara**, I need the app to detect obstacles from the 8-class set (person, chair, door, staircase, pole, bench, bicycle, wet floor sign) at an overall accuracy of ≥ 85%, so that I receive reliable warnings for real campus hazards, measured by a confusion matrix over the labelled validation set reporting mean accuracy ≥ 85% and per-class recall ≥ 80% for person, chair, door, staircase.

**US-07** `[Phase 3]`
As **Amara**, I need each detected obstacle to be announced by TalkBack at most once per 1.5 seconds for the same label, so that repeated detections of the same object do not flood and overwhelm my audio channel, measured by walking past a stationary chair and receiving exactly one announcement within any 1500 ms window.

**US-08** `[Phase 3]`
As **David**, I need the app to work fully in airplane mode, so that I am not left without obstacle detection in the basement library stack or campus lifts, measured by the full detection loop (camera → inference → announcement) passing with the device in airplane mode.

**US-09** `[Phase 3]` *(Cross-cutting §8.4)*
As **Amara**, I need the app to announce "Detection unavailable — use primary mobility aid" if inference fails for three or more consecutive frames, so that I am never silently left without feedback, measured by simulating isolate failure and confirming the announcement fires before the fourth failed frame.

**US-10** `[Phase 3]`
As **David**, I need the end-to-end latency from camera capture to TalkBack announcement to have a P95 below 50 ms, so that warnings reflect my current physical position and not where I was half a second ago, measured by the benchmark harness logging ≥ 20 runs across four conditions and reporting P95 < 50 ms in the bright/empty condition.

---

### Haptic Radar (Phase 4)

**US-11** `[Phase 4]`
As **David**, I need the vibration intensity to increase smoothly as I approach an obstacle, following the inverse-square curve A(d) = min(1.0, k/d²), so that I can intuitively sense my rate of approach without relying on audio, measured by a blindfolded walk test where the participant correctly identifies "closer / same / farther" at three measured distances with ≥ 80% accuracy.

**US-12** `[Phase 4]`
As **Priya**, I need a sensitivity slider with three labelled presets ("Subtle", "Standard", "Strong") that adjusts the k constant, so that I can tune the haptic intensity to a level that supplements rather than overwhelms my residual vision workflow, measured by three co-design participants selecting distinct k values that each survive an app restart.

**US-13** `[Phase 4]`
As **Amara**, I need to disable haptic alerts instantly from any screen using a 2-finger long-press, so that I can silence feedback during a lecture without navigating into Settings, measured by the manual override activating within 200 ms of the gesture from HomeScreen, SettingsScreen, and OnboardingScreen, and a status announcement confirming the state change.

**US-14** `[Phase 4]`
As **David**, I need the haptic feedback channel to be independent of the audio channel, so that I can use vibration alone in noisy environments (canteen, corridor, outdoor) without the audio announcements competing, measured by running the full nav loop with device volume muted and confirming vibration still fires correctly for each obstacle class.

---

## Story Count

| Phase | Stories |
|---|---|
| Phase 2 — Design & Prototyping | US-01 to US-05 (5 stories) |
| Phase 3 — Core Development | US-06 to US-10 (5 stories) |
| Phase 4 — Haptic Radar | US-11 to US-14 (4 stories) |
| **Total** | **14 stories** ✓ (minimum 12 required) |

---

## Acceptance Criteria (§4.2)

- [x] Three personas: congenitally blind (Amara), recently sight-lost (David), low vision (Priya)
- [x] Stories use format: *As [persona], I need [function] so that [outcome], measured by [criterion]*
- [x] Minimum 12 stories: **14 written**
- [x] Each story tagged with phase
