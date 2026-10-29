# CHANGELOG_CH5: fixes after the Chapter 5 test round

Items come from `docs/RAKAN_IMPROVEMENTS_FROM_CH5.md` (P/D/L IDs) and
`docs/RAKAN_FIXES_FROM_VIVA_PREP.md` (V IDs). The report records results at
the testing date; items below are "Fixed after testing" once Bos has
committed them and rerun the listed test cases.

## Test counts (V-01)

Quote one dated count in the report (4.11, 5.2.1, 5.2.6 and 6.1).

| Date | Flutter (`flutter test`) | Backend (`backend\venv\Scripts\python -m pytest -v`) | Note |
|---|---|---|---|
| 29 Oct 2026 | 145 passed | 24 passed | Before this batch (includes the uncommitted follow-ups to `7cc7fad` and the register-screen terms tests) |
| 29 Oct 2026 | 164 passed | 41 passed | After the first batch. `flutter analyze`: no issues |
| 29 Oct 2026 | 172 passed | 46 passed | After the second batch. `flutter analyze`: no issues |
| 29 Oct 2026 | 190 passed | 46 passed | After the third batch (**quote this one**). `flutter analyze`: no issues |

## Items in this batch

Commit hash: _pending (Bos commits)_. One commit is suggested at the end.

