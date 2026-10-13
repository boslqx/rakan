"""Builds Rakan's extended exercise library from the exercises-dataset.

The curated list lives in extended_exercises_spec.txt (next to this file):
which dataset exercises are used, their Rakan display names, muscle group,
difficulty, equipment, form tips and any corrected steps. This script joins
that spec with the dataset (instructions, secondary muscles, media) and
writes:

  lib/features/workout/data/exercise_data_extended.dart   every spec entry
  backend/data/exercises_extended.py                      entries flagged '*'
  assets/exercise_gifs/, assets/exercise_thumbnails/       media copies

Media is (c) Gym visual (https://gymvisual.com/) and is redistributed by
the dataset at 180x180 with an attribution requirement, so every generated
entry carries sourceAttribution.

Usage, from the repo root:
  python backend/scripts/build_extended_exercises.py --dataset "<path>/exercises-dataset-main"
  python backend/scripts/build_extended_exercises.py --dataset "<path>" --check   (validate only)

Spec format, one exercise per line (' | ' separated):
  id | name | difficulty B/I/A | flags | equipment | secondary | sets | tips
    flags:     c compound or i isolation (one required), * also in backend
               pool, h timed hold, u unilateral (sets guide says "each ...")
    secondary: '-' to derive from the dataset, else comma-separated names
               from kGranularToBroadMuscleGroup
    sets:      '-' to derive, else the exact setsRepsGuide text
    tips:      2-3 tips separated by ';'
  '## Group' starts a muscle group section; a line starting with '>'
  replaces the previous entry's dataset steps (steps separated by ' | ').
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SPEC = Path(__file__).resolve().parent / "extended_exercises_spec.txt"
DART_LIBRARY = REPO / "lib/features/workout/data/exercise_data.dart"
DART_RECOVERY = REPO / "lib/features/workout/data/muscle_recovery_constants.dart"
DART_OUT = REPO / "lib/features/workout/data/exercise_data_extended.dart"
PY_LIBRARY = REPO / "backend/data/exercises.py"
PY_OUT = REPO / "backend/data/exercises_extended.py"
GIF_DIR = REPO / "assets/exercise_gifs"
THUMB_DIR = REPO / "assets/exercise_thumbnails"

ATTRIBUTION = "© Gym visual — https://gymvisual.com/"

GROUPS = {  # spec heading -> (Dart MuscleGroups member, backend muscle_group)
    "Chest": ("chest", "chest"),
    "Back": ("back", "back"),
    "Shoulders": ("shoulders", "shoulders"),
    "Arms": ("arms", "arms"),
    "Legs": ("legs", "legs"),
    "Glutes": ("glutes", "glutes"),
    "Core": ("core", "abs"),
}
DIFFICULTY = {"B": "Beginner", "I": "Intermediate", "A": "Advanced"}

# Dataset secondary-muscle names -> Rakan granular names. Names not listed
# (ankles, feet, shins, groin, neck) have no Rakan equivalent and are dropped.
SECONDARY_MAP = {
    "shoulders": "Shoulders", "deltoids": "Shoulders",
    "rear deltoids": "Rear Deltoids", "rotator cuff": "Rotator Cuff",
    "chest": "Chest", "upper chest": "Upper Chest",
    "triceps": "Triceps", "biceps": "Biceps", "brachialis": "Brachialis",
    "forearms": "Forearms", "wrists": "Forearms", "wrist flexors": "Forearms",
    "wrist extensors": "Forearms", "grip muscles": "Forearms", "hands": "Forearms",
    "upper back": "Upper Back", "rhomboids": "Upper Back", "back": "Upper Back",
    "latissimus dorsi": "Lats", "lats": "Lats",
    "trapezius": "Trapezius", "traps": "Trapezius",
    "lower back": "Lower Back",
    "core": "Core", "abdominals": "Core", "lower abs": "Core",
    "obliques": "Obliques", "hip flexors": "Hip Flexors",
    "glutes": "Glutes", "hamstrings": "Hamstrings", "quadriceps": "Quads",
    "calves": "Calves", "soleus": "Calves",
}
# Dataset primary target -> Rakan granular name. Used as a secondary muscle
# when an exercise is filed under a different group than its dataset target
# (e.g. squats target "glutes" in the dataset but live under Legs here).
TARGET_MAP = {
    "pectorals": "Chest", "serratus anterior": "Serratus Anterior",
    "upper back": "Upper Back", "lats": "Lats", "spine": "Lower Back",
    "traps": "Trapezius", "levator scapulae": "Trapezius",
    "delts": "Shoulders", "biceps": "Biceps", "triceps": "Triceps",
    "forearms": "Forearms", "quads": "Quads", "hamstrings": "Hamstrings",
    "calves": "Calves", "abductors": "Hip Abductors", "glutes": "Glutes",
    "abs": "Core",
}
# Rakan granular name -> backend secondary_muscles vocabulary
BACKEND_SECONDARY = {
    "Chest": "chest", "Upper Chest": "chest", "Inner Chest": "chest",
    "Lats": "back", "Upper Back": "back", "Trapezius": "back",
    "Serratus Anterior": "chest", "Lower Back": "lower back",
    "Shoulders": "shoulders", "Anterior Deltoids": "shoulders",
    "Front Deltoids": "shoulders", "Rear Deltoids": "shoulders",
    "Rotator Cuff": "shoulders",
    "Biceps": "biceps", "Brachialis": "biceps", "Triceps": "triceps",
    "Forearms": "forearms", "Wrists": "forearms",
    "Legs": "legs", "Quads": "legs", "Calves": "legs",
    "Hamstrings": "hamstrings", "Hip Flexors": "hip flexors",
    "Glutes": "glutes", "Hip Abductors": "glutes",
    "Core": "core", "Obliques": "core",
}
# Equipment tags with no onboarding equivalent. Exercises using them only
# match a full-gym profile (same rule as the hand-written library), so they
# can't go in the backend pool.
UNMAPPED_EQUIPMENT = {
    "parallel bars", "trx", "gymnastic rings", "stability ball",
    "medicine ball", "bosu ball",
}
# Name keywords plan_generator._target_group uses to file an "arms"
# exercise as triceps (anything else counts as biceps).
TRICEP_KEYWORDS = ("tricep", "dip", "skull", "close-grip", "pushdown", "extension")

DART_LIST = "kExtendedExercises"


def fail(msg):
    sys.exit(f"error: {msg}")


def dart_str(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def py_str(s):
    return json.dumps(s, ensure_ascii=False)


def read_dart_map(src, name):
    body = re.search(r"%s\s*=\s*\{(.*?)\n\};" % re.escape(name), src, re.S)
    if not body:
        fail(f"couldn't find {name}")
    return dict(re.findall(r"'([^']+)':\s*'?([\w.]+)'?", body.group(1)))


def load_rakan():
    library = DART_LIBRARY.read_text(encoding="utf-8")
    recovery = DART_RECOVERY.read_text(encoding="utf-8")
    equipment_map = read_dart_map(library, "kEquipmentTagToEnum")
    # granular muscle name -> spec group heading, e.g. 'Lats' -> 'Back'
    heading = {dart: spec for spec, (dart, _) in GROUPS.items()}
    granular = {
        k: heading[v.split(".")[-1]]
        for k, v in read_dart_map(recovery, "kGranularToBroadMuscleGroup").items()
    }
    # Hand-written libraries only (the generated files are rebuilt from scratch)
    app_names = {n.lower() for n in re.findall(r"^\s+name: '((?:[^'\\]|\\.)*)'", library, re.M)}
    backend_src = PY_LIBRARY.read_text(encoding="utf-8")
    backend_names = {n.lower() for n in re.findall(r'"name": "([^"]+)"', backend_src)}
    return equipment_map, granular, app_names, backend_names


def parse_spec():
    entries, group = [], None
    for lineno, raw in enumerate(SPEC.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("## "):
            group = line[3:].strip()
            if group not in GROUPS:
                fail(f"spec line {lineno}: unknown group {group!r}")
            continue
        if line.startswith("#"):
            continue
        if line.startswith(">"):
            if not entries:
                fail(f"spec line {lineno}: steps override before any entry")
            entries[-1]["steps"] = [s.strip() for s in line[1:].split(" | ") if s.strip()]
            continue
        parts = [p.strip() for p in line.split(" | ")]
        if len(parts) != 8:
            fail(f"spec line {lineno}: expected 8 fields, got {len(parts)}")
        if group is None:
            fail(f"spec line {lineno}: entry before any '## Group' heading")
        ex_id, name, diff, flags, equipment, secondary, sets, tips = parts
        if not re.fullmatch(r"\d{4}", ex_id):
            fail(f"spec line {lineno}: bad id {ex_id!r}")
        if diff not in DIFFICULTY:
            fail(f"spec line {lineno}: difficulty must be B/I/A")
        if not set(flags) <= set("*ciuh") or ("c" in flags) == ("i" in flags):
            fail(f"spec line {lineno}: flags {flags!r} need exactly one of c/i")
        tip_list = [t.strip() for t in tips.split(";") if t.strip()]
        if not 2 <= len(tip_list) <= 3:
            fail(f"spec line {lineno}: {name} needs 2-3 tips")
        entries.append({
            "line": lineno, "id": ex_id, "name": name, "group": group,
            "difficulty": DIFFICULTY[diff], "backend": "*" in flags,
            "compound": "c" in flags, "hold": "h" in flags,
            "unilateral": "u" in flags, "equipment": equipment,
            "secondary": None if secondary == "-" else [s.strip() for s in secondary.split(",")],
            "sets": None if sets == "-" else sets, "tips": tip_list, "steps": None,
        })
    return entries


def clean_steps(steps):
    out = []
    for s in steps:
        s = s.strip().replace("в°", "°")
        # "Repeat for the desired number of repetitions." adds nothing; keep
        # repeat lines that say to switch sides or alternate.
        if re.match(r"repeat\b", s, re.I) and not re.search(r"switch|other|alternat", s, re.I):
            continue
        if s and s[-1] not in ".!?":
            s += "."
        out.append(s[0].upper() + s[1:])
    return out


def equipment_tags(equipment):
    """First alternative's tags, lower-cased ('/' separates setups)."""
    first = equipment.split("/")[0]
    return [t.strip().lower() for t in first.split(",") if t.strip()]


