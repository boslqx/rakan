# Rakan: Fix and Improvement Backlog (from FYP Chapter 5 testing)

This backlog comes from the Chapter 5 testing (Testing and Evaluation) of the FYP report. Every item gives its report ID (D-xx = defect, L-xx = limitation, UT/IT/ST/E2E = test case), so a fix can be traced back to the report.

## Rules for Claude Code

1. Let Bos commit the changes, give the commit message at the end
2. **Never touch real user accounts.** Test data, seed scripts and Admin SDK calls may only use `*@rakan-demo.test` accounts. The scripts in `tools/demo_seed/ch5_*.py` already assert this. Keep that check in any new script.
3. After each item, run `flutter test` and `backend\venv\Scripts\python -m pytest -v`. Both suites must stay green (105 Dart tests, 14+ backend tests).
4. **Do not change these documented values without asking Bos first**, because the report cites them:
   - posture thresholds in `angle_calculator.dart` (`FormThresholds`);
   - fatigue bands 0.4 / 0.7;
   - adjustments +10% / 0 / −17.5% / −42.5%;
   - the 28-day detraining boundary;
   - the recovery threshold 0.8.
   If a fix needs one of them changed, propose the change and stop.
5. Backend changes only reach users after a Render redeploy. After deploying, check that the live backend runs the new commit (see P3-3).
6. At the end, write a short `CHANGELOG_CH5.md` that lists each item ID, its commit hash, and which test IDs to rerun. The report records results at the testing date, so Bos will mark these as "Fixed after testing".

---

## P0: Security and data integrity (do first)

### P0-1 · D-15 (Critical) · Plan endpoints trust the uid in the request body
- **Evidence:** ST-14. A request with another user's `uid` and no ID token created a plan for that user. The Admin SDK bypasses the Firestore rules.
- **Where:** `backend/routers/plan_router.py` (`/generate-plan`, `/regenerate-plan`), `backend/firebase_config.py`, and the Flutter service that calls these endpoints. Also check `adapt_router.py` and `adaptation_engine_router.py` for any write that uses a body uid.
- **Fix:**
  - The client sends `Authorization: Bearer <Firebase ID token>`.
  - Add a FastAPI dependency that calls `firebase_admin.auth.verify_id_token()` and returns the uid.
  - Use the token uid. Return 401 when the token is missing or invalid, and 403 when a body uid is present and does not match.
  - Remove `uid` from the request models, or ignore it.
- **Accept when:**
  - Re-running `tools/demo_seed/ch5_st14.py` gives 401 or 403.
  - Onboarding, injury regeneration and plan reset still work in the app (IT-01, IT-04, IT-07).
  - New pytest cases cover a missing token, a wrong-uid token and a valid token (mock `verify_id_token`).

### P0-2 · D-24 (High) · Accounts that never touched "Private Account" cannot be followed
- **Evidence:** UT-SOC-02. `firestore.rules` compares `isPrivate == true`. Reading a missing field is an error, so the request is denied, and `UserProfileScreen` then spins forever.
- **Fix:**
  - Write `isPrivate: false` when the user document is created (sign-up, Google sign-in and onboarding).
  - In the rules, use `resource.data.get('isPrivate', false)`, and use the same pattern for any other optional field the rules read.
  - Catch the permission error in `UserProfileScreen` and show a message instead of the spinner.
  - Add a one-off backfill script that sets `isPrivate: false` where the field is missing. Dry-run it on demo accounts first, and let Bos run it on production.
- **Accept when:**
  - UT-SOC-02 passes with a fresh account.
  - `tools/demo_seed/ch5_rules_test.py` still gives 25 of 25 as expected.

### P0-3 · D-21 (Medium) · A logged day can still be moved or made a rest day
- **Evidence:** UT-SCH-08. Completion is matched by **date**. After a logged Push day was moved, Saturday showed it as missed and a new day on that date showed "WORKOUT COMPLETED".
- **Where:** schedule day actions (Move to Another Day, Make It a Rest Day, drag-to-swap), `ScheduleMatcher`, and the workout log write.
- **Fix:**
  - Hide or disable Move, Rest and drag for any day that has a log this week.
  - Store the plan day id (`dayId`/`planDayId`) on each new workout log.
  - Match completion by day id first, and fall back to date for old logs.
- **Accept when:** UT-SCH-08 passes and the existing `schedule_matcher_test.dart` tests still pass. Add tests for the id-based match.

### P0-4 · D-27 + L-01 (Medium) · Injury rebuild refills every unlogged day and breaks volume limits
- **Evidence:** UT-REC-03. Weekly sets went from 69 to 105, and chest from 15 to 50 sets, although the chest maximum is 20. Days with no injured muscle were also rebuilt, so manual edits and weekly adaptations were lost.
- **Where:** `backend/services/plan_generator.py` (regenerate path) and `backend/routers/plan_router.py`. `backend/tests/test_regenerate_plan.py` holds the existing tests.
- **Fix:**
  - Rebuild only days that contain a paused muscle group, and leave every other day untouched.
  - When refilling, cap weekly sets per muscle at its maximum recoverable volume. This is the same per-muscle max the app shows.
  - Skip the rebuild entirely on the Active → Recovering transition, unless the paused groups change.
