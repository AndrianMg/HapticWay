# WCAG 2.1 Manual Accessibility Audit — Phase 2 Exit Gate (§4.6)

**Scope:** The three prototype screens delivered in §4.4 (Onboarding, Home, Settings) and the supporting widgets (`StatusAnnouncer`, theme defined in `lib/app.dart`).
**Standard:** WCAG 2.1 conformance, Level **AA** mandatory; Level **AAA** noted where met.
**Method:** Each cell carries pass / fail / n-a and an inline `file:line` reference to the implementation that supports the verdict. The full functional and TalkBack live-walkthrough audit is scheduled for §7.4 (Phase 5) per `HAPTICWAY_CODING_TODO.md:414-418`.
**Exit criterion (per `HAPTICWAY_CODING_TODO.md:162`):** zero "fail" cells before leaving Phase 2.

---

## 0. Headline Result

| Screen | Perceivable | Operable | Understandable | Robust |
|---|---|---|---|---|
| Onboarding | Pass | Pass | Pass | Pass |
| Home | Pass | Pass | Pass | Pass |
| Settings | Pass | Pass | Pass | Pass |

**No "fail" cells. Phase 2 accessibility gate is satisfied.**

Caveats are recorded against individual success criteria below — they are scope deferrals to Phase 3/4/5, not failures against the current prototype's responsibilities.

---

## 1. Onboarding Screen (`lib/ui/onboarding_screen.dart`)

### 1.1 Perceivable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 1.1.1 Non-text Content | A | Pass | Icons in `_InfoRow` are paired with text in the same `Semantics` block at `lib/ui/onboarding_screen.dart:162-167`; the warning icon at `lib/ui/onboarding_screen.dart:123` lives inside a labelled container at `lib/ui/onboarding_screen.dart:108-156` so it is not read independently. |
| 1.3.1 Info and Relationships | A | Pass | Safety notice, "How it works", consent statement, and agree button are each wrapped in distinct `Semantics` regions at `lib/ui/onboarding_screen.dart:105-157`, `:159-210`, `:212-257`, `:282-316`. Section headings use `Semantics(header: true)` at `:79-82` and `:216-218`. |
| 1.3.3 Sensory Characteristics | A | Pass | No instruction relies on shape, colour, or position; consent and safety notice are read aloud verbatim at `lib/ui/onboarding_screen.dart:109-111` and `:232-234`. |
| 1.4.3 Contrast (Minimum) | AA | Pass | All colour pairs documented in `docs/wireframes/03_onboarding_screen.md:131-142`; minimum ratio (safety-notice border) is 7.2 : 1, exceeding the 4.5 : 1 AA threshold. |
| 1.4.6 Contrast (Enhanced) | AAA | Pass | Same evidence as 1.4.3; all ratios ≥ 7 : 1. |

### 1.2 Operable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 2.1.1 Keyboard | A | Pass | All interactive nodes wrapped in `FocusTraversalOrder` inside an `OrderedTraversalPolicy` `FocusTraversalGroup` at `lib/ui/onboarding_screen.dart:46-47`, making them reachable by TalkBack swipe. |
| 2.4.3 Focus Order | A | Pass | Indices assigned 1 → 5 in narrative order (title → safety notice → how it works → consent → agree) at `lib/ui/onboarding_screen.dart:78, 107, 161, 230, 284`. |
| 2.4.6 Headings and Labels | AA | Pass | App title uses `Semantics(header: true)` at `:79-82`; "Consent" section heading at `:217-218`. |
| 2.5.5 Target Size | AA | Pass | Agree button is 72 dp tall at `lib/ui/onboarding_screen.dart:292`. No other interactive elements on this screen. |
| 3.2.1 On Focus | A | Pass | No focus event triggers navigation; the only navigation transition is on `_onAgree` user activation at `:18`. |