def kind(e):
    tags = equipment_tags(e["equipment"])
    if e["hold"]:
        return "hold"
    if tags[0] in ("barbell", "ez-bar", "smith machine", "weight plate"):
        return "heavy"
    if tags[0] in ("machine", "cable machine", "roman chair"):
        return "machine"
    if tags[0] in ("resistance band",):
        return "band"
    if tags[0] in ("bodyweight", "pull-up bar", "parallel bars", "trx",
                   "gymnastic rings", "stability ball", "bosu ball", "bar"):
        return "bodyweight"
    return "free"  # dumbbells, kettlebells, medicine ball


def unilateral_suffix(e):
    if e["group"] in ("Legs", "Glutes"):
        return " each leg"
    if e["group"] == "Core":
        return " each side"
    return " each arm"


def is_calf(e):
    return "calf" in e["name"].lower() or "toe raise" in e["name"].lower()


def sets_guide(e):
    if e["sets"]:
        return e["sets"]
    k, diff = kind(e), e["difficulty"]
    if k == "hold":
        return {
            "Beginner": "3 holds × 20–30 seconds",
            "Intermediate": "3 holds × 20–40 seconds",
            "Advanced": "3–5 holds × 10–20 seconds",
        }[diff] + (unilateral_suffix(e) if e["unilateral"] else "")
    if e["compound"]:
        if k == "bodyweight":
            guide = {
                "Beginner": "3 sets × 10–15 reps",
                "Intermediate": "3 sets × 8–12 reps",
                "Advanced": "3–5 sets × 3–8 reps",
            }[diff]
        elif k == "heavy":
            guide = "4 sets × 6–10 reps"
        elif k == "band":
            guide = "3 sets × 12–15 reps"
        else:
            guide = "3–4 sets × 8–12 reps"
    elif is_calf(e):
        guide = "3–4 sets × 12–20 reps"
    elif e["group"] == "Core" or k == "band" or "wrist" in e["name"].lower():
        guide = "3 sets × 12–20 reps"
    else:
        guide = "3 sets × 10–15 reps"
    return guide + (unilateral_suffix(e) if e["unilateral"] else "")


