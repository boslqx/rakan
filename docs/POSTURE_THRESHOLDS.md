# Posture Detection — Thresholds, Evidence and Design (Phase 29)

This file explains every number in `FormThresholds`
(`lib/features/workout/services/angle_calculator.dart`): what it measures,
where it comes from, and how confident we are in it. It is written so the
dissertation's methodology chapter can quote it directly.

---

## 1. How an angle becomes a verdict

1. MediaPipe returns 33 landmarks per frame in normalised image coordinates.
2. `AngleCalculator.toPixelSpace()` converts them to **upright pixel space**:
   - scales x by frame width and y by frame height, so both axes use the same
     unit (Phase 28 fix — without it a 90° joint can read up to ~16° wrong on
     a 4:3 frame);
   - **new in Phase 29:** rotates the frame by CameraX's `rotationDegrees`
     (270° for the front camera held in portrait). Joint angles don't change
     under rotation, but the two new *gravity-referenced* measures do — trunk
     lean and shin angle are measured against real-world vertical, so the
     image must be upright first.
3. Each analyser picks the **visible side** of the body. In a side-on view
   the far limb is occluded and MediaPipe guesses it, so the near side
   (all landmarks with visibility ≥ 0.5) is used.
4. A shared `_RepTracker` counts reps with **hysteresis**: a rep is
   rest zone → work zone → back to rest. While a rep is in progress it
   records the primary angle's extreme and the worst value of each fault
   measure. When the rep finishes it is judged **once**, at its true
   extreme, and a `VALIDATION|...` line is logged for the accuracy study.
5. Live faults (e.g. leaning too far right now) turn the skeleton red
   immediately; depth/range faults are judged when the rep ends and shown
   as "Rep N: too shallow…" until the next rep.

### Counting vs. correctness — why there are two thresholds

Before Phase 29 most analysers only **counted** a rep if it reached the
correct depth. A shallow rep was therefore never counted and never judged —
it simply vanished. For Objective 2 that is a problem: the study needs the
app to say "this rep was wrong", not ignore it. Every analyser now has:

- a **looser counting threshold** (did the user attempt a rep?), and
- a **stricter correctness threshold** (was the rep good?).

A rep that passes the first but not the second is counted *and flagged*.

### The design rule

> **Threshold = published reference value + 10° measurement tolerance.**
> For joints judged near full extension (~180°) the tolerance is **20°**.

Why: 2D MediaPipe angles are not motion-capture accurate. Dill et al.
(2023) found MediaPipe angle accuracy is best for standing exercises such as
squats and degrades as conditions worsen and as a joint approaches straight.
A rule demanding the exact textbook angle would mark genuinely good reps as
wrong. Making the tolerance one explicit, named constant
(`FormThresholds.tolerance`) means the dissertation can state it once and
the accuracy study can test it.

Where no published number exists, the value is labelled **ENGINEERING
ESTIMATE** in code and below. These are exactly the values the Objective 2
study should scrutinise.

---

## 2. Exercise by exercise

### 2.1 Squat — Bodyweight, Barbell, Resistance Band, Goblet, Front

| Measure | Rule | Source |
|---|---|---|
| Inner knee angle (hip-knee-ankle) | Rep counted at ≤ 110° | Top of half-squat band (80–100°) + 10° |
| Depth (correctness) | Deepest point ≤ **80°** | Parallel squat ≈ 60–70° (Rojas-Jaramillo et al., 2024) + 10° |
| Standing | ≥ 160° | Unchanged |
| Trunk lean from vertical | Worst value ≤ **57°** | Graber et al. (2023): 37.8° ± 9.7° at parallel depth; mean + 2 SD |
| "Too deep" fault | **Removed** | 13 of 15 studies found deep squats safe for healthy knees (Rojas-Jaramillo et al., 2024) |