| ID | Change | Where | Tests | Rerun |
|---|---|---|---|---|
| P0-1 · D-15 + V-07 | Every endpoint needs `Authorization: Bearer <Firebase ID token>`. The plan routes write with the token's uid; a body uid that differs gives 403; missing or invalid token gives 401 on all four endpoints. The app sends the token on every call (`backendHeaders()`), and still sends the body uid so it also works against the old backend | `backend/auth.py`, `backend/main.py`, `backend/routers/plan_router.py`; `lib/core/utils/backend_headers.dart`, `plan_service.dart`, `injury_service.dart`, `adapt_service.dart`, `weekly_summary_service.dart` | `backend/tests/test_auth.py` (17 cases: missing, forged, malformed, wrong uid, valid) | ST-14 (`tools/demo_seed/ch5_st14.py` must print HTTP 401 and no new plan), IT-01, IT-04, IT-07, one finished workout (`/adapt-plan`), one weekly run (`/commit-adaptations`) |
| V-03 | Change Password uses the sign-up rule (`Validators.registerPassword`) and shows the same live checklist | `change_password_dialog.dart`, `lib/shared/widgets/password_checklist.dart` (moved out of `register_screen.dart`) | `test/change_password_test.dart` ("abcdef", "rakan123" rejected; "Rakan12!" accepted) | UT-SET-07: **expected message changes** to "New password does not meet all requirements" |
| V-04 | Change Password tile hidden for accounts without the `password` provider (Google-only) | `settings_screen.dart` | — | Google-only demo account: no Change Password tile |
| V-05 | Terms acceptance stored on `users/{uid}/profile/data` as `termsAcceptedAt` (server time) and `termsVersion` (the documents' "last updated" date). Google sign-up writes it at once; an email account can't write before verification (rules), so it is kept on the device and written with the onboarding profile. Privacy Policy section 2 renamed "Camera and voice coaching" | `lib/features/legal/services/legal_consent_service.dart`, `register_screen.dart`, `user_profile_service.dart`, `legal_content.dart` | `test/legal_consent_test.dart` | New email demo account and new Google demo account: both fields present after onboarding |
| V-08 | `VALIDATION\|...` lines only in debug builds (`kDebugMode`); format unchanged for `capture.py` | `angle_calculator.dart` | Existing posture tests still print the lines (debug) | Release build + logcat: no `VALIDATION` lines |
| V-11 | Recovery scores recomputed for the current 7-day window before the weekly summary and when the Coach Recovery tab opens (bounded to 5 s). Groups with no sets left in the window are reset to 0, keeping `lastTrained`. Pure core: `WorkoutLogService.computeRecoveryDocs` | `workout_log_service.dart`, `weekly_summary_service.dart`, `coach_screen.dart` | `test/muscle_recovery_test.dart` (group trained 6 days ago at 0.75; older sessions leaving the window; reset to 0) | UT-REC-01, Recovery tab after a few days without training |
| V-13 | Weekly run reads only `completedAt >= weekStart` logs | `weekly_summary_service.dart` | — | One weekly run |
| V-15 | Stats ON PLAN and muscle-balance targets count scheduled sessions from the plan's `generatedAt`, not the window start. WORKOUTS still counts every session | `training_stats.dart`, `stats_report_tab.dart` | `test/training_stats_test.dart` (plan created mid-window: 1 of 1 instead of 3 of 13) | Coach Stats on a new demo account |
| V-16 · L-07 | One region-to-muscle map (app names) with one translation to the backend's names; the readiness card now marks the same groups the plan pauses | `injury_service.dart` (`kBodyRegionToAppMuscleGroups`, `kAppGroupToBackendGroup`, `pausedAppGroupsFor`), `coach_screen.dart` | `test/injury_reminder_test.dart` (every region gives the same groups in both places) | UT-REC-03 readiness card (shoulder: Shoulders + Arms; lower back: Back + Core; hip: Legs + Glutes) |
| V-18 | `if (!mounted) return;` before each `setState` after an `await` in `_loadRecovery` | `coach_screen.dart` | — | — |
| V-26 · P1-5 · D-22 | Template workouts top up from the library (same group, matching equipment, closest difficulty) when the pool gives fewer than 3. Template code moved to a data file so it can be tested | `lib/features/workout/data/workout_templates.dart`, `workout_screen.dart` | `test/workout_screen_test.dart` (Back + dumbbell/bench now >= 3) | UT-SCH-06 |
| V-27 · L-06 | Coach insight no longer says "Rest and ice" or promises rehab exercises; says what the plan does and points to the Terms ("not medical advice") | `coach_screen.dart` | — | Coach Recovery tab with an active and a recovering injury |

### Second batch (29 Oct 2026)

| ID | Change | Where | Tests | Rerun |
|---|---|---|---|---|
| P0-2 · D-24 | Rules read `isPrivate` with `.get('isPrivate', false)` (activity visibility and follow create). New public docs get `isPrivate: false` when the username is claimed (never overwrites a user's choice). `UserProfileScreen` shows a message + TRY AGAIN instead of spinning when a read fails. One-off backfill script (dry run by default; demo accounts unless `--all-users`) | `firestore.rules`, `public_profile_service.dart`, `user_profile_screen.dart`, `tools/demo_seed/ch5_backfill_isprivate.py` | Backfill dry run on demo accounts: 6 public docs, 1 missing (`demo_ch5c`), nothing written | Deploy rules (`firebase deploy --only firestore:rules`), then UT-SOC-02 with a fresh account and `ch5_rules_test.py` (25 of 25). Then Bos runs the backfill with `--all-users` (dry run first, then `--apply`) |
| V-06 | `usernames` create/delete need `isVerified()`; read stays signed-in only. Usernames are only claimed behind the verification gate (onboarding, ChooseUsernameScreen) | `firestore.rules` | — | After the rules deploy: claim a username on a verified demo account (works) |
| P0-4 · D-27 + L-01 (+ L-02) | Injury rebuild only touches workout days that train a paused group (by split or by any exercise on the day) plus days an earlier rebuild changed; every other day keeps its exercises, adaptations and edits. Rebuilt days fill only up to each muscle's weekly maximum (Chest/Back/Legs/Glutes 20, Shoulders/Arms 16, Core 12 — the app's table), counting the days left as they are. A day that loses only some muscles (Push without shoulders) is marked (`originalWorkoutName`) and restored on recovery. The app skips the rebuild when the paused groups don't change (Active → Recovering, or another injury in an already paused area) | `backend/services/plan_generator.py`, `backend/routers/plan_router.py`; `injury_service.dart` (`changesPausedGroups`), `coach_screen.dart`, `log_injury_screen.dart` | `backend/tests/test_regenerate_plan.py` (+6: only touched days selected, added exercise counts, partial day marked and restored, weekly maximum over 20 seeded plans, endpoint leaves untouched days alone); `test/injury_reminder_test.dart` (Active → Recovering) | UT-REC-03 (weekly sets must not jump; chest stays ≤ 20), E2E-05, E2E-06 |
| V-12 · P1-7 | A session whose `/adapt-plan` call fails is queued on the device (per account, once per workout, kept 14 days) and retried on the next Home open, before the weekly run, using the workout's own time. When proposals exist and `/commit-adaptations` fails, the weekly run writes nothing and the checkpoint and week number don't advance, so it is retried next time (a week-4 deload can't be skipped) | `adapt_service.dart` (`queuePrediction`, `retryPendingPredictions`), `home_screen.dart`, `weekly_summary_service.dart` (`mustRetryWeeklyRun`) | `test/adaptation_retry_test.dart` | UT-WRK-14 / IT-10: finish a workout in airplane mode, reconnect, open Home: a pending proposal appears |
| V-19 | Library ADD TO WORKOUT follows the day screen's rules: while this week's session on that day is still to come it opens the day and asks SAVE TO MY PLAN / JUST THIS TIME there; when the day is over (or holds a different session this week) it adds to the plan from next week and keeps this week's day as it was. Schedule and Home refresh (`scheduleChanges`) | `exercise_detail_sheet.dart` (`addsThroughDayScreen`), `workout_day_detail_screen.dart` (`addOnOpen`) | `test/library_add_test.dart` | Add from the library to a future day (scope sheet appears; Schedule shows it without restarting) and to a day already done this week (added from next week) |

### Third batch (29 Oct 2026) — Bos's decisions a–m

App only: no backend or Firestore rules changes, so only a new app build is
needed.

| ID | Change | Where | Tests | Rerun |
|---|---|---|---|---|
| V-09 (e) | A scheduled deload stores the sets/reps it cut from (`preDeloadSets`, `preDeloadReps`); the next weekly run starts from those, applies its own adjustment and clears them. Exercises no adjustment touches that run are simply restored. Forced (reactive) deloads are not undone. The −42.5% value is unchanged | `weekly_summary_service.dart` (`exerciseUpdate`) | `test/adaptation_retry_test.dart`: 3 × 10 → 2 × 6 → 3 × 10 (+ that week's adjustment) | `demo.deload` account: run the week-4 deload, then the week-5 run: sets come back |
| V-10 (f) | Weekly changes apply to every workout day of the template, not only weekdays after today (a Sunday run used to change nothing while marking proposals committed). This week's days already over (passed, or today once logged) keep their session as a "kept for this week" version, the same mechanism the Schedule tab uses, so the change shows from next week. The plan's exercises are now read once per run instead of once per proposal | `weekly_summary_service.dart` (`keepsThisWeeksDay`, `_keepThisWeeksPastDays`) | `test/adaptation_retry_test.dart` (Sunday run keeps Mon–Sat and changes them from next week) | A weekly run late in the week: earlier days change from next week; this week's past days look as they were |
| V-20 (i) | Weekly reminders are rescheduled from the current plan whenever it changes (any `scheduleChanges` bump: swaps, cancellations, rest-day conversions, library adds, injury rebuilds) and each time the app opens (covers plan generation and reset). Rest days get no reminder. Injury rebuilds now also bump `scheduleChanges` when they succeed, so Home and Schedule refresh after a background rebuild (L-05) | `notification_service.dart` (`weeklyReminderContent`, `refreshWeeklyReminders`), `main_shell.dart`, `injury_service.dart`, `settings_screen.dart` | `test/weekly_reminders_test.dart` | Reminders on → make a workout day a rest day → no reminder that day; log an injury → Schedule updates without restarting |
| V-21 (j) | Personal Stats and onboarding check age 13–80, height 100–250 cm and weight 30–300 kg. Changing the weight in Personal Stats also adds a weight record ("Updated in Personal Stats"), so Coach shows it | `validators.dart` (`bodyStats`), `edit_stats_screen.dart`, `step1_profile.dart`, `weight_record_service.dart` (`isWeightChange`) | `test/body_stats_test.dart` | Personal Stats: 1750 cm rejected; change weight → Coach shows the new weight |
| V-22 (k) | The 7-second countdown only runs while the camera detects the user; out of view it shows STEP INTO VIEW and starts over, so counting begins only after the user has been in view for the whole countdown | `pose_countdown_overlay.dart`, `pose_detection_screen.dart`, `auto_log_screen.dart` | `test/pose_countdown_test.dart` | UT-GDE-03 as written in the report |
| V-23 (l) | Arnold Press has form check (ShoulderPressAnalyser); 31 pose-enabled exercises. A test checks the analyser mapping equals the pose-enabled set exactly | `exercise_data.dart`, `angle_calculator.dart` (`explicitNames`) | `test/posture_variants_test.dart` | Arnold Press in the library: form check available |
| V-17 (h) | The reps × kg total (bodyweight sets add nothing) is labelled KG LIFTED / LIFTED everywhere it is shown (workout screen, workout complete, Coach stats tile and trend chip, weekly summary, activity card, log detail). The muscle-balance rule (bodyweight counts reps) is unchanged | `workout_active_screen.dart`, `workout_complete_screen.dart`, `stats_report_tab.dart`, `plan_changes_dialog.dart`, `activity_log_card.dart`, `workout_log_detail_screen.dart` | — | Look at those screens |
| (b) | One-time agreement step before onboarding for any account with no agreement on record (on the device or the profile): a new Google account from the Login screen, or an email account first opened on another phone. I AGREE records it as sign-up does; Sign out leaves | `lib/features/legal/screens/terms_agreement_screen.dart`, `auth_navigation_service.dart`, `legal_consent_service.dart` (`hasAccepted`) | `test/legal_consent_test.dart` | New Google account via **Login** → BEFORE YOU START screen → I AGREE → onboarding; profile has `termsAcceptedAt` |

## Deploying (P0-1 / V-07)

1. Install the new app build on every demo phone **first**. The new app works
   with the current backend (it still sends the body uid); the current app
   will get 401 from the new backend.
2. Then push and let Render redeploy. Confirm the live commit (P3-3 `/version`
   is still open, so check the commit in the Render dashboard for now).
3. Rerun `ch5_st14.py` (expect HTTP 401, plan count unchanged) and IT-01,
   IT-04, IT-07.

## Results after deploying

| Date | Test | Result |
|---|---|---|
| 29 Oct 2026 | ST-14 (`ch5_st14.py`, no ID token, B's uid in the body) | **Pass.** HTTP 401 "Missing ID token" in 0.1 s; B's plans 3 before, 3 after (D-15 fixed) |
| | ST-04 to ST-09 (`ch5_rules_test.py`, after `ch5_accounts.py delete demo.ch5b@rakan-demo.test`) | |

## Manual retest checklist (V-02)

Fixed in code after the test round, still "Open" in report 5.6. Run on the
phone with `*@rakan-demo.test` accounts and record pass/fail here.

| Test | Steps | Expected | Result |
|---|---|---|---|
| UT-SCH-08 (D-21, P0-3) | Log a workout on today's plan day. Open Schedule, long-press / open that day's actions; try Move to Another Day, Make It a Rest Day, and dragging it onto another day | The logged day can't be moved, made a rest day or dragged (actions hidden or disabled). No other day shows "WORKOUT COMPLETED" and the logged day isn't shown as missed | |
| L-04 | From the missed-day card on Home, reschedule a missed session to a later rest day this week. Open the Schedule tab | Schedule shows the rescheduled session on the new day (same as Home), not a rest day | |
| UT-AUTH-02 (D-28, P1-1) | Sign in with a verified account, close the app, turn on airplane mode, open the app | The app opens normally (or shows "Check your internet connection and try again." with TRY AGAIN), never VERIFY YOUR EMAIL | |

## Bos's decisions (29 Oct 2026)

| # | Decision | Outcome |
|---|---|---|
| a | Neck injury: pause Back and Shoulders? | **Not paused (kept as is), based on the evidence below.** Neck stays out of the region map; the card and the plan agree |
| b | New Google account from Login | One-time agreement step — done (third batch) |
| c | Consent time for email accounts | Fine as is (stored at onboarding) |
| d | Cap plan generation at the weekly max | No — generation stays uncapped (injury rebuilds stay capped) |
| e | V-09 deload restore | Done (third batch) |
| f | V-10 which days weekly changes reach | Every day, past days kept for this week — done |
| g | V-14 48-hour rule | Keep the current design; Bos updates report 4.5.7 and E2E-03 |
| h | V-17 volume | Label "kg lifted" — done |
| i | V-20 rest-day reminders | None — done |
| j | V-21 weight record | Yes — done |
| k | V-22 countdown waits for body | Yes — done |
| l | V-23 Arnold Press | Enable — done (31 exercises) |
| m | V-25 glitch filter / borderline band | No |

Evidence for (a): the JOSPT neck pain guideline (Blanpied et al., 2017)
recommends scapulothoracic and upper-extremity strengthening even for acute
neck pain with mobility deficits, and 2024 reviews find that strengthening
the neck, shoulder and scapular muscles reduces neck pain (low to moderate
certainty). Nothing found supports pausing all back and shoulder training.
Exercises that load the upper trapezius heavily (shrugs, overhead pressing)
do load the neck muscles, so a symptom-guided, gradual return applies; the
coach insight already says Rakan is not medical advice.

## Not done yet

- From the viva-prep list: V-24 (store camera form results).
- From the CH5 backlog: the remaining P1 items (P1-2, P1-3, P1-4, P1-8,
  P1-9, P1-10, P1-11, P1-12), P3-3 `/version`, P3-4 warm-up ping.
