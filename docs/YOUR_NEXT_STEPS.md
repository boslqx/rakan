# Your next steps (29 Oct 2026)

Details of every change: `CHANGELOG_CH5.md`.

## Round 3 (your decisions a–m) — do this first

This round changed **only the app** (no backend, no Firestore rules), so
there is nothing to deploy to Render or Firebase.

**R1 · Commit** (check `git status` first, as before):

```
feat: decisions a-m (deload restore, weekly changes on every day, reminders, stats checks, countdown, Arnold Press, terms step)

V-09 deload restored the week after; V-10 weekly changes reach every plan
day (past days kept for this week); V-20 reminders follow plan changes, no
rest-day reminders, Schedule refreshes after injury rebuilds (L-05); V-21
body stat ranges + weight record; V-22 countdown waits for the user;
V-23 Arnold Press form check (31 exercises); V-17 "kg lifted" labels;
one-time terms step for new accounts without agreement (b).
Flutter 190 passed, backend 46 passed. See CHANGELOG_CH5.md.
```

**R2 · Rebuild and install the app** on every phone (same as Step 2 below:
`flutter build apk --release`, then `flutter install`).

**R3 · Retest on the phone** (record results in `CHANGELOG_CH5.md`):

| # | Test | Do | Expect |
|---|---|---|---|
| R-a | (b) terms step | Sign in with a **new** Google account from the **Login** screen | BEFORE YOU START screen → I AGREE → onboarding. Firestore profile has `termsAcceptedAt` |
| R-b | V-22 / UT-GDE-03 | Start a camera set while standing out of view; step in after 10 s | STEP INTO VIEW and the count stays at 7 until you're in view; leaving mid-count starts it over |
| R-c | V-23 | Exercise library → Arnold Press | Form check available and counts reps |
| R-d | V-21 | Settings → Personal Stats: height 1750 → save; then change the weight | 1750 rejected with a message; after the weight change, Coach shows the new weight |
| R-e | V-20 | Settings → reminders on; make a workout day a rest day (Schedule) | No reminder on that day any more (check the next reminder time shown in Settings) |
| R-f | V-20 / L-05 | Log an injury, wait ~1 min on the Schedule tab | Schedule updates by itself, without restarting |
| R-g | V-10 | On a Sunday (or late in the week), let a weekly run happen (`demo.adaptive`) | Earlier days' sessions this week look as they were; the plan's days change from next week |
| R-h | V-09 | `demo.deload` through the week-4 deload, then the week-5 run | Sets/reps go down in week 4 and come back in week 5 |
| R-i | V-17 | Finish a workout; open Coach → Stats | Tiles say KG LIFTED / LIFTED instead of VOLUME |

**R4 · Report changes for this round** (you edit the .docx):

- Test counts: **Flutter 190 passed, backend 46 passed, 29 Oct 2026**
  (replaces the 172/46 from earlier).
- 4.5: "only workout days after today are changed" is no longer true. Now:
  each weekly run changes every workout day of the plan; this week's days
  that are already over keep the session they had, so the change shows from
  next week. Also say the scheduled deload lasts one week: the sets/reps it
  cut are restored at the next weekly run.
- 4.5.7 and E2E-03 (you chose to keep the current design): describe it as
  one card per missed session (the whole day, whatever it trained). "Move to
  a rest day" offers the free rest days from today up to 7 days ahead and
  before that same workout comes round again; a missed session not handled
  within 7 days is skipped automatically. There is no 48-hour rule and no
  per-muscle card, so remove the Curovic (2025) 48-hour citation there.
- 5.3.7 UT-GDE-03: the countdown now does wait until the body is visible,
  so the test as written can pass (retest R-b).