def prescription(e):
    """Backend (sets, reps, rest_seconds), matching the guide's ranges."""
    k, diff = kind(e), e["difficulty"]
    if k == "hold":
        return 3, 1, 45 if e["group"] == "Core" else 60
    if e["sets"]:
        # A hand-written guide like "3–5 sets × 3–8 reps": fewest sets,
        # middle of the rep range, longer rest for low-rep strength work.
        m = re.match(r"(\d+)(?:–\d+)? sets × (\d+)(?:–(\d+))? reps", e["sets"])
        if not m:
            fail(f"spec line {e['line']} ({e['name']}): can't derive backend reps from {e['sets']!r}")
        low, high = int(m.group(2)), int(m.group(3) or m.group(2))
        reps = (low + high) // 2
        return int(m.group(1)), reps, 120 if reps < 6 else 75
    if e["compound"]:
        if k == "bodyweight":
            return {"Beginner": (3, 12, 60), "Intermediate": (3, 10, 75),
                    "Advanced": (3, 5, 120)}[diff]
        if k == "heavy":
            return 4, 8, 120
        if k == "band":
            return 3, 12, 60
        return (4, 10, 90) if k == "machine" else (3, 10, 75)
    if is_calf(e):
        return 4, 15, 45
    if e["group"] == "Core" or k == "band" or "wrist" in e["name"].lower():
        return 3, 15, 45
    return 3, 12, 60


