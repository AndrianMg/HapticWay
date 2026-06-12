# Data Protection Impact Assessment (DPIA)

**Project:** HapticWay — offline haptic navigation aid for blind and visually impaired users
**Controller:** Andrei Murug (student researcher), Regent College London
**Date:** [PENDING — date of supervisor sign-off]
**Reviewed by:** Faisal Maramazi (supervisor)

---

## 1. Description of processing

### 1.1 In the app (on-device, during any use)

| Data | Processing | Persistence |
| --- | --- | --- |
| Camera frames | Real-time object detection (TFLite, on-device) | **Never stored** — frames exist only in memory for the duration of one inference pass (constraint C5) |
| Depth images (ARCore) | Real-time distance estimation | Never stored — cached in memory per frame only |
| Haptic sensitivity setting (k) | Stored to personalise vibration strength | `shared_preferences`, opaque numeric value, no PII |
| Benchmark / WoZ session logs | Research instrumentation | JSONL/CSV on-device; contain timestamps, class labels, distances, amplitudes, researcher-marked action codes — **no images, no identifiers, no location** |

The app makes **no network calls in the navigation loop** (constraint C4) and has no analytics, no accounts, and no cloud back-end. There is nothing to breach server-side because there is no server.

### 1.2 In the research study (§7.2 user testing)

| Data | Category | Purpose |
| --- | --- | --- |
| Visual-impairment status / sight-loss severity | **Special category (Art. 9)** | Recruitment mix + interpreting results; recorded as an anonymous demographic variable |
| Age band, tech experience, cultural background | Personal data | Anonymous demographic variables |
| Interview recordings / transcripts | Personal data | Thematic analysis; anonymised at transcription |
| Session logs (WoZ JSONL) | Non-personal | Stimulus–response analysis; linked to participants only via anonymous ID |
| Consent forms (signed) | Personal data | Legal record of consent |

## 2. Lawful basis

- **Art. 6(1)(a) GDPR — consent**, for all study participation data.
- **Art. 9(2)(a) GDPR — explicit consent**, for visual-impairment status
  (special category health data). Consent is written, specific, and given via
  `docs/consent_form.md` before any data collection.

Consent is withdrawable at any time without reason; on withdrawal, the
participant's data is deleted (see §4).

## 3. Processors and transfers

**None.** All app processing is on-device. Study records are held by the
researcher on [PLACEHOLDER — encrypted university storage]; no third-party
processors, no international transfers.

## 4. Retention

- **App:** nothing retained beyond the device; participants' devices are not
  used — sessions run on the researcher's test device, and session logs are
  pulled and then deleted from it.
- **Study records:** anonymised transcripts and logs retained until
  [PLACEHOLDER — end of marking period / university retention policy].
  Signed consent forms retained per university policy. Raw audio deleted after
  transcription.
- **On withdrawal:** all data linked to the participant's anonymous ID is
  deleted; anonymous aggregated results already published in the report are
  exempt (Art. 17(3)(d)).

## 5. Risks and mitigations

| # | Risk | Likelihood | Severity | Mitigation |
| --- | --- | --- | --- | --- |
| 1 | Physical injury during blindfold navigation | Medium | High | Scripted pre-walked route; researcher within arm's reach; immediate-stop rule; near-miss logging (§6.4 harness) |
| 2 | Re-identification from small sample (n≥5) | Medium | Medium | Anonymous IDs; demographic variables reported only in aggregate; no direct quotes attributed to identifiable combinations of demographics |
| 3 | Camera captures bystanders during sessions | Medium | Low | Frames never persisted (C5); sessions in controlled spaces; signage informing bystanders |
| 4 | Loss/theft of test device | Low | Low | No PII on device; session logs contain no identifiers; logs pulled and wiped after each session |
| 5 | Participant distress (blindfold anxiety) | Low | Medium | Blindfold optional for sighted-range participants; practice period; stop-anytime rule stated verbally and in consent form |
| 6 | Coercion / power imbalance in recruitment | Low | Medium | No incentives contingent on completion; recruitment via third-party organisations, not personal contacts of the researcher |

## 6. DPIA outcome

Residual risk after mitigations is assessed as **low**. Processing is
proportionate to the research aim (evaluating an assistive-technology
prototype with its intended user group). Sign-off:

- Principal investigator: ____________________  date: ________
- Supervisor / DPO: ____________________  date: ________
