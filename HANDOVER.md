# Rakan — FYP Project Handover Summary (Updated — Phase 27)

## Project Overview

- **App Name:** Rakan — Adaptive AI Fitness Coach with Real-Time Posture Correction
- **Type:** Final Year Project (FYP) — university level, supervisor-reviewed
- **Platform:** Flutter mobile app (Android + iOS), targeting Malaysian users
- **Backend:** FastAPI deployed on Render (free tier, ~50s cold start)
- **Database/Auth:** Firebase Firestore + Firebase Auth
- **ML:** scikit-learn Linear Regression for fatigue prediction
- **Pose Detection:** Native Android MediaPipe via Flutter platform channels

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Frontend | Flutter 3.41.6, Dart |
| Backend | FastAPI (Python 3.12), deployed on Render |
| Database | Firebase Firestore |
| Auth | Firebase Auth (Email + Google Sign-In) |
| ML | scikit-learn, joblib, pandas |
| Pose Detection | MediaPipe Tasks Vision 0.10.14 (native Android Kotlin) |
| Camera | CameraX (Android) |
| Device | Samsung S20 FE (physical testing) |
| IDE | VSCode, Windows 11 |
| Run command | `flutter run --no-dds` |

---

## Design System — "Kinetic Precision"

Dark premium aesthetic:

- Background: `#0c0e10`
- `surfaceContainerLow`: `#13161A`
- `surfaceContainerHigh`: `#1C2026`
- `surfaceContainerLowest`: `#000000`
- Primary/Accent: `#c6c6c7` (metallic silver)
- `onSurface`: `#E8E8E9`
- `onSurfaceVariant`: `#9B9EA3`
- `onPrimary`: `#0c0e10`
- `outlineVariant`: used for subtle dividers
- Error: `#EE7D77`
- Fonts: Space Grotesk (headlines) + Manrope (body)
- No borders — tonal depth separation only
- No `withOpacity()` — use `withValues(alpha: x)` instead

**Note (Phase 27):** `coach_screen.dart` still uses `withOpacity()` throughout
(17 pre-existing call sites) despite this rule. The new plateau-notice
widget added this session matched the file's existing convention rather
than introducing a mixed style within one file — this is a pre-existing
inconsistency to clean up file-wide, not something introduced this
session. Worth a dedicated pass later rather than fixing piecemeal.

---

## Project Folder Structure

*(Unchanged from Phase 25/26 — see prior version for the full tree. Phase 27
touched only `workout_log_service.dart`, `adapt_service.dart`,
`coach_screen.dart`, and `adapt_service_test.dart`, all pre-existing files.
No new files, no structural changes, no backend changes at all.)*

Key files touched this session (Phase 27):
- `lib/features/workout/services/workout_log_service.dart` — new
  `getRecentSessionMaxWeights()` method
- `lib/features/workout/services/adapt_service.dart` — new
  `detectPlateau()` static method
- `lib/features/coach/screens/coach_screen.dart` — wires the above into
  `_loadExerciseProgression`, adds a passive plateau notice under the
  exercise progression chart
- `test/adapt_service_test.dart` — 10 new tests for `detectPlateau`

**Test count as of Phase 27: 53 Dart tests + 3 backend (pytest) tests, all
passing.** This also resolves the imprecision flagged at the end of Phase
26 ("exact new Dart/backend split not yet re-confirmed"): re-running
`flutter test` this session shows 53 Dart tests total, and Phase 27 added
exactly 10 — meaning Phase 26's count of 43 was, in fact, already a
Dart-only figure (43 + 10 = 53, matching exactly). Backend pytest count is
unchanged at 3, since Phase 27 touched no backend code at all.
`flutter analyze` on the three changed files shows only pre-existing lint
noise (deprecated `withOpacity`, stray `!` assertions, `print` calls)
already present before this session — nothing new introduced.

---

## Firestore Data Structure