def derive_secondary(e, ds, granular):
    group = e["group"]
    if e["secondary"] is not None:
        names = e["secondary"]
    else:
        names = []
        target = TARGET_MAP.get(ds["target"])
        if target and granular.get(target) != group:
            names.append(target)
        for m in ds["secondary_muscles"]:
            name = SECONDARY_MAP.get(m.lower())
            if name == "Shoulders" and group == "Chest":
                name = "Front Deltoids"
            elif name == "Shoulders" and group == "Back":
                name = "Rear Deltoids"
            if name:
                names.append(name)
        # A secondary in the exercise's own group would double-count it in
        # recovery tracking (workout_log_service credits secondaries at 0.5).
        names = [n for n in names if granular.get(n) != group]
    deduped = list(dict.fromkeys(names))
    return deduped if e["secondary"] is not None else deduped[:3]


def build(entries, dataset, equipment_map, granular, app_names, backend_names):
    seen_ids, seen_names = set(), set()
    for e in entries:
        where = f"spec line {e['line']} ({e['name']})"
        ds = dataset.get(e["id"])
        if ds is None:
            fail(f"{where}: id {e['id']} not in dataset")
        if e["id"] in seen_ids:
            fail(f"{where}: id {e['id']} used twice")
        seen_ids.add(e["id"])
        key = e["name"].lower()
        # An app-only entry may reuse a backend name the app library lacks —
        # that gives the existing backend exercise its media and steps.
        if key in seen_names or key in app_names or (e["backend"] and key in backend_names):
            fail(f"{where}: name already used")
        seen_names.add(key)

        e["media"] = f"{e['id']}-{ds['media_id']}"
        e["steps"] = clean_steps(e["steps"] or ds["instruction_steps"]["en"])
        e["secondary"] = derive_secondary(e, ds, granular)
        for m in e["secondary"]:
            if m not in granular:
                fail(f"{where}: unknown secondary muscle {m!r}")
        e["sets_guide"] = sets_guide(e)

        for alt in e["equipment"].split("/"):
            for tag in (t.strip().lower() for t in alt.split(",")):
                if tag not in equipment_map and tag not in UNMAPPED_EQUIPMENT:
                    fail(f"{where}: unknown equipment tag {tag!r}")

        if e["backend"]:
            enums = []
            for tag in equipment_tags(e["equipment"]):
                if tag in UNMAPPED_EQUIPMENT:
                    fail(f"{where}: {tag!r} has no onboarding equivalent, can't be in the backend")
                enum = equipment_map[tag]
                if enum != "noEquipment" and enum not in enums:
                    enums.append(enum)
            e["backend_equipment"] = enums or ["noEquipment"]
            e["backend_secondary"] = list(dict.fromkeys(
                BACKEND_SECONDARY[m] for m in e["secondary"]))
            e["prescription"] = prescription(e)
            if e["group"] == "Arms":
                is_tricep = ds["target"] == "triceps"
                named_tricep = any(k in key for k in TRICEP_KEYWORDS)
                if is_tricep != named_tricep:
                    fail(f"{where}: plan_generator would file this as "
                         f"{'triceps' if named_tricep else 'biceps'}")