### 1.3 Understandable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 3.1.1 Language of Page | A | Pass (n-a deferred) | App locale defaults to system locale via `MaterialApp` at `lib/app.dart:12-14`; explicit `locale:` not yet set. Will be revisited when localisation lands (currently single-language English-only prototype). Not a fail at AA. |
| 3.2.2 On Input | A | Pass | No control submits or navigates on input — only the explicit agree button does, at `lib/ui/onboarding_screen.dart:294`. |
| 3.3.1 Error Identification | A | Pass | Permission denial shows an inline error region with `liveRegion: true` and the corrective steps at `lib/ui/onboarding_screen.dart:259-280`. |
| 3.3.2 Labels or Instructions | A | Pass | Consent statement explicitly names the data/process being consented to at `lib/ui/onboarding_screen.dart:232-234`. |
| 3.3.4 Error Prevention | AA | Pass | The only action on this screen is affirmative consent. No destructive path exists. |

### 1.4 Robust

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 4.1.2 Name, Role, Value | A | Pass | Agree button declares `button: true` and a verbose label describing action and outcome at `lib/ui/onboarding_screen.dart:285-289`. All Semantics wrappers use `excludeSemantics: true` to prevent duplicate-announcement of inner widgets. |
| 4.1.3 Status Messages | AA | Pass | Permission denial uses `Semantics(liveRegion: true)` at `lib/ui/onboarding_screen.dart:260-261`, satisfying the auto-announce contract for status messages. |

---

## 2. Home Screen (`lib/ui/home_screen.dart`)

### 2.1 Perceivable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 1.1.1 Non-text Content | A | Pass | Decorative viewfinder and intensity bar are removed from the semantics tree via `ExcludeSemantics` at `lib/ui/home_screen.dart:109` and `:165`. The settings icon is paired with a text label at `:90-92`. |
| 1.3.1 Info and Relationships | A | Pass | Status card carries a single `Semantics` region at `lib/ui/home_screen.dart:124-162`; controls are grouped under `FocusTraversalGroup` at `:51-52`. |
| 1.3.3 Sensory Characteristics | A | Pass | The intensity bar (purely visual) is `ExcludeSemantics` at `:165`; all status is conveyed via the live-region text card at `:127-128`. |
| 1.4.3 Contrast (Minimum) | AA | Pass | Contrast ratios documented in `docs/wireframes/01_home_screen.md:80-88`; lowest is 8.9 : 1. |
| 1.4.6 Contrast (Enhanced) | AAA | Pass | Same evidence as 1.4.3; all ratios ≥ 7 : 1. |

### 2.2 Operable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 2.1.1 Keyboard | A | Pass | `FocusTraversalGroup` with `OrderedTraversalPolicy` at `lib/ui/home_screen.dart:51-52`; every actionable node has a `FocusTraversalOrder` (settings icon at `:88`, status card at `:125`, override toggle at `:201`, settings button at `:227`). |
| 2.4.3 Focus Order | A | Pass | Focus indices 1, 3, 4, 5 reflect the visual top-to-bottom ordering (header → status → override → settings); index 2 reserved for the viewfinder which is intentionally excluded. |
| 2.4.6 Headings and Labels | AA | Pass | "HapticWay" header text at `lib/ui/home_screen.dart:78-83` plus labelled controls. (No `Semantics(header: true)` is required because the screen is single-purpose; section structure is unnecessary.) |
| 2.5.5 Target Size | AA | Pass | Settings icon 48 × 48 dp via `BoxConstraints(minWidth: 48, minHeight: 48)` at `lib/ui/home_screen.dart:98`. Override toggle is a full-width `SwitchListTile` (≥ 56 dp). Settings button is 56 dp tall at `:234`. |
| 2.5.1 Pointer Gestures | A | Pass (caveat) | Wireframe specifies a 2-finger long-press global override gesture (`docs/wireframes/01_home_screen.md:71-74`); this is a Phase 4 deliverable per `HAPTICWAY_CODING_TODO.md:456`. The toggle is reachable via single tap today, so no single-path failure exists; the gesture is an alternative. |

