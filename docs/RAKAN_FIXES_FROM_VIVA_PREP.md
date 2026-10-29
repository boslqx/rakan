# Rakan: Fixes and Improvements from Viva Preparation (29 Oct 2026)

This list comes from reading the whole codebase and the FYP report while preparing the viva guides (`FYP\Viva\*.pdf`). It **adds to** `docs/RAKAN_IMPROVEMENTS_FROM_CH5.md` (the Chapter 5 backlog). Items already in that backlog are not repeated in full; section C only records their current status.

Each item gives: where, the problem (with evidence), the fix, and when it is done. Items marked **ASK BOS** change behaviour that the report describes; propose the change and stop.

## Rules for Claude Code

1. Follow every rule in `docs/RAKAN_IMPROVEMENTS_FROM_CH5.md` ("Rules for Claude Code"): Bos commits; only `*@rakan-demo.test` accounts; keep both test suites green; do not change the cited values (posture thresholds, fatigue bands 0.4/0.7, adjustments +10% / 0 / -17.5% / -42.5%, 28-day boundary, recovery 0.8) without asking; redeploy Render and confirm the live commit.
2. Read the real source before changing anything. File paths below were correct on 29 Oct 2026.
3. Add or update a test with every logic fix. Pure decision code goes in `static` functions so it can be unit-tested (existing pattern: `computeMissedDays`, `training_stats.dart`).
4. Log each item in `CHANGELOG_CH5.md` with its ID from this file (V-xx), the commit hash and the test cases to rerun.
5. Do **not** edit the report (`.docx`). For section D, only draft replacement wording if Bos asks.

---

## A. First: housekeeping (do before anything else)

### V-01 · Commit the work in progress and re-run the suites
- **Problem:** Uncommitted changes exist (`lib/features/legal/` is untracked; follow-ups to commit `7cc7fad` in `missed_day_dialog.dart`, `workout_day_detail_screen.dart`, `workout_screen.dart`, `adapt_service.dart`, `schedule_matcher.dart`, `workout_plan_service.dart` and three test files).
- **Fix:** Run `flutter test` and `backend\venv\Scripts\python -m pytest -v`; report the exact counts and date (the report quotes four different counts: 4.11, 5.2.1, 5.2.6, 6.1). Give Bos a commit message.
- **Done when:** Both suites green; counts and date written in `CHANGELOG_CH5.md` so the report can quote one number.

### V-02 · Retest fixes made after the test round
- **Problem:** D-21 (logged day movable), L-04 (Schedule ignores overrides) and D-28 (offline start shows "verify email") look fixed in code but are "Open" in the report.
- **Fix:** No code. Write a short manual retest checklist (UT-SCH-08, the L-04 scenario, UT-AUTH-02) for Bos to run on the phone.
- **Done when:** Checklist in `CHANGELOG_CH5.md`.

---

## B. New items found during viva preparation

### Security and privacy

#### V-03 · Change Password is weaker than sign-up (High)
- **Where:** `lib/features/settings/screens/change_password_dialog.dart`; `lib/core/utils/validators.dart`.
- **Problem:** Sign-up requires 8+ characters with lowercase, uppercase, digit and symbol (`Validators.registerPassword`). Change Password only checks `newPass.length < 6`, so "abcdef" is accepted.
- **Fix:** Validate the new password with `Validators.registerPassword` and show the same requirement checklist as the register screen.
- **Done when:** "abcdef" and "rakan123" are rejected; "Rakan12!" accepted. Widget or unit test added. Note: UT-SET-07's expected message changes; tell Bos.

#### V-04 · Change Password shown to Google-only accounts (Medium)
- **Where:** `settings_screen.dart` (Change Password tile); `AccountDeletionService.usesPassword` already detects password accounts.
- **Fix:** Show the tile only when the user has the `password` provider; otherwise hide it or show "Managed by Google".
- **Done when:** A Google-only demo account does not see the dialog.

