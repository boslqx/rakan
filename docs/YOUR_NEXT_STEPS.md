# Your next steps (29 Oct 2026)

Do these in order. Steps 2–4 must stay in this order: the new backend
refuses calls without an ID token, so the phones need the new app first.
Details of every change: `CHANGELOG_CH5.md`.

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

## Step 9 · Decisions I need from you

Answer these in chat (one line each is enough); I'll implement them.

| # | Question | Options |
|---|---|---|
| a | Neck injury: should it pause Back? (Now it pauses nothing, and the card agrees.) | Keep as is / pause Back |
| b | A brand-new Google account made from the **Login** screen never sees the terms box. | Show a one-time agreement dialog / send new Google users to Register |
| c | Email accounts' `termsAcceptedAt` is the onboarding time, not sign-up time. | Fine as is / add a narrow rules exception to save it at sign-up |
| d | New plans already exceed the weekly max (6-day, 90-min plan: ~45 chest sets vs 20). Cap generation too? Changes the plans/durations the report describes. | Leave generation / cap it |
| e | V-09 deload never undone (3×10 → 2×6 forever). | Store pre-deload sets/reps and restore them the week after (my proposal) / other |
| f | V-10 weekly changes only touch days after today's weekday (Sunday run changes nothing). | Apply to every day of the template / keep and fix the report |
| g | V-14 reschedule: the 48-hour rule was removed in `7cc7fad`. | Restore the 48-hour floor / keep and update report 4.5.7, E2E-03 |
| h | V-17 two "volume" rules (workout screen counts bodyweight as 0). | Label the tile "kg lifted" / unify (changes Tier 2 trend) |
| i | V-20 reminders after plan changes: should rest days still get a "Rest Day" reminder? | Yes / no |
| j | V-21 Personal Stats: should a weight change also add a weight record (so Coach shows it)? | Yes / no |
| k | V-22 countdown: wait until the whole body is visible (as UT-GDE-03 expects)? | Yes / keep and update the report |
| l | V-23 Arnold Press: enable form check (31 exercises) or remove the mapping (stays 30)? | Enable / remove |
| m | V-25 posture: glitch filter + "almost there" message for 81–89° squats (80° stays)? | Yes / no |

## What's still open (I can continue on request)

V-20, V-21 (range checks), V-24 (store form results), CH5 P1-2, P1-3,
P1-4, P1-8 to P1-12, P3-3 `/version`, P3-4 warm-up ping.