**Correction to the original implementation.** The old analyser treated
80–100° as "good depth" and flagged < 80° as "too deep". Rojas-Jaramillo et
al. (2024) classify squats by inner knee angle as quarter (110–140°), half
(80–100°), parallel (≈60–70°) and deep (40–45°). So the old "good" window
was a half squat, and a proper parallel squat — the depth the app's own
exercise library tells users to reach ("Lower until thighs are parallel to
the floor") — was marked wrong. Escamilla (2001) is often cited for
preferring parallel over deep squats; the newer scoping review supersedes
that caution for healthy knees, so the app now accepts anything parallel or
deeper.

**Trunk lean.** Graber et al. (2023) measured self-selected bodyweight
squats; at 110° of knee flexion (≈70° inner angle, i.e. parallel) trunk lean
was 37.8° ± 9.7°. Mean + 2 SD (57.2°) covers ~97.5% of normal squatters, so
only unusually large forward lean is flagged. The ±2 SD band (±19°) is
already wider than the measurement tolerance, so no extra margin is added.
Front-loaded squats are performed more upright than back squats (Sinclair et
al., 2016), but no paper found gives degree values for goblet/front squats,
so the same limit is applied to all squat variants rather than inventing a
stricter one.

### 2.2 Lunge / split squat — Forward, Reverse, Barbell lunge, Split squat, Bulgarian (bodyweight and dumbbell)

| Measure | Rule | Source |
|---|---|---|
| Front-knee inner angle | Counted at ≤ 120°; correct ≤ **100°** | Common 90° front-knee cue + 10°. Farrokhi et al. (2008) measured ≈70° inner (110° flexion) in a normal lunge, so 100° is a lenient lower bound on depth |
| Trunk lean from vertical | Worst value ≤ **30°** | Farrokhi et al. (2008) define the normal lunge with a vertical trunk; their deliberate trunk-forward variant raised hip flexion by ≈20°. 20° + 10° |

**Correction to the original implementation.** The front leg used to be
"whichever knee is more bent". In a Bulgarian split squat the rear foot is
on a bench, so the rear knee stays bent at the top — the analyser picked the
rear knee, never saw "standing", and never counted a rep. The front leg is
now the leg whose **shin is closer to vertical**, which holds for every lunge
and split-squat variant (the rear shin always slopes back).

### 2.3 Deadlift (conventional)

Unchanged thresholds (hip angle ≤ 100° to count the hinge, ≥ 165° lockout).
Only change: the near-side hip is used instead of requiring both hips
visible. Spinal rounding — the main deadlift fault — cannot be measured
reliably from MediaPipe's 33 landmarks (there are no spine points), so it is
not claimed.

### 2.4 Romanian deadlift — Barbell, Dumbbell (new)

| Measure | Rule | Source |
|---|---|---|
| Hip angle (shoulder-hip-knee) | Counted at ≤ 125°; lockout ≥ 165° | Same hinge logic as the deadlift |
| Knee bend (fault) | Inner knee angle stays ≥ **155°** | Knees held at ≈15° flexion (Physiopedia, n.d.); 15° + 10° = 25° flexion |
| Depth | Deepest hip angle ≤ **110°** | **ENGINEERING ESTIMATE.** Bar should reach just below the knee (Physiopedia, n.d.); with knees at ~165° that geometrically corresponds to a hip angle of roughly 100–110° |

### 2.5 Push-up family — Standard, Wide, Diamond, Close-grip, Incline, Decline

| Measure | Rule | Source |
|---|---|---|
| Elbow angle | Counted at ≤ 120°; correct ≤ **100°** | FitnessGram 90° push-up standard ("lower until a 90-degree angle at the elbows, upper arms parallel to the floor"; Topend Sports, n.d.) + 10° |
| Body line (shoulder-hip-ankle) | ≥ 160° | Unchanged; straight = 180°, near-extension tolerance 20° |

**Corrections.** (1) The old depth check accepted any rep that was counted
(≤ 110°), so depth was never actually judged — only the body line was.
(2) Both elbows had to be visible; in the recommended side-on view the far
elbow usually isn't, so it now uses the near arm.

**Pike push-up** (existing, corrected). It used the standard push-up check,
so its deliberately bent hips would always fail the straight-body test.
It now skips that check and instead flags hips dropping out of the pike
(shoulder-hip-ankle > **120°**, **ENGINEERING ESTIMATE**: the pike holds the
hips near 90°; past 120° it has become an ordinary declined push-up).

**Barbell bench press** (existing, corrected). It was routed to the push-up
analyser, so a lifter lying on a bench with feet on the floor was judged on
a plank line that doesn't exist. Bench now checks elbow depth only.

### 2.6 Shoulder press — Dumbbell, Seated dumbbell, Barbell overhead

Front-on view (both arms visible).

| Measure | Rule | Source |
|---|---|---|
| Elbow angle | Bottom ≤ 100°; top counted at ≥ 145°; lockout correct ≥ **160°** | Full extension 180° − 20° near-extension tolerance (value unchanged) |
| Left-right asymmetry | ≤ **20°** | Each arm carries ±10° measurement error, so up to 20° of difference can be noise alone; only a larger gap is reported |

The logged primary value for the press is the rep's **maximum** elbow angle
(lockout), not the minimum.

Arnold press was **not** enabled: it starts with the elbows in front of the
body, pointing at the camera, which foreshortens the upper arm in a front
view and would make both the angle and the asymmetry check unreliable.

### 2.7 Curl family — Seated dumbbell, Hammer, Barbell, Resistance band, Cable

**Side-on view** (changed from front-on).

| Measure | Rule | Source |
|---|---|---|
| Elbow angle | Counted at ≤ 70°; correct ≤ **50°**; extended ≥ 140° | 40–160° range of motion used by published MediaPipe curl counters; 40° + 10° (value unchanged) |
| Upper-arm swing (hip-shoulder-elbow) | ≤ **30°** | Chua et al. (2024): shoulder flexion stayed within ≈[−10°, 0°] in normal curls and drifted to ≈[0°, 20°] with fatigue-induced compensation; 20° + 10° |

**Why the view changed.** A curl moves the forearm in the sagittal plane,
straight towards a front-facing camera. In a 2D front view the forearm is
foreshortened, so the measured elbow angle no longer matches the real one.
From the side, the whole movement lies in the image plane.

---

## 3. Exercises deliberately left out

| Exercise | Reason |
|---|---|
| Arnold press | Elbows point at the camera at the start; front-view angle unreliable |
| Dumbbell walking lunge | User walks out of the frame |
| Jump squat | Ballistic; landmark blur at take-off/landing |
| Archer push-up | Asymmetric — the working arm alternates sides |
| Incline / concentration curl | Upper arm is not beside the torso, so the swing check would be invalid |
| Dumbbell bench / floor press, close-grip bench | Could reuse the bench analyser; not requested this phase |

---

## 4. Known limitations (state these in the dissertation)

- **2D only.** All angles are projections onto the image plane. Side-on
  views are used wherever the movement is sagittal so that the projection
  error is smallest.
- **Rotation assumption.** Gravity-referenced checks rely on the frame's
  `rotationDegrees`. The default (270°) matches what `SkeletonPainter`
  already assumes (front camera, portrait). A phone propped in landscape
  would need the real rotation value, which the native side already sends.
- **Engineering estimates.** RDL depth (110°) and pike hip (120°) have no
  direct published value.
- **No spine landmarks.** Back rounding is not measured for any hinge.
- **Validation still pending.** None of these thresholds has been validated
  against human-labelled reps yet. That is the job of the Objective 2
  accuracy study (`tools/posture_study/`).

---

## 5. References

Chua, M.X., Okubo, Y., Peng, S., Do, T.N., Wang, C.H. and Wu, L. (2024)
'Analysis of fatigue-induced compensatory movements in bicep curls: gaining
insights for the deployment of wearable sensors', *arXiv preprint*,
arXiv:2402.11421. Available at: https://arxiv.org/abs/2402.11421 (Accessed:
7 October 2026).