- **Accept when:**
  - New pytest cases show that unaffected days keep their exercises.
  - No muscle exceeds its weekly max after a rebuild.
  - E2E-05 and E2E-06 still behave as described.

---

## P1: Functional bugs found by manual testing

| ID | Problem (evidence) | Where | Fix | Accept when |
|---|---|---|---|---|
| P1-1 · D-28 | Opening the app offline while signed in shows VERIFY YOUR EMAIL (UT-AUTH-02) | `auth_service.dart` (`reloadAndCheckVerified`), splash routing | Return "not verified" only when the server says so. Re-throw network errors (`FirebaseAuthException` code `network-request-failed`) so the splash shows "Check your internet connection and try again." with TRY AGAIN | UT-AUTH-02 passes in airplane mode |
| P1-2 · D-23 | Password-reset and resend-verification confirmations are invisible (dark text on dark bar) (UT-AUTH-07, UT-AUTH-14) | `login_screen.dart` `_showSuccess`, `email_verification_screen.dart` `_showMessage` | Give the SnackBar text an explicit colour from the theme. Check every other SnackBar helper for the same bug | Both messages readable; UT-AUTH-07 passes |
| P1-3 · D-25 | Onboarding name not shown in Settings / Edit Profile ("Rakan Athlete") | Onboarding save + settings screens | Call `user.updateDisplayName(name)` when onboarding is saved, **or** make Settings and Edit Profile read the name from the Firestore user doc. Pick one source of truth | A new account shows its onboarding name in Settings |
| P1-4 · D-26 | Photo crop toolbar is drawn under the status bar on Android 16, so a photo can't be saved (UT-SET-03, emulator) | `image_cropper` config, `AndroidManifest.xml` (`UCropActivity`), Android styles | Update `image_cropper`, or give `UCropActivity` a theme that respects system insets / disables edge-to-edge | UT-SET-03 passes on the Android 16 emulator **and** on a physical phone |
| P1-5 · D-22 | "Use Template" promises 3–4 exercises but the Back template added 2 (21 min) (UT-SCH-06) | Convert-rest-day template logic | Guarantee ≥ 3 eligible exercises, falling back to bodyweight/compatible equipment. If that's impossible, change the message to match | UT-SCH-06 passes for the intermediate + dumbbells + bench profile |
| P1-6 · D-14 | Backend accepts unknown goal/experience/duration and duplicate days (Table 5.2.4.1, ST-11) | `plan_router.py` request models | Use Pydantic `Literal[...]` for goal, experience and session duration, plus a validator that rejects duplicate `workout_days`. Values must match what the Flutter client sends | New pytest cases get HTTP 422; onboarding still works |
| P1-7 | Workout finished offline: log syncs, but no adaptation proposal is ever stored (UT-WRK-14 / IT-10) | Workout finish flow → `/adapt-plan` call | If `/adapt-plan` fails, queue the request locally (e.g. a pending-proposal doc or shared_preferences) and retry when connectivity returns or on next launch | Finish offline → reconnect → a pending proposal appears |
| P1-8 | Home shows only grey loading shapes while offline, although Schedule and Coach show cached data (IT-10) | Home screen data loading | Read from the Firestore cache (`Source.cache` fallback) or show cached data with an "offline" banner, not an endless skeleton | Home shows last known data in airplane mode |
| P1-9 | "YOUR WEEK IN REVIEW" appears on the plan's first day and marks days **before plan creation** as missed (UT-HOM observations) | Weekly summary trigger, missed-day detection (`AdaptService`) | Ignore days before the plan's `createdAt`; don't show the review in the plan's first week | A fresh account sees no review sheet and no missed days on day 1 |
| P1-10 | Week number counts from the first workout log, not the plan start ("Week 1" → "Week 2") (UT-HOM observations) | Home header / week counter | Compute the week from the active plan's start date | Header matches the plan week |
| P1-11 | Reminder settings are stored per device, so Account B inherited Account A's reminder time (UT-SET section) | `NotificationService`, settings storage | Store reminder prefs per uid (key by uid or in the user doc). Cancel and reschedule on login/logout | Switching accounts shows each account's own setting |
| P1-12 | An active injury isn't drawn red on the body map until it becomes Recovering, although the chip says "Shoulders injured" (UT-REC-03 text) | Recovery Map / body heatmap colouring | Treat `active` the same as or stronger than `recovering` when colouring | Active injury shown red immediately |

---

## P2: Limitations from the end-to-end tests (Table 5.6.2)