- Form check: **31** exercises, not 30 (4.12 "30 of the 627" → "31 of the
  627", and wherever else 30 appears).
- Screens/tables showing VOLUME: now KG LIFTED (workout screen, Coach stats).
- Personal stats (Table 4.13.1): a changed weight now also appears in Coach.

**R5 · Still to do from the first rounds** (below): Step 3 (rules deploy)
if you haven't yet, the rules test (Step 5, after deleting `demo.ch5b`),
Step 6 (backfill), Step 7 (retests) and Step 8 (report).

---

## Step 1 · Commit

From `C:\Users\User\rakan`:

```bash
git add -A
```

```bash
git status
```

Check that `backend/serviceAccountKey.json` is **not** in the list (it is
git-ignored; it must never be committed). Then commit with this message:

```
fix: CH5 + viva-prep backlog (auth, consent, injury rebuild, adaptation retry)

P0-1/V-07 ID token on every backend endpoint; P0-2 isPrivate default;
P0-4 injury rebuild scope + weekly set cap; V-03..V-06, V-08, V-11..V-13,
V-15, V-16, V-18, V-19, V-26 (D-22), V-27 (L-06). Includes the follow-ups
to 7cc7fad and the legal screens.
Flutter 172 passed, backend 46 passed. See CHANGELOG_CH5.md.
```

Copy the commit hash (`git log -1 --format=%h`) into `CHANGELOG_CH5.md`
where it says _pending (Bos commits)_.

## Step 2 · Install the new app on every phone (before the backend)

With the phone connected by USB:

```bash
flutter build apk --release
```

```bash
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

The new app works with the old backend too, so nothing breaks yet.

## Step 3 · Deploy the Firestore rules

```bash
firebase deploy --only firestore:rules
```

(P0-2 `isPrivate` default and V-06 username rule.)

## Step 4 · Deploy the backend

```bash
git push origin main
```

Render redeploys `rakan-backend`. In the Render dashboard → rakan-backend →
Events, wait for "Deploy live" and check it shows your commit hash.
The first call after a deploy can take ~50 s (cold start).

## Step 5 · Automated checks against the live project

```bash
backend\venv\Scripts\python tools\demo_seed\ch5_st14.py
```

Expect `HTTP 401` and the same plan count before and after (ST-14 fixed).

```bash
backend\venv\Scripts\python tools\demo_seed\ch5_rules_test.py
```

Expect 25 of 25 as before.

## Step 6 · `isPrivate` backfill on production (P0-2)

Dry run first (writes nothing, lists the accounts missing the field):

```bash
backend\venv\Scripts\python tools\demo_seed\ch5_backfill_isprivate.py --all-users
```

If the list looks right, write it:

```bash
backend\venv\Scripts\python tools\demo_seed\ch5_backfill_isprivate.py --all-users --apply
```

Tip: run UT-SOC-02 (step 7, row 13) with a **fresh** account before this,
so you see the fix without the backfill's help.

## Step 7 · Retest on the phone

Use `*@rakan-demo.test` accounts. Write pass/fail in the Result column of
`CHANGELOG_CH5.md`.

| # | Test | Do | Expect |
|---|---|---|---|
| 1 | IT-01 + V-05 | Register a new email demo account (tick the terms box), verify, finish onboarding | Plan is generated. In Firestore, `users/{uid}/profile/data` has `termsAcceptedAt` and `termsVersion` ("29 October 2026") |
| 2 | UT-SET-07 + V-03 | Settings → Change Password: try `abcdef`, then `Rakan12!` | `abcdef` shows "New password does not meet all requirements" and the checklist; `Rakan12!` works. **The expected message in UT-SET-07 changes** |
| 3 | V-04 | Sign in with a Google-only account (needs a real Google test account; demo emails can't be Google accounts) | No Change Password tile in Settings |
| 4 | UT-REC-03 + P0-4 | Account with a Push/Pull/Legs plan: note the Schedule overview sets. Log a knee injury | Only the Legs day changes; Push and Pull keep their exercises; no muscle above its max (chest ≤ 20 sets) |
| 5 | P0-4 | Change that injury Active → Recovering | Plan doesn't change. Then mark Recovered: the Legs day comes back |
| 6 | E2E-05 / E2E-06 | Shoulder injury on a Push day, then recover | Push loses shoulder work while injured, and gets it back after recovery |
| 7 | IT-04 / IT-07 | Injury regeneration, then Settings → Update Fitness Goals (plan reset) | Both work (they now send the ID token) |
| 8 | UT-WRK-14 / IT-10 + V-12 | Airplane mode → finish a workout → back online → open Home | In Firestore `adaptationProposals`, a pending proposal for that workout appears |
| 9 | V-19 | Exercise library → ADD TO WORKOUT → a day later this week | The day opens with SAVE TO MY PLAN / JUST THIS TIME; Schedule shows it without restarting. Then try a day already done this week → "added to your plan from next …" |
| 10 | V-11 + UT-REC-01 | Recovery tab for a muscle last trained 6+ days ago | It isn't shown as fatigued any more |
| 11 | V-15 | Coach → Stats on a new account (30 days) | ON PLAN counts from the plan start, not "3 of 13" |
| 12 | V-16 | Log a hip injury | Readiness card marks Legs and Glutes (shoulder: Shoulders + Arms; lower back: Back + Core) |
| 13 | UT-SOC-02 + P0-2 | Fresh account B; follow it from account A; open B's profile | Follow works; profile loads (or shows a message), never spins forever |
| 14 | UT-SCH-06 + V-26 | Intermediate, dumbbells + bench: Schedule → rest day → Use Template → Back | At least 3 exercises |
| 15 | V-27 | Recovery tab with an active, then a recovering injury | Insight says the plan pauses the groups and that Rakan isn't medical advice; no "ice", no "rehab exercises" |
| 16 | V-08 | Release build: `adb logcat` while doing a camera form-check set | No `VALIDATION` lines (debug builds still print them) |
| 17 | UT-SCH-08 (D-21) | Log today's workout; in Schedule try Move / Make it a rest day / drag | Not allowed; no other day shows "WORKOUT COMPLETED" |
| 18 | L-04 | Reschedule a missed session from Home to a later day this week | Schedule shows it on the new day |
| 19 | UT-AUTH-02 (D-28) | Signed in, close app, airplane mode, open app | Opens normally (or the connection message), never VERIFY YOUR EMAIL |

## Step 8 · Update the report (you edit the .docx)

- Test counts (4.11, 5.2.1, 5.2.6, 6.1): **Flutter 172 passed, backend 46
  passed, 29 Oct 2026.**
- UT-SET-07: new expected message (step 7, row 2).
- 5.6: mark as "Fixed after testing" whatever passed in step 7: D-15, D-21,
  D-22, D-24, D-27, D-28, L-01, L-04, L-06, L-07.
- 5.7.2: "VALIDATION lines only in debug builds" is now true.
- 4.11 / 4.13: you can now mention the Terms, Privacy Policy and "not
  medical advice".

Ask me if you want draft sentences for any of these.

## Step 9 · Decisions

All answered on 29 Oct 2026 and implemented in Round 3 (see the table in
`CHANGELOG_CH5.md` → "Bos's decisions"). For (a), the research found that
guidelines recommend strengthening the shoulders and upper back for neck
pain, so a neck injury still pauses nothing.

## What's still open (I can continue on request)

V-24 (store camera form results), CH5 P1-2, P1-3, P1-4, P1-8 to P1-12,
P3-3 `/version`, P3-4 warm-up ping.