#### V-05 · Record terms acceptance and finish the legal screens (Medium)
- **Where:** `lib/features/legal/` (new, untracked), `register_screen.dart`, Google sign-up path, `users/{uid}/profile/data`.
- **Problem:** The checkbox is required but agreement is not stored, so consent cannot be shown later.
- **Fix:** On successful sign-up (email and Google), write `termsAcceptedAt` (server timestamp) and `termsVersion` (the `lastUpdated` value) to the profile. Rename Privacy Policy section 2 from "Camera and microphone" to "Camera and voice coaching" (the app has no microphone permission).
- **Done when:** A new demo account has both fields; legal screens reachable from register and Settings.

#### V-06 · Username create rule does not require a verified email (Low)
- **Where:** `firestore.rules`, `match /usernames/{usernameLower}`.
- **Problem:** Uses `request.auth != null`; every other user-data rule uses `isVerified()`.
- **Fix:** Use `isVerified()` for create and delete (read can stay signed-in only). Check that onboarding claims the username only after verification; if not, ASK BOS.
- **Done when:** Rules deployed; `ch5_rules_test.py`-style check passes for verified and fails for unverified.

#### V-07 · Include the adaptation endpoints in the ID-token check (part of D-15)
- **Where:** `backend/routers/adapt_router.py`, `adaptation_engine_router.py`; `adapt_service.dart`, `weekly_summary_service.dart`, `injury_service.dart` (HTTP calls).
- **Problem:** No `Authorization` header is sent to `/adapt-plan` or `/commit-adaptations`. They write nothing, so the risk is lower, but they are open.
- **Fix:** When doing CH5 P0-1, apply the same token dependency to all routers and send `Authorization: Bearer <idToken>` from every client call.
- **Done when:** Requests without a valid token get 401 on all four endpoints.

#### V-08 · VALIDATION logs print in release builds (Low)
- **Where:** `angle_calculator.dart` (`_logRep`, deadlift `debugPrint('VALIDATION|...')`).
- **Problem:** `debugPrint` is not removed in release builds; report 5.7.2 says the lines only appear in debug builds.
- **Fix:** Wrap the VALIDATION prints in `if (kDebugMode)` (from `package:flutter/foundation.dart`). Do not change the line format (`capture.py` parses it).
- **Done when:** Release build prints nothing; debug build unchanged.

### Adaptive engine (Modules 8 and 9)