| ID | Limitation | Suggested change |
|---|---|---|
| L-02 | A partly affected day is never restored (e.g. Push → Chest-only after a shoulder injury, not marked "(Adjusted)"). After a knee recovered, Friday Legs still held only glutes | Always save `originalWorkoutName` and the original exercise list for **any** day that loses a muscle group, and restore from it on recovery. Commit 2d8ba3a covers rest days and "(Adjusted)" days, so check it also covers partly affected days, and add a pytest case |
| L-03 | Full volume returns in one step on Recovered | Graded return: e.g. 60% of sets in week 1, 80% in week 2, then 100%. Store a `returnPhase` on the injury. **Ask Bos before choosing the percentages** (they'd be cited in the report) |
| L-04 | Schedule tab ignores one-off rescheduled sessions (Home shows them, Schedule shows rest) | Merge schedule overrides into the Schedule tab, using the same `ScheduleMatcher` logic as Home |
| L-05 | Schedule doesn't refresh after a background injury rebuild | Use a Firestore snapshot listener on the plan days, or reload after the regenerate call completes |
| L-06 | The Recovering coach insight promises "rehabilitation exercises" that don't exist | Change the message text. Adding real rehab exercises is a feature for later |
| L-07 | Readiness card marks only Glutes for a hip injury, while the plan pauses Legs and Glutes | Create one shared region→muscle map, used by both the readiness card and the regenerate request |
| D-13 | 90-minute (and some 60-minute low-equipment) sessions fall 20–40 min short (Table 5.2.3.2) | Option A: when eligible exercises run out, allow the set cap to rise (5 → 6) or add a compatible second split group. Option B: show the realistic estimated duration on the plan and in onboarding. Measure again with the property-based script and report the new "within ±15 min" numbers |
| D-16 | The fatigue model detects only 1 of 6 high-fatigue sessions (regression to the mean) | **Don't change the model or thresholds without Bos.** Prepare a comparison only: (a) class-weighted / more high-fatigue synthetic samples, (b) a rule override such as avg RPE ≥ 8.5 → high. Report the band confusion matrix for each on the same 200-sample test split (`random_state=42`) |

---

## P3: Tests, tooling and deployment

| ID | Item | Change |
|---|---|---|
| P3-1 · D-17 | `backend/tests/test_adaptation_engine.py` has its own copy of the `/commit-adaptations` router | Import the real router from `routers/adaptation_engine_router.py` (or test through `main.app` with TestClient) and delete the copy |
| P3-2 | The 24 boundary cases from the report (Tables 5.2.2.1–5.2.2.3) were run in a one-off script | Add them as parametrised pytest cases: fatigue 0.00/0.39/0.40/0.55/0.70/0.71/1.00; trend 106/105/100/90/89/empty/[0]; the 10 tier-resolution cases. The expected values are in the report tables, and the current code already passes them |
| P3-3 · D-20 | The deployed backend was once older than the repo, with nothing to show it | Add `GET /version`, which returns the git commit (set via a Render env var at build). Show it on a debug/about row in Settings, debug builds only |
| P3-4 | Render free-tier cold start of ~52 s on the first call (IT-09) | On app launch/splash, fire a non-blocking `GET /` or `/version` warm-up ping, so the backend is awake before onboarding or the first workout finishes |
| P3-5 | `firestore.rules` changes have no automated test in the repo | Optional: add rules unit tests with the Firebase Local Emulator Suite (`@firebase/rules-unit-testing`) mirroring ST-04 to ST-09 and the D-24 case |
| P3-6 | Manual cases that need a widget test | Add widget tests for: SnackBar text colour (D-23), the offline splash message (D-28), and that a logged day hides Move/Rest (D-21) |

---

## P4: Posture detection refinements (from Section 5.7.6)

Don't change `FormThresholds` values. These are additions only.

- **Borderline band:** a squat whose deepest knee angle is 81–89° gets softer feedback ("Almost there, go a little deeper") instead of a hard "incorrect". 7 of the 9 squat false positives were in this band. Keep the verdict logic the same, change only the message, unless Bos approves a verdict change.
- **Glitch filter:** ignore single frames with physically impossible values (e.g. trunk lean > 100°, or a sudden jump > 60° between consecutive frames), so one lost frame cannot flag a rep (seen: trunk lean 178.5°).
- **Study logging:** add an optional `fault=` field to the `VALIDATION` log line and to `tools/posture_study/capture.py`. A future study can then report accuracy per fault type (shallow, hip sag, forward lean).
- **Deadlift:** rounded back can't be measured without spine landmarks. For now, make sure the deadlift is shown with a "form check not available" note rather than a misleading verdict.

---

## P5: Future features (Chapter 6 future work, not for now)

Only do these if Bos asks.
- Sleep-hours input as an extra recovery signal (the "Track recovery: sleep hours" use case was not implemented).
- Optional HRV import from wearables (Health Connect).
- Gamification: streak rewards, challenges, badges.
- On-device performance profiling (frame time, memory, pose FPS) with Flutter DevTools in profile mode.

---

## Suggested order

P0-1 → P0-2 → P1-2 → P1-1 → P0-3 → P0-4 → P1-6 → P3-1 → P3-2 → P3-3 → P3-4 → rest of P1 → P2 → P4

After the backend items, redeploy Render and confirm with `/version`. Then re-run the matching test IDs, and record pass/fail in `CHANGELOG_CH5.md` for Bos.