Dill, S., Rösch, A., Rohr, M., Güney, G., De Witte, L., Schwartz, E. and
Hoog Antink, C. (2023) 'Accuracy evaluation of 3D pose estimation with
MediaPipe Pose for physical exercises', poster presented at *BMT 2023*.
Available at:
https://smart-medication.eu/dokumente/beitraege/bmt-2023-poster-mediapipe-pose.pdf
(Accessed: 7 October 2026).

Escamilla, R.F. (2001) 'Knee biomechanics of the dynamic squat exercise',
*Medicine and Science in Sports and Exercise*, 33(1), pp. 127–141.

Farrokhi, S., Pollard, C.D., Souza, R.B., Chen, Y.J., Reischl, S. and
Powers, C.M. (2008) 'Trunk position influences the kinematics, kinetics,
and muscle activity of the lead lower extremity during the forward lunge
exercise', *Journal of Orthopaedic & Sports Physical Therapy*, 38(7),
pp. 403–409. doi: 10.2519/jospt.2008.2634.

Graber, K.A., Halverstadt, A.L., Gill, S.V., Kulkarni, V.S. and Lewis, C.L.
(2023) 'The effect of trunk and shank position on the hip-to-knee moment
ratio in a bilateral squat', *Physical Therapy in Sport*, 61, pp. 102–107.
doi: 10.1016/j.ptsp.2023.03.005.

Physiopedia (n.d.) *Romanian deadlift*. Available at:
https://www.physio-pedia.com/Romanian_deadlift (Accessed: 7 October 2026).

Rojas-Jaramillo, A., Cuervo-Arango, D.A., Quintero, J.D., Ascuntar-Viteri,
J.D., Acosta-Arroyave, N., Ribas-Serna, J., González-Badillo, J.J. and
Rodríguez-Rosell, D. (2024) 'Impact of the deep squat on articular knee
joint structures, friend or enemy? A scoping review', *Frontiers in Sports
and Active Living*, 6, 1477796. doi: 10.3389/fspor.2024.1477796.

Sinclair, J., Atkins, S., Vincent, H. and Richards, J.D. (2016) 'Modelling
muscle force distributions during the front and back squat in trained
lifters', *Central European Journal of Sport Sciences and Medicine*, 14(2),
pp. 13–20. doi: 10.18276/cej.2016.2-02.

Topend Sports (n.d.) *Push-up test*. Available at:
https://www.topendsports.com/testing/tests/pushup.htm (Accessed: 7 October
2026).