#### V-09 · Scheduled deload is never undone (High) · ASK BOS
- **Where:** `weekly_summary_service.dart` (`_applyAdjustmentToMuscleGroup`).
- **Problem:** Tier 0 (-42.5%) is written into the recurring template. Later increases are at most +10%, and `(2 * 1.10).round() == 2`, so 3 x 10 becomes 2 x 6 and sets never return to 3.
- **Fix (proposal):** When applying `scheduled_deload`, store `preDeloadSets` and `preDeloadReps` on each changed exercise; on the next weekly run (week after the deload), restore them before applying that week's adjustment, and clear the fields.
- **Done when:** Unit test of the pure step: 3 x 10 -> deload 2 x 6 -> next run restores 3 x 10 (+ that week's adjustment).

#### V-10 · Weekly adjustments only touch days after today's weekday (High) · ASK BOS
- **Where:** `weekly_summary_service.dart`, `if (dayNumber <= todayWeekday || isRestDay) continue;`.
- **Problem:** Plan days are a weekly template, so earlier weekdays are never adjusted; a run on Sunday (weekday 7) changes nothing, yet proposals are marked committed. Report 4.5 says "only workout days after today are changed".
- **Fix (proposal):** Apply to every workout day of the template, but freeze this week's already-passed days (same idea as `keptForThisWeek` in the Schedule code), or simply apply to all days because the change is meant to start next week.
- **Done when:** Test: a run with `todayWeekday = 7` still changes Monday-Saturday exercises of the matching group.

#### V-11 · Recovery score is stale at the weekly run (Medium)
- **Where:** `weekly_summary_service.dart` (`_generateSummary` reads `muscleRecovery/{group}`); `workout_log_service.dart` (`updateMuscleRecovery` runs only after a save).
- **Fix:** Call `updateMuscleRecovery(uid)` at the start of `_generateSummary`, and also when the Coach Recovery tab loads, so a muscle stops showing "fatigued" days after its last session. Also write zero scores for groups with no sets in the 7-day window (today they keep their old score until they turn "unknown").
- **Done when:** Test or seeded check: a group trained 6 days ago at 0.75 and not since shows the recomputed value.

#### V-12 · Adaptation failures are silent (Medium) (extends CH5 P1-7)
- **Where:** `adapt_service.dart` (`predictAndAdapt` returns `''` on any error); `weekly_summary_service.dart` (checkpoint and `weekNumber` advance even if `/commit-adaptations` failed).
- **Fix:** (a) Queue the session features locally (or a `pendingPrediction` doc) and retry `/adapt-plan` on the next app open. (b) If proposals existed and the commit call failed, do not advance `lastWeeklySummaryAt` or `weekNumber`; retry on the next Home open (so a week-4 deload is not skipped).
- **Done when:** Simulated 500 from the backend leaves proposals pending and the week number unchanged.

#### V-13 · Weekly run reads every workout log (Low, performance)
- **Where:** `_generateSummary` (`collection('workoutLogs').get()` with no filter).
- **Fix:** Query `completedAt >= weekStart` (same string-comparison approach as `updateMuscleRecovery`).

#### V-14 · Reschedule rules changed after the report (Medium) · ASK BOS
- **Where:** `adapt_service.dart` `computeRescheduleDays` (commit `7cc7fad` removed the `lastTrainedDate` 48-hour floor and moved to one card per missed date).
- **Problem:** Report 4.5.7 and E2E-03 describe per-muscle cards and the 48-hour rule (Curovic, 2025).
- **Fix:** Bos decides: restore the 48-hour floor (re-add `lastTrainedDate`, tests for 47 h / 48 h) **or** keep the new design and update the report. Do nothing until decided.

### Statistics, Coach and Schedule

#### V-15 · Adherence and muscle-balance targets ignore the plan start (Medium)
- **Where:** `lib/features/coach/services/training_stats.dart` (`summarize`, `muscleBalance`).
- **Problem:** Scheduled sessions are counted from the start of the range using today's plan, so a new user's 30-day ON PLAN starts very low (for example 3 of 13).
- **Fix:** Pass the plan's `generatedAt` and start counting from `max(window.start, planStart)`. Optionally use `ScheduleMatcher.resolvedDayForDate` with overrides.
- **Done when:** New tests in `training_stats_test.dart` for a plan created mid-window.

#### V-16 · One region-to-muscle map (Medium) (extends L-07)
- **Where:** `coach/services/injury_service.dart` (`kBodyRegionToMuscleGroups`, backend vocabulary) vs `coach/screens/coach_screen.dart` (`_injuryRegionGroup`).
- **Problem:** Shoulder pauses Shoulders and Arms in the plan but the readiness card marks Shoulders only; lower back pauses Back and Core but the card marks Back only; hip pauses Legs and Glutes but the card marks Glutes only.
- **Fix:** One shared map (app vocabulary) plus a single translation to the backend's lowercase / `abs` names.
- **Done when:** Unit test that every region gives the same groups in both places.

#### V-17 · Two different "volume" rules (Low) · ASK BOS
- **Where:** `workout_active_screen.dart` `_totalVolume` (reps x kg, bodyweight = 0) vs `training_stats.dart` / `updateMuscleRecovery` (bodyweight counts reps).
- **Fix:** Bos chooses: keep both and label the VOLUME tile "kg lifted", or unify. The weekly trend uses `totalVolume`, so changing it changes Tier 2 behaviour.

#### V-18 · Coach Recovery tab `setState` after `await` without `mounted` (Low)
- **Where:** `coach_screen.dart` `_loadRecovery` (the seeding branch and the final `setState`, plus the catch).
- **Fix:** Add `if (!mounted) return;` before each `setState` after an `await`.

#### V-19 · Exercise library "ADD TO WORKOUT" bypasses the scope choice and refresh (Medium)
- **Where:** `workout/screens/exercise_detail_sheet.dart` (`_addExerciseToDay`).
- **Problem:** Always writes to the plan (every week), ignores locked or one-time days, and does not bump `WorkoutPlanService.scheduleChanges`, so Schedule and Home may not show the new exercise until reload.
- **Fix:** Bump `scheduleChanges` after the write; reuse `showScopeChoiceSheet` ("SAVE TO MY PLAN" / "JUST THIS TIME") with the same rules as `WorkoutDayDetailScreen._addExercise`.
- **Done when:** Adding from the library updates the Schedule segment without restarting.

#### V-20 · Weekly reminders go stale after plan changes (Medium) (extends CH5 P1-11)
- **Where:** `notification_service.dart` `scheduleWeeklyReminders` is only called from `settings_screen.dart`.
- **Fix:** If reminders are enabled, reschedule after plan generation, reset, injury rebuild, weekly adaptation, day swap, cancel and rest-to-workout conversion (one helper, called from `_runMutation` and the plan services). ASK BOS whether rest days should still get a "Rest Day" reminder.

#### V-21 · Personal Stats: no range checks, weight does not reach Coach (Low) · ASK BOS for the weight part
- **Where:** `settings/screens/edit_stats_screen.dart`.
- **Fix:** Reuse the onboarding range validators for age, height and weight. Optionally add a `WeightRecord` when the weight changes so Coach shows it (Coach uses the newest weight record first).

### Posture detection

#### V-22 · Countdown does not wait for the body (Low) · ASK BOS
- **Where:** `widgets/pose_countdown_overlay.dart`; `pose_detection_screen.dart`; `auto_log_screen.dart`.
- **Problem:** UT-GDE-03 expects the 7-second countdown to repeat until the whole body is visible; the code runs it once regardless.
- **Fix (if Bos wants the tested behaviour):** Restart (or pause) the countdown while no pose is detected; only finish after the body has been visible for the last N seconds.

#### V-23 · Arnold Press mapping mismatch (Low)
- **Where:** `angle_calculator.dart` `ExerciseAnalyserFactory._byName` has `'arnold press'`; `exercise_data.dart` has `hasPoseDetection: false` for it.
- **Fix:** Bos decides: enable form check for Arnold Press (then 31 exercises; report says 30) or remove the mapping. Add a test that the factory names equal the pose-enabled set exactly.

#### V-24 · Store camera form results (Medium, enables future evaluation)
- **Where:** `pose_detection_screen.dart`, `auto_log_screen.dart` (`_repForm`), exercise log write in `workout_active_screen.dart`.
- **Problem:** Good/bad rep verdicts are shown and spoken but never saved, so form improvement over time cannot be measured (report 1.5 scope).
- **Fix:** Save `formRepsGood` and `formRepsTotal` per exercise log when the camera counted the set. No UI change required.

#### V-25 · Glitch filter and borderline band (already CH5 P4) · ASK BOS
- Listed for completeness: ignore frames with impossible values (trunk lean 178.5 deg); soft "almost there" feedback for 81-89 deg squats. The 80 deg threshold itself must not change.

### Small fixes

#### V-26 · Template workouts can return fewer than 3 exercises (extends D-22)
- **Where:** `workout_screen.dart` `buildTemplateExercises`, `_kMuscleGroupTemplatePools`.
- **Example:** Back pool with `['dumbbell', 'bench']` yields only Dumbbell Row and Chest-Supported Dumbbell Row.
- **Fix:** If fewer than 3 survive, top up from `kExercises` with the same `muscleGroup` that pass `equipmentMatches`, sorted by difficulty distance.
- **Done when:** Test with the example above returns >= 3.

#### V-27 · Coach insight wording (L-06)
- **Where:** `coach_screen.dart` `_buildCoachInsightCard`.
- **Fix:** Remove "Rest and ice if needed" and the promise of "light mobility and rehab exercises"; point to the Terms ("not medical advice") instead.

---

## C. Status of the CH5 backlog items (checked 29 Oct 2026)

| ID | Item | Status in code |
|---|---|---|
| P0-1 · D-15 | Verify Firebase ID token | **Open** (no `verify_id_token` in backend) |
| P0-2 · D-24 | `isPrivate` default in rules | **Open** (`firestore.rules` still reads `.data.isPrivate`) |
| P0-3 · D-21 | Logged day protection | Locking added in `7cc7fad` + uncommitted work; completion still matched by date. Retest (V-02) |
| P0-4 · D-27, L-01 | Injury rebuild too broad | **Open** |
| P1-1 · D-28 | Offline start shows verify email | Fixed in code (`acc460a`); retest |
| P1-2 · D-23 | Invisible confirmations | CHECK |
| P1-3 · D-25 | Onboarding name not in Auth | **Open** (no `updateDisplayName` in onboarding) |
| P1-4 · D-26 | Crop button under status bar | CHECK on phone |
| P1-5 · D-22 | Template < 3 exercises | **Open** (see V-26) |
| P1-6 · D-14 | Pydantic `Literal` types | **Open** |
| P1-7 | Offline session never adapts | **Open** (see V-12) |
| P1-9, P1-10 | Day-one weekly summary / week jump / strip before plan start | **Open** |
| P1-11 | Reminders per device | **Open** (see V-20) |
| L-04 | Schedule ignores overrides | Fixed in `7cc7fad` (`_thisWeek`); retest |
| P3-3 | `/version` endpoint | **Open** |
| P3-4 | Warm-up ping | **Open** |

Suggested order: V-01 -> V-02 -> P0-1 + V-07 -> P0-2 -> V-03 -> V-05 -> V-08 -> P0-4 -> V-11 -> V-12 -> V-15 -> V-16 -> V-19 -> V-20 -> V-26 -> V-27 -> remaining CH5 P1 -> ASK BOS items (V-09, V-10, V-14, V-17, V-21, V-22, V-23) once decided.

---

## D. Report corrections (for Bos; do not edit the .docx)

Claude Code may draft replacement sentences on request. Section numbers refer to `Project Proposal Report.docx`.

| # | Section | Problem | Correct to |
|---|---|---|---|
| 1 | 1.3 | Targets changed from 90% / 80% (proposal) to 75% with no reason | Add the agreed reason in one sentence |
| 2 | 1.5 | Promises a 4-week test of improving exercise form | Reword (form history not stored) |
| 3 | Ch. 3 (around 3.4) | Says Firebase Storage is used | Photos are base64 in Firestore; no Storage |
| 4 | 3.4 | Correct squat = knee 70-100 deg | Final rule: <= 80 deg, no "too deep" (5.7.4) |
| 5 | 3.3 / Fig. 3.3.1 | Architecture text omits the FastAPI server | Mention FastAPI on Render |
| 6 | 4.8 (last paragraph) | RPE drives the recovery screen | RPE feeds the fatigue model; recovery = sets / MRV |
| 7 | 4.11, 5.2.1, 5.2.6, 6.1 | Four different test counts | One dated count (V-01) |
| 8 | 4.12 | 127 exercises, 121 GIFs, backend 126, "30 of the 127"; caption "Table 4.11.1" | 627, 624, 326, "30 of the 627"; renumber |
| 9 | 4.13 Table 4.13.1 | Personal stats update Coach weight | Coach shows the newest weight record |
| 10 | 4.14 Table 4.14.1 | Lists `addScheduleOverride`; caption "Table 4.13.1"; no plan vs one-time choice | Current design; renumber |
| 11 | 4.5 | 28-day boundary cites Halonen et al. (2024); code cites Encarnacao et al. (2022) and Mujika and Padilla (2000) | Make consistent |
| 12 | 4.5.7, E2E-03 | 48-hour rule, per-muscle cards | Depends on V-14 |
| 13 | 5.2.4 | "input it was designed for" | "not designed for" |
| 14 | 5.3.7 UT-GDE-03 | Countdown repeats until body visible | Depends on V-22 |
| 15 | 5.3.9 UT-REC-01 | "5 of 8 ready" | 7 muscle groups |
| 16 | 5.6 | D-21, D-28, L-04 open | "Fixed after testing" once retested |
| 17 | 6.2 | "13 participants"; "Zhang et al, 20025", "Furtheremoe", "lightning" | 20 participants; typos |
| 18 | 4.11 / 4.13 | No mention of Terms, Privacy Policy, not medical advice | Add once V-05 is done |
| 19 | 5.7.2 | VALIDATION lines "only printed in debug builds" | True after V-08 |
| 20 | Ch. 4 | No subsection for the Coach statistics report | Optional short subsection |