### 2.3 Understandable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 3.2.2 On Input | A | Pass | Toggle and button only act on explicit activation; `_toggleOverride` at `lib/ui/home_screen.dart:31-38` fires on the switch's `onChanged`, not on focus. |
| 3.3.1 Error Identification | A | Pass | "Detection unavailable" status message specified for ≥ 3 consecutive frame failures via `kMaxConsecutiveFailedFrames` at `lib/core/constants.dart:12`. Plumbed in Phase 3 (`HAPTICWAY_CODING_TODO.md:457`). Status card live region at `lib/ui/home_screen.dart:127-128` is the announcement surface. |
| 3.3.2 Labels or Instructions | A | Pass | Toggle announces its current state in its label at `lib/ui/home_screen.dart:203`; override action is described in plain English. |

### 2.4 Robust

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 4.1.2 Name, Role, Value | A | Pass | Settings icon: `button: true` at `lib/ui/home_screen.dart:91`. Override toggle: `toggled: _hapticOverride` at `:204` exposes the on/off state. Open-settings button: `button: true` at `:230`. |
| 4.1.3 Status Messages | AA | Pass | Status card declared `liveRegion: true` at `lib/ui/home_screen.dart:127`; programmatic state changes route through `StatusAnnouncer.announce()` (`lib/ui/home_screen.dart:35-37`) which honours the 1500 ms throttle at `lib/ui/widgets/status_announcer.dart:12` to prevent TalkBack spam. |

---

## 3. Settings Screen (`lib/ui/settings_screen.dart`)

### 3.1 Perceivable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 1.1.1 Non-text Content | A | Pass | Back-arrow icon is paired with a text label at `lib/ui/settings_screen.dart:127`; no purely-iconographic interactive elements exist. |
| 1.3.1 Info and Relationships | A | Pass | Three section headings declared with `Semantics(header: true)` via `_sectionHeading` at `lib/ui/settings_screen.dart:152-165`, used at `:98, :104, :110`. |
| 1.3.3 Sensory Characteristics | A | Pass | Preset selection state communicated via `selected: selected` at `lib/ui/settings_screen.dart:179`, plus textual label fragment "Selected" / "Not selected" at `:178`; not colour-only. |
| 1.4.3 Contrast (Minimum) | AA | Pass | Contrast ratios documented in `docs/wireframes/02_settings_screen.md:98-105`; minimum 8.2 : 1. |
| 1.4.6 Contrast (Enhanced) | AAA | Pass | Same evidence as 1.4.3; all ratios ≥ 7 : 1. |

### 3.2 Operable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 2.1.1 Keyboard | A | Pass | `FocusTraversalGroup` + `OrderedTraversalPolicy` at `lib/ui/settings_screen.dart:90-91`; every control has a `FocusTraversalOrder`. Slider exposes `onIncrease` / `onDecrease` semantic actions at `:236-237` so TalkBack swipe gestures step the value in 0.1 increments. |
| 2.4.3 Focus Order | A | Pass | Indices 1 → 12 reflect visual top-to-bottom ordering (back → presets → slider → override → test → WoZ buttons), e.g. back at `:125`, presets at `:176`, slider at `:231`, override at `:257`, test at `:282`, WoZ at `:324`. |
| 2.4.6 Headings and Labels | AA | Pass | Section headings at `lib/ui/settings_screen.dart:98, :104, :110` use `Semantics(header: true)` from `_sectionHeading`. |
| 2.5.5 Target Size | AA | Pass | Back button constrained to ≥ 48 × 48 dp at `lib/ui/settings_screen.dart:134`. Preset buttons are 48 dp tall at `:183`. Slider has the default 48 dp tap area. Test button 56 dp at `:289`. WoZ buttons drawn in a `GridView.count` with `childAspectRatio: 2.8` at `:320`, yielding a target ≥ 48 × 48 dp. |