*(Unchanged from Phase 25/26 — `scheduleOverrides` and
`missedDayResolutions` remain keyed by `muscleGroup + date` per Decision
#47, untouched again this session.)*

See prior version of this document for the full collection tree
(`profile`, `workoutPlans`, `scheduleOverrides`, `missedDayResolutions`,
`workoutLogs`, `adaptationProposals`, `weightRecords`, `injuries`).

**No new collections, and no new writes at all this session.**
`getRecentSessionMaxWeights()` only *reads* the existing
`workoutLogs/{logId}/exerciseLogs` subcollection — the exact same
subcollection `getMaxWeightForExercise` already reads, just aggregated
per-session instead of into one running max. This was a deliberate design
choice (Decision #58 below), not an oversight — see Feature Work section.

---

## API Endpoints (Render)

*(Unchanged this session — Phase 27 is Flutter-only, no backend routes
added, removed, or modified.)*

- `POST /generate-plan` — generates 7-day workout plan from user profile
- `POST /adapt-plan` — predicts fatigue score, returns intensity adjustment
- `POST /commit-adaptations` — resolves pending proposals (session + skip-triggered) into final adjustments
- **Backend URL:** `https://rakan-backend.onrender.com`

---

## Adaptive System — Full Reference

*(Signals #1–7 unchanged from the Phase 25 redesign — see prior document
version for the complete signal table and the reschedule/skip/detraining
flow. Phase 27 does not add an 8th signal — see below.)*

### Plateau detection is deliberately NOT Signal #8 (Phase 27)

Exercise-level plateau detection was added this session but was
**deliberately kept outside the Signals #1–7 reactive-adaptation
pipeline** (`adaptation_engine.py`'s `resolve_adjustment` /
`commit-adaptations` flow). Signals #1–7 all *prescribe* — they compute a
`final_adjustment` and mutate future `sets`/`reps` on the plan. Plateau
detection only *observes* — it reads the same underlying `workoutLogs`
data every other signal ultimately traces back to, but never writes
anywhere and never influences what the plan prescribes next. See Decision
#57 below for why this distinction matters enough to state explicitly.

This also confirms something checked directly (via code trace, not
assumption) before designing plateau detection: **the RPE-driven fatigue
system in Signals #1–7 never mutates a logged or prescribed weight value —
only `sets`/`reps`.** Every logged max-weight value is therefore a genuine,
untampered performance data point, and plateau detection needs no
filtering to exclude adaptation-affected sessions.

---

## Feature Work — Phase 27: Exercise-Level Plateau Detection

**Motivation:** the Feature Backlog has carried "Exercise-level plateau
detection" as the next planned adaptive-system gap since Phase 25/26. The
goal: flag, per exercise, when a user's max weight has stopped
meaningfully progressing, as a foundation for later work (e.g. suggesting
an exercise swap) and as a data point for the dissertation's evaluation of
the adaptive system's completeness.

**Rule locked in before implementation:** a plateau is flagged for a given
exercise when none of the last N=4 logged sessions for that exercise shows
a max-weight increase of X=2% or more compared to the prior session's max
weight for the same exercise. N=4 aligns with the project's existing
4-week evaluation window; X=2% sits below the commonly-cited 2.5–5%
minimum progressive-overload increment cited in strength-training
literature, so a session just under typical progression still correctly
reads as "no meaningful improvement" rather than a false negative.

**Design decisions considered before implementation** (four questions,
resolved before any code was written, same review-first workflow as the
Phase 26 missed-day grouping redesign):

1. **Where the logic lives.** Considered the Python backend
   (`adaptation_engine.py`) vs. Flutter. Backend was rejected: that module
   and its routers are stateless rules APIs with no Firestore access at
   all — introducing Firestore reads there just to reach data the Flutter
   client already queries cheaply would be a disproportionate architecture
   change. Chosen: Flutter, split the same way `computeMissedDays`
   (pure, static, testable) is split from `findMissedDays` (Firestore
   fetch) — a pure `detectPlateau()` in `AdaptService`, fed by a
   Firestore-fetching `getRecentSessionMaxWeights()` in
   `WorkoutLogService`.
2. **The N+1 off-by-one.** "None of the last 4 sessions shows an increase
   vs. its prior session" is 4 *comparisons*, which requires 5 raw session
   values, not 4. Resolved explicitly rather than left implicit — see
   Decision #59.
3. **Persistence on detection.** Three options were weighed: (A) a new
   `plateauFlags` Firestore collection mirroring `adaptationProposals`,
   with its own idempotency/resolution state machine; (B) compute
   on-demand, no persisted record; (C) a hybrid, persisting only on
   state *transition*, piggybacked on the existing post-save hook that
   already calls `updateMuscleRecovery`. **Option B was chosen** — see
   Decision #58.
4. **UI surfacing.** Passive (visible only when the user opens that
   exercise's history) vs. active (a toast/dialog, like the missed-day
   popup). **Passive was chosen** — this is a descriptive research signal
   about stagnation, not a safety-relevant intervention like the fatigue
   deload, so an interrupt wasn't judged to be warranted.

**Implementation:**
- `WorkoutLogService.getRecentSessionMaxWeights({uid, exerciseName, limit:
  4, scanLimit: 30})` — same scan/query shape as the existing
  `getMaxWeightForExercise` (scan `workoutLogs` newest-first, look up each
  log's `exerciseLogs` subcollection), but keeps each session's max
  separate instead of folding into one running max, and returns them
  oldest-first.
- `AdaptService.detectPlateau({sessionMaxWeights, n: 4, thresholdPct:
  0.02})` — pure, static, no Firestore. Returns `false` ("insufficient
  history") when fewer than `n+1` sessions are available; otherwise checks
  each of the last `n` session-to-session transitions and returns `true`
  only if none met the threshold. A `prior <= 0` transition is skipped
  rather than causing a divide-by-zero.
- `CoachScreen._loadExerciseProgression` now also calls both, over the
  *full* unwindowed session history for the selected exercise (not the
  chart's selected date-range window — the rule is "last 4 transitions,"
  independent of what the chart happens to be displaying), and stores the
  result in `_isPlateaued`.
- `CoachScreen._buildPlateauNotice()` renders a small passive info banner
  under the chart legend when `_isPlateaued` is true — no dialog, no
  toast, nothing shown unless the user has already opened that exercise's
  history.

**Tests added** (`test/adapt_service_test.dart`, `AdaptService.detectPlateau`
group, 10 tests): insufficient history at 4 sessions; the exact 5-session
boundary (minimum history for detection to first fire); a genuine plateau
across all 4 transitions; one qualifying ≥2% increase clearing it; a
sub-2% increase *not* clearing it; an increase of exactly 2% clearing it
(inclusive-threshold boundary); an old increase outside the last-5 window
correctly not counting; empty history; a zero-weight prior session guarded
against a divide-by-zero false positive; and custom `n`/`thresholdPct`
values honored.

**Verification status — Dart tests and static analysis only, NOT yet
on-device verified.** Full suite (53 Dart tests) passes, `flutter analyze`
is clean of new issues. Unlike Phase 26's Scenarios A–E, this session did
**not** include a physical-device walkthrough (e.g. logging 5+ real
sessions for one exercise on the S20 FE and confirming the banner appears
at the right moment, and only then). That should happen before this is
called done for the dissertation — logged as an open item below, not
claimed as complete.

---

## Key Academic Citations (for dissertation)

*(Unchanged from Phase 25/26 — see prior document version for the full
list. The 2% threshold's positioning below the 2.5–5% progressive-overload
literature range draws on the same strength-training body of citations
already logged; no new citation was introduced this session.)*

---

## Key Architectural Decisions (dissertation-worthy)

*(1–56 unchanged from prior sessions — see previous document version for
full text. New decisions below, Phase 27.)*

57. **Plateau detection is structurally separate from the reactive
    adaptation pipeline (Signals #1–7), not an 8th signal** *(Phase 27)* —
    Signals #1–7 all prescribe (they mutate future `sets`/`reps` via
    `resolve_adjustment`/`commit-adaptations`); plateau detection only
    observes and never writes anywhere. Keeping this boundary explicit
    matters for the dissertation: one is a prescriptive intervention the
    system makes on the user's behalf, the other is a descriptive
    observation surfaced to the user — conflating them would overstate
    what the system is doing. This also documents a fact verified by
    direct code trace before design began: the fatigue/adaptation engine
    never mutates weight, only sets/reps, so plateau detection needs no
    filtering of adaptation-affected sessions.
58. **On-demand computation chosen over a persisted `plateauFlags`
    collection** *(Phase 27)* — avoids introducing new write-time state
    and a resolution/idempotency state machine (when does a flag clear —
    on the next qualifying increase, or only on explicit acknowledgment?)
    that would need its own design pass before implementation. Because the
    algorithm is a pure function over data already being stored
    (`workoutLogs`), no information is lost by not persisting a derived
    flag — historical detection events remain fully reconstructable later
    by replaying the algorithm over past logs, if the dissertation needs
    that.
59. **A rule requiring N session-to-session transitions needs N+1 raw
    session values — stated explicitly to avoid an off-by-one in when
    detection can first fire** *(Phase 27)* — "none of the last 4 sessions
    shows an increase vs. its prior session" is 4 comparisons, requiring 5
    raw values (1→2, 2→3, 3→4, 4→5). `detectPlateau` returns
    "insufficient history" (not "plateaued") until a user has logged a
    5th session for that exercise. Documented explicitly since this is
    exactly the kind of subtle boundary an examiner could probe directly.
60. **A session-to-session transition spanning a long calendar gap is
    treated identically to a normal transition in plateau detection —
    accepted as a known limitation, not fixed, consistent with Decision
    #56's precedent** *(Phase 27)* — a transition following a multi-week
    break (already handled elsewhere by Signal #7's own return-from-break
    tier) can register as a "plateau" transition here even though the real
    explanation is detraining, not stagnation. Cross-referencing break
    history into the plateau window was judged out of scope for the
    remaining FYP timeline, following the same "document rather than
    silently accept" discipline applied to Signal #7's client-clock
    dependency.

---

## Bugs Found and Fixed — Phase 27

None. This session was pure feature addition (plateau detection only) —
no existing file's behavior was changed, and the full pre-existing test
suite (53 Dart + 3 backend) was re-run and confirmed passing with no
regressions.

---

## On-Device Testing — Phase 24/25/26 Missed-Day Flow

*(Unchanged from Phase 26 — all five scenarios (A–E) remain completed and
passing; see prior document version for the full table. Phase 27 added no
new on-device testing — see the Verification status note in the Feature
Work section above and the new checklist item below.)*

---

## Feature Backlog — Status by Section

*(Sections unchanged from Phase 26 except where noted below.)*

### Adaptive

| Task | Status |
| --- | --- |
| Weekly update to the workout plan | ✅ |
| Notice/summary of what changed after an adaptive update | ✅ |
| Missed-day detection with user-driven reschedule/skip choice | ✅ *(Phase 25)* |
| Detraining-time-based load reaction | ✅ *(Phase 25)* |
| Return-from-break magnitude scaling by layoff length | ✅ *(Resolved, Phase 25)* |
| Missed-day UI grouped by date (visual, per-muscle-group resolution kept) | ✅ *(Phase 26)* |
| New-user false-positive missed-day bug | ✅ *(Fixed, Phase 26)* |
| On-device verification of full Phase 24/25 missed-day flow | ✅ *(Completed, Phase 26)* |
| Exercise-level plateau detection | ✅ *(Implemented, Phase 27, this session — unit-tested; on-device verification still outstanding, see below)* |
| "Combine with an existing day" reschedule option | ⬜ Not started (explicitly deferred, Phase 25) |
| Repeated-return escalation (structural plan flag) | ⬜ Not started |
| Weight/BMI trend feedback into adaptive loop | ⬜ Not started |
| Goal-change propagation | ⬜ Not started |
| Server-side timing validation for Signal #7 | ⬜ Not started — accepted as documented limitation (Decision #56), not currently planned |

---

## Remaining Work (To-Do) — Updated Priority Order, Phase 27

1. **Posture detection accuracy study (Objective 2)** — instrumentation and
   CSV schema exist; needs 3–5 testers, ≥20 reps/exercise, confusion-matrix
   analysis. Still the highest external-dependency risk to the timeline —
   start recruiting testers now if this hasn't begun yet.
2. **On-device verification of plateau detection (Phase 27, new)** — log
   5+ real sessions for one exercise on the S20 FE and confirm: the notice
   stays hidden through sessions 1–4, appears correctly at session 5 when
   no transition met the 2% threshold, and clears correctly the session
   after a genuine ≥2% increase. Currently only unit-tested, not device-
   verified — should not be marked fully done in the dissertation until
   this happens.
3. **"Combine with an existing day" reschedule option** (deferred from
   Phase 25) — needs its own volume-stacking-risk design first.
4. **Repeated-return escalation** (Gap 3) — needs an occurrence-counting
   mechanism before design can proceed.
5. **General UI polish** across all phases.
6. **Dissertation write-up** — citations secured, 60 architectural
   decisions logged as of this session, ready to draw on.
7. *(optional/low-priority)* Replace the 30-log calendar/PR scan limit with
   a proper Firestore range query.
8. *(optional/low-priority)* Weight/BMI trend and goal-change adaptive
   pathways (Gaps 4, 5).
9. *(optional)* Audit other list-based dialogs/widgets for the
   index-vs-identity state-keying pattern (Decision #51) — proactive
   check, not a known bug elsewhere yet.
10. *(optional)* File-wide `withOpacity()` → `withValues(alpha: x)`
    cleanup in `coach_screen.dart` (17 pre-existing call sites, noted this
    session — see Design System section above).

---

## On-Device Testing Checklist — Status Update

- ✅ Phase 24/25/26 missed-day flow (Scenarios A–E) — completed, see prior
  document version.
- ⬜ **Plateau detection (Phase 27) — not yet on-device verified.** Unit
  tests and static analysis only so far. See Remaining Work item 2 above.
- All other prior-session items previously verified — nothing else
  currently outstanding from Phase 26's checklist.

**Next open item:** on-device verification of plateau detection, then
focus shifts back to the posture accuracy study (still the longest lead
time item overall).

---

## Dev Environment

*(Unchanged from Phase 26 — see prior document version for the full
section: PowerShell command substitutions, `adb` path, backend venv
activation, GitHub/Firebase project references, and the
`flutter run --no-dds` connection-error troubleshooting steps.)*

---

## Important Notes for New Chat

- This is a serious FYP — always explain decisions, cite research where
  relevant, guide like a university instructor
- **Breadth-first strategy** — all phases completed before deep polish; the
  one remaining adaptive design gap (plateau detection) is now implemented
  and unit-tested; on-device verification of it is the only adaptive-system
  item still open, alongside the posture accuracy study
- Solo project — working on main branch only
- Always explain WHY before writing code
- Use `withValues(alpha: x)` not `withOpacity(x)` — the latter is
  deprecated (note: `coach_screen.dart` doesn't follow this yet file-wide —
  see Design System section)
- The `grep` and `tail` commands don't work on Windows PowerShell — use
  `findstr` and manual scrolling
- Keep cost close to zero — no paid services
- Before building anything touching Firestore reads/writes for plan or log
  data, check the "Firestore Data Structure" section above first
- Before adding a new adaptive signal, check the "Adaptive System — Full
  Reference" section above first
- **Plateau detection is not Signal #8 and does not feed into
  `resolve_adjustment`/`commit-adaptations`** — it's a separate, read-only
  observation surfaced passively on the Coach screen. Don't conflate the
  two when writing about the adaptive system.
- Before touching any list-rendering dialog with per-item resolve/loading
  state, check Decision #51 — key state by item identity, not list index
- Before assuming device-clock manipulation will trigger an adaptive
  reaction, remember Signal #7 is event-driven, not time-driven — a real
  workout session must be completed after the clock jump, not just time
  passing
- Posture accuracy target is 75%, not 90% — the original Project
  Proposal's 90% figure is superseded; use 75% in all future work
- **Immediate next priority:** on-device verification of plateau detection
  (quick), then the posture accuracy study (longest lead time — start
  recruiting testers now if not already underway)

## Objectives Fulfillment

| Objectives | Status |
| --- | --- |
| To develop a mobile app with an AI-based adaptive workout planner with performance dashboard statistics that generates and automatically updates personalised 7-day exercise routines based on user equipment, performance, and recovery data, achieving at least 75% user satisfaction through user acceptance testing. | Adaptive pipeline fully on-device verified as of Phase 26 (missed-day flow, all 7 signals); exercise-level plateau detection (performance dashboard statistics) implemented and unit-tested Phase 27, on-device verification still outstanding; user acceptance testing not yet conducted |
| To implement a real-time posture detection system using MediaPipe that analyses exercise form via mobile camera and delivers instant corrective feedback with at least 75% accuracy on key exercises (squats, push-ups, deadlifts). | Instrumentation ready; accuracy study not yet conducted — highest-priority remaining item |
| To design and integrate a fatigue and recovery monitoring mechanism that adjusts workout intensity based on user-reported data, such as RPE scale, and evaluate its effectiveness in reducing overtraining risk by observing user recovery progress. | Fully built and on-device verified as of Phase 26 (7 adaptive signals, missed-day flow end-to-end tested); Signal #7's client-clock timing dependency documented as an accepted known limitation (Decision #56); effectiveness evaluation not yet conducted |
