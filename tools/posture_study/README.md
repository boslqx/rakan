# Posture Detection Accuracy Study (Objective 2)

Two scripts. They replace copying `VALIDATION|...` lines out of the terminal by hand.

| Script | Needs | Does |
|---|---|---|
| `capture.py` | Plain Python (standard library only) + `adb` | Streams logcat from the phone, parses every `VALIDATION` line, tags each rep with the ground-truth label you set, and writes `data/posture_<tester>_<time>.csv` live |
| `analyse.py` | `pandas` (already in `backend\venv`) | Merges every CSV in `data/` and writes the accuracy, confusion matrices, precision/recall, 95% CI and pass/fail vs 75% to `results/` |

## Why ground truth has to come from you

The app logs what it **predicted** (`true`/`false`). Accuracy means comparing that with what the tester **actually did**, and the app can't know that. So the study uses a controlled-condition design: before each set you tell the tester to do deliberately correct reps or deliberately faulty ones, and you type the matching label into `capture.py`. Every rep that arrives is stamped with that label automatically.

## Running a session

1. Plug in the S20 FE (USB debugging on) and run the app: `flutter run --no-dds`
2. In a **second** PowerShell window at the repo root:
   ```powershell
   python tools/posture_study/capture.py --tester T01
   ```
   If `adb` isn't on PATH, add `--adb "C:\Users\User\AppData\Local\Android\Sdk\platform-tools\adb.exe"`
3. For each set:
   - Type `c` (correct form) or `i shallow` (incorrect form, with a fault tag) **before** the tester starts
   - Open posture detection on the phone and the tester does the reps
   - Each rep prints live, e.g. `[set 1] pushup rep 2: angle=56.0 body=166.6 app=true truth=true OK`
4. Type `q` when the session is done. The CSV is saved after every rep anyway.

### Commands

| Command | Meaning |
|---|---|
| `c` | Next set is CORRECT form |
| `i <fault>` | Next set is INCORRECT form. Suggested tags: squat `shallow` / `forward_lean`; push-up `shallow` / `hips_sag` / `hips_pike`; deadlift `no_hinge` / `no_lockout`; RDL `knees_bent` / `shallow`; lunge `shallow` / `forward_lean`; press `no_lockout` / `uneven`; curl `half_rep` / `swing`. (`too_deep` was removed in Phase 29: deep squats are now correct — see `docs/POSTURE_THRESHOLDS.md`) |
| `n` | New set with the same label |
| `x` / `x 4` | Tester didn't do what was intended, so flip the ground truth of the last rep (or rep 4) |
| `m` | You saw a rep the app **didn't count**. Logged separately as the rep-detection rate |
| `note <text>` | Attach a note to the last row (lighting, clothing, camera angle…) |
| `s` | Running accuracy so far |

A new set on the phone (rep counter resets) or a change of exercise automatically starts a new `set_id` with the same label.

## Suggested protocol (per tester, per exercise)

- Camera side-on, full body in frame, phone at hip height, about 2–3 m away. Keep this the same for every tester and note it in the methodology.
- 2 sets × 5 correct reps + 2 sets × 5 incorrect reps (a different fault per set) gives 20 reps per exercise, matching the ≥20 target.
- 3–5 testers gives 60–100 reps per exercise.
- Use anonymised IDs (T01, T02…), never names.
- Optional but strong for the viva: screen-record or video each session so ground truth can be re-checked afterwards (use `x` for corrections).

## Analysing

```powershell
backend\venv\Scripts\python tools/posture_study/analyse.py
```

Outputs in `tools/posture_study/results/`:
- `summary.md`: tables ready to paste into the dissertation
- `metrics.csv`, `confusion_<exercise>.csv`, `all_reps_combined.csv`

**Metric definitions.** The positive class is incorrect form, because catching bad form is the system's job.
- *Accuracy* = (TP+TN)/N, reported with a 95% Wilson CI (small samples)
- *Recall* = share of genuinely bad reps the app flagged
- *Precision* = share of flagged reps that were genuinely bad
- *Specificity* = share of good reps correctly left alone
- *Rep detection rate* = reps counted ÷ (counted + observer-logged misses). Missed reps have no prediction, so they are excluded from accuracy and reported separately.

## VALIDATION line format (Phase 29)

`VALIDATION|exercise|rep|primary|secondary|isCorrect`. Only `deadlift` still logs the old 5-field form.

| exercise tag | primary (`min_angle` column) | secondary (`min_body_line` column) |
|---|---|---|
| `squat` | deepest knee angle | worst trunk lean (NEW — squat lines now have 6 fields) |
| `pushup` | deepest elbow angle | lowest body line |
| `pike_pushup` | deepest elbow angle | highest hip angle |
| `bench` | deepest elbow angle | — |
| `deadlift` | deepest hip angle | — |
| `rdl` | deepest hip angle | lowest knee angle |
| `lunge` | deepest front-knee angle | worst trunk lean |
| `press` | **highest** elbow angle (lockout) | largest left-right gap |
| `curl` | smallest elbow angle | largest upper-arm swing |

Variants log under their family tag (a goblet squat logs `squat`), so for the Objective 2 study keep to Bodyweight Squat, Push-Up and Barbell Deadlift, or add a `note` naming the variant. **Squat and push-up data logged before Phase 29 used the old depth rules — re-run them.**

## CSV columns

`timestamp, tester_id, set_id, exercise, rep_no, min_angle, min_body_line, predicted_correct, ground_truth_correct, fault_tag, app_counted, gt_flipped, note`