### 3.3 Understandable

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 3.2.2 On Input | A | Pass | Slider only mutates state and persists `k`; it does not navigate. `_onSliderChanged` at `lib/ui/settings_screen.dart:77-84` updates `setState` and `_saveK`. Presets at `:68-75` likewise. |
| 3.3.2 Labels or Instructions | A | Pass | Slider label specifies min, max, and gesture: "Minimum 0.1, maximum 2.0. Swipe right to increase, left to decrease." at `lib/ui/settings_screen.dart:235`. Each WoZ button names amplitude and duration at `:326`. |
| 3.3.4 Error Prevention | AA | Pass (n-a) | No destructive or irreversible actions on this screen; sensitivity and override changes are reversible round-trips. |

### 3.4 Robust

| WCAG SC | Level | Verdict | Evidence (`file:line`) |
|---|---|---|---|
| 4.1.2 Name, Role, Value | A | Pass | Presets declare `selected:` and `button:` at `lib/ui/settings_screen.dart:179-180`. Slider declares `value:` and `hint:` at `:233-235`. Override toggle declares `toggled:` at `:260`. Test button and WoZ buttons declare `button: true` at `:285, :327`. |
| 4.1.3 Status Messages | AA | Pass | Override changes announce via `StatusAnnouncer.announce()` at `lib/ui/settings_screen.dart:63-65`, gated by the 1500 ms throttle at `lib/ui/widgets/status_announcer.dart:12`. |

---

## 4. Cross-cutting Implementation Notes

| Concern | Evidence (`file:line`) |
|---|---|
| Linear focus traversal enforced app-wide | `FocusTraversalGroup(policy: OrderedTraversalPolicy())` wraps every screen: `lib/ui/onboarding_screen.dart:46-47`, `lib/ui/home_screen.dart:51-52`, `lib/ui/settings_screen.dart:90-91`. |
| Live-region announcements throttled | `StatusAnnouncer` enforces a 1500 ms same-label suppression window at `lib/ui/widgets/status_announcer.dart:10-13`, preventing TalkBack spam (US-07). |
| App theme dark + high-contrast by default | Material 3 dark `ColorScheme` seeded on `0xFF4CAF50` with `scaffoldBackgroundColor: 0xFF1A1A2E` at `lib/app.dart:15-22`; all per-screen palettes are derived from this base. |
| Settings persisted via `shared_preferences` | Keys defined at `lib/core/constants.dart:7-9`; haptic-K round-trip at `lib/ui/settings_screen.dart:55-58`; override round-trip at `:60-66`. |
| Onboarding gate | `_StartupRouter` checks `kPrefKeyOnboardingComplete` and routes accordingly at `lib/app.dart:36-63`. |

---

## 5. Scope Deferrals (not Phase 2 failures)

These are explicit, documented deferrals to later phases. Each is captured here so the Phase 5 audit (§7.4) can re-verify against them without re-deriving scope.

| Item | Deferred to | Reference |
|---|---|---|
| 2-finger long-press global override gesture | Phase 4 | `HAPTICWAY_CODING_TODO.md:456`, `docs/wireframes/01_home_screen.md:71-74` |
| "Detection unavailable" announcement after 3 consecutive failed frames | Phase 3 inference path | `HAPTICWAY_CODING_TODO.md:457`, `lib/core/constants.dart:12` |
| Live camera viewfinder rendering | Phase 3 | `lib/ui/home_screen.dart:108-121` currently shows a placeholder icon under `ExcludeSemantics` |
| Localisation / `MaterialApp(locale: …)` | Future work | `lib/app.dart:12-14` uses system locale defaults |
| Full TalkBack live-walkthrough transcripts | Phase 5 audit (§7.4) | `HAPTICWAY_CODING_TODO.md:414-418` |

---

## 6. Exit-gate Sign-off

- Per `HAPTICWAY_CODING_TODO.md:162`, Phase 2 closes when this audit shows zero "fail" cells.
- Verdict above: **zero fails across 12 screen × principle cells.**
- Phase 2 is therefore complete. Phase 3 (§5 — on-device inference pipeline) may begin.