def write_dart(entries):
    out = [
        "part of 'exercise_data.dart';",
        "",
        "// GENERATED by backend/scripts/build_extended_exercises.py from",
        "// backend/scripts/extended_exercises_spec.txt — edit the spec and re-run",
        "// the script rather than editing this file.",
        "//",
        f"// {len(entries)} exercises from the exercises-dataset. Media © Gym visual",
        "// (https://gymvisual.com/), redistributed by the dataset with permission.",
        "",
        f"const List<ExerciseData> {DART_LIST} = [",
    ]
    group = None
    for e in entries:
        if e["group"] != group:
            group = e["group"]
            out.append(f"  // {group.upper()}")
        dart_group = GROUPS[group][0]
        out += [
            "  ExerciseData(",
            f"    name: {dart_str(e['name'])},",
            f"    muscleGroup: MuscleGroups.{dart_group},",
            f"    secondaryMuscles: [{', '.join(dart_str(m) for m in e['secondary'])}],",
            f"    difficulty: {dart_str(e['difficulty'])},",
            f"    equipment: {dart_str(e['equipment'])},",
            "    youtubeId: '',",
            f"    setsRepsGuide: {dart_str(e['sets_guide'])},",
            "    steps: [",
            *[f"      {dart_str(s)}," for s in e["steps"]],
            "    ],",
            f"    tips: [{', '.join(dart_str(t) for t in e['tips'])}],",
            f"    sourceAttribution: {dart_str(ATTRIBUTION)},",
            f"    localGifAsset: 'assets/exercise_gifs/{e['media']}.gif',",
            f"    thumbnailAsset: 'assets/exercise_thumbnails/{e['media']}.jpg',",
            "  ),",
        ]
    out.append("];")
    DART_OUT.write_text("\n".join(out) + "\n", encoding="utf-8")


def write_python(entries):
    picked = [e for e in entries if e["backend"]]
    out = [
        "# GENERATED by backend/scripts/build_extended_exercises.py from",
        "# backend/scripts/extended_exercises_spec.txt — edit the spec and re-run",
        "# the script rather than editing this file.",
        "#",
        f"# {len(picked)} well-known exercises added to the plan generator's pool.",
        "# Every name here also exists in the Flutter library",
        "# (lib/features/workout/data/exercise_data_extended.dart), which the app",
        "# joins on by name for media, steps and tips.",
        "",
        "EXTENDED_EXERCISES = [",
    ]
    group = None
    for e in picked:
        if e["group"] != group:
            group = e["group"]
            out.append(f"  # {group.upper()}")
        sets, reps, rest = e["prescription"]
        out += [
            "  {",
            f"    \"name\": {py_str(e['name'])},",
            f"    \"muscle_group\": \"{GROUPS[group][1]}\",",
            f"    \"secondary_muscles\": [{', '.join(py_str(m) for m in e['backend_secondary'])}],",
            f"    \"equipment\": [{', '.join(py_str(m) for m in e['backend_equipment'])}],",
            f"    \"difficulty\": \"{e['difficulty'].lower()}\",",
            f"    \"sets\": {sets}, \"reps\": {reps}, \"rest_seconds\": {rest},",
            f"    \"is_compound\": {e['compound']},",
            "    \"wger_id\": None,",
            "  },",
        ]
    out.append("]")
    PY_OUT.write_text("\n".join(out) + "\n", encoding="utf-8")


def copy_media(entries, dataset_dir):
    copied = 0
    for e in entries:
        for src, dst in (
            (dataset_dir / "videos" / f"{e['media']}.gif", GIF_DIR / f"{e['media']}.gif"),
            (dataset_dir / "images" / f"{e['media']}.jpg", THUMB_DIR / f"{e['media']}.jpg"),
        ):
            if not src.is_file():
                fail(f"missing media {src}")
            if not dst.is_file() or dst.stat().st_size != src.stat().st_size:
                shutil.copyfile(src, dst)
                copied += 1
    return copied


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dataset", required=True, type=Path,
                        help="path to the exercises-dataset-main folder")
    parser.add_argument("--check", action="store_true",
                        help="validate and print the summary without writing anything")
    args = parser.parse_args()

    raw = json.loads((args.dataset / "data" / "exercises.json").read_text(encoding="utf-8"))
    dataset = {d["id"]: d for d in raw}
    equipment_map, granular, app_names, backend_names = load_rakan()
    entries = parse_spec()
    build(entries, dataset, equipment_map, granular, app_names, backend_names)

    print(f"{len(entries)} exercises, {sum(e['backend'] for e in entries)} in the backend pool")
    for g in GROUPS:
        in_group = [e for e in entries if e["group"] == g]
        diffs = {d: sum(e["difficulty"] == d for e in in_group) for d in DIFFICULTY.values()}
        print(f"  {g:<10} {len(in_group):>3} app  {sum(e['backend'] for e in in_group):>3} backend  "
              + "  ".join(f"{d[0]}{n}" for d, n in diffs.items()))
    if args.check:
        return

    write_dart(entries)
    write_python(entries)
    copied = copy_media(entries, args.dataset)
    print(f"wrote {DART_OUT.relative_to(REPO)} and {PY_OUT.relative_to(REPO)}; copied {copied} media files")


if __name__ == "__main__":
    main()
