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
| 29 Oct 2026 | 172 passed | 46 passed | After the second batch (**quote this one**). `flutter analyze`: no issues |

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

## Deploying (P0-1 / V-07)

1. Install the new app build on every demo phone **first**. The new app works
   with the current backend (it still sends the body uid); the current app
   will get 401 from the new backend.
2. Then push and let Render redeploy. Confirm the live commit (P3-3 `/version`
   is still open, so check the commit in the Render dashboard for now).
3. Rerun `ch5_st14.py` (expect HTTP 401, plan count unchanged) and IT-01,
   IT-04, IT-07.

## Manual retest checklist (V-02)

Fixed in code after the test round, still "Open" in report 5.6. Run on the
phone with `*@rakan-demo.test` accounts and record pass/fail here.

| Test | Steps | Expected | Result |
|---|---|---|---|
| UT-SCH-08 (D-21, P0-3) | Log a workout on today's plan day. Open Schedule, long-press / open that day's actions; try Move to Another Day, Make It a Rest Day, and dragging it onto another day | The logged day can't be moved, made a rest day or dragged (actions hidden or disabled). No other day shows "WORKOUT COMPLETED" and the logged day isn't shown as missed | |
| L-04 | From the missed-day card on Home, reschedule a missed session to a later rest day this week. Open the Schedule tab | Schedule shows the rescheduled session on the new day (same as Home), not a rest day | |
| UT-AUTH-02 (D-28, P1-1) | Sign in with a verified account, close the app, turn on airplane mode, open the app | The app opens normally (or shows "Check your internet connection and try again." with TRY AGAIN), never VERIFY YOUR EMAIL | |

## Decisions for Bos

- **Neck injuries:** the readiness card used to mark Back as injured for a
  neck injury, but the plan never paused anything for the neck. With one
  shared map the card now follows the plan (neck: nothing). If neck should
  pause Back, change `kBodyRegionToAppMuscleGroups` and both places follow.
- **New Google account from the Login screen:** it skips the terms checkbox,
  so no consent is recorded for it. Options: show a one-time agreement
  dialog after a first Google sign-in from Login, or send new Google users to
  Register.
- **Consent time for email accounts:** stored at onboarding (the first write
  the rules allow), not at the moment of sign-up. A narrow rules exception
  could store it at sign-up if the exact moment matters.
- **New plans already exceed the weekly maximum:** the injury rebuild is now
  capped, but plan generation itself is not. A 6-day, 90-minute advanced
  plan gives about 45 chest sets a week against the app's maximum of 20.
  Capping generation would change the plans and durations the report
  describes (Tables 5.2.3.x, D-13), so it needs your decision.

## Not done yet

- From the viva-prep list: V-20 (reminders after plan changes; needs the
  rest-day decision), V-21 (stats range checks), V-24 (store form results).
- From the CH5 backlog: the remaining P1 items (P1-2, P1-3, P1-4, P1-8,
  P1-9, P1-10, P1-11, P1-12), P3-3 `/version`, P3-4 warm-up ping.
- ASK BOS items, waiting for decisions: V-09, V-10, V-14, V-17, V-21 (weight
  record), V-22, V-23, V-25.
