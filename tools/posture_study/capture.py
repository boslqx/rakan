"""
Rakan — Posture accuracy study: live VALIDATION log capture
===========================================================

WHY THIS EXISTS
---------------
The posture analysers in lib/features/workout/services/angle_calculator.dart
emit one line per counted rep via debugPrint, e.g.

    VALIDATION|pushup|2|56.0|166.6|true
    VALIDATION|squat|3|92.4|true
    VALIDATION|deadlift|1|71.2|false

Those lines only tell us what the SYSTEM predicted. An accuracy study also
needs the GROUND TRUTH (what the tester actually did). So this script does
two jobs at once:

  1. Streams `adb logcat` from the phone, parses every VALIDATION line, and
     writes it to a CSV automatically (no copy-pasting from the terminal).
  2. Lets the observer (you) declare the intended form for each set with a
     one-letter command, so every captured rep is stamped with a ground-truth
     label at the moment it happens.

Protocol it supports (controlled-condition design):
  - Tester does a set of deliberately CORRECT reps      -> type `c`
  - Tester does a set of deliberately INCORRECT reps    -> type `i shallow`
    (the word after `i` is a fault tag, e.g. shallow, hips_sag, no_lockout)
  - If the tester didn't actually do what was intended on a rep, flip it
    with `x` (last rep) or `x 4` (rep 4 of the current set).
  - If the app FAILED to count a rep you saw, type `m` — that is logged
    separately so rep-detection rate can be reported too.

Standard library only — runs with any Python 3.8+, no venv needed.

USAGE (from the repo root, PowerShell):
    python tools/posture_study/capture.py --tester T01
    python tools/posture_study/capture.py --tester T02 --adb "C:\\path\\to\\adb.exe"
"""

import argparse
import csv
import os
import re
import shutil
import subprocess
import sys
import threading
from datetime import datetime

# --------------------------------------------------------------------------
# Parsing
# --------------------------------------------------------------------------
# Squat / deadlift: VALIDATION|exercise|rep|minAngle|isCorrect          (5 fields)
# Push-up:          VALIDATION|pushup|rep|minElbow|minBodyLine|isCorrect (6 fields)
# Angles may be the literal "null" when the analyser never saw a value.
VALIDATION_RE = re.compile(r"VALIDATION\|([^\s]+)")

CSV_COLUMNS = [
    "timestamp",
    "tester_id",
    "set_id",
    "exercise",
    "rep_no",
    "min_angle",
    "min_body_line",
    "predicted_correct",     # what the app said (true/false); blank for missed reps
    "ground_truth_correct",  # what the tester actually did (true/false/blank=unlabelled)
    "fault_tag",             # e.g. shallow, hips_sag — only for incorrect sets
    "app_counted",           # true = app logged this rep; false = observer logged a missed rep
    "gt_flipped",            # true if observer corrected the ground truth for this rep
    "note",
]


def _num(s):
    return "" if s in ("null", "", None) else s


def parse_validation_line(line):
    """Return a dict for a VALIDATION logcat line, or None if not one."""
    m = VALIDATION_RE.search(line)
    if not m:
        return None
    parts = ("VALIDATION|" + m.group(1)).strip().split("|")
    if len(parts) == 5:
        _, ex, rep, angle, correct = parts
        body = ""
    elif len(parts) == 6:
        _, ex, rep, angle, body, correct = parts
    else:
        return None
    correct = correct.strip().lower()
    if correct not in ("true", "false"):
        return None
    try:
        rep_no = int(rep)
    except ValueError:
        return None
    return {
        "exercise": ex.strip().lower(),
        "rep_no": rep_no,
        "min_angle": _num(angle),
        "min_body_line": _num(body),
        "predicted_correct": correct,
    }


# --------------------------------------------------------------------------
# Session state (shared between the logcat thread and the command loop)
# --------------------------------------------------------------------------
class Session:
    def __init__(self, tester_id, out_path):
        self.tester_id = tester_id
        self.out_path = out_path
        self.rows = []
        self.lock = threading.Lock()
        self.set_id = 0
        self.gt = None          # "true" / "false" / None (unlabelled)
        self.fault = ""
        self.last_exercise = None
        self.last_rep_no = 0

    # ---- set management -------------------------------------------------
    def new_set(self, gt, fault=""):
        with self.lock:
            self.set_id += 1
            self.gt = gt
            self.fault = fault
            self.last_rep_no = 0
            self.last_exercise = None   # first rep after a manual new set must not auto-bump
            label = "CORRECT" if gt == "true" else f"INCORRECT ({fault or 'untagged'})"
            say(f"--- Set {self.set_id} started - ground truth: {label} ---")

    # ---- rows ------------------------------------------------------------
    def add_app_rep(self, parsed):
        with self.lock:
            # The analyser's repCount restarts at 1 when a new detection
            # session opens. If we see the counter go backwards, or the
            # exercise changes, the tester has started a new set on the
            # phone — open a new set automatically with the same label so
            # (set_id, rep_no) stays unique.
            if self.set_id == 0:
                self.set_id = 1
                say("(auto) set 1 opened - UNLABELLED. Type c or i <fault> before reps next time.")
            elif (
                self.last_exercise is not None
                and (parsed["exercise"] != self.last_exercise
                     or parsed["rep_no"] <= self.last_rep_no)
            ):
                self.set_id += 1
                say(f"(auto) new set {self.set_id} detected on phone - "
                    f"keeping label {self._label()}")
            self.last_exercise = parsed["exercise"]
            self.last_rep_no = parsed["rep_no"]

            row = {
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "tester_id": self.tester_id,
                "set_id": self.set_id,
                **parsed,
                "ground_truth_correct": self.gt or "",
                "fault_tag": self.fault if self.gt == "false" else "",
                "app_counted": "true",
                "gt_flipped": "false",
                "note": "",
            }
            self.rows.append(row)
            self._save()
        match = ""
        if row["ground_truth_correct"]:
            match = "  OK" if row["ground_truth_correct"] == row["predicted_correct"] else "  << MISMATCH"
        else:
            match = "  ! UNLABELLED - type c or i <fault> before the next set"
        say(f"[set {row['set_id']}] {row['exercise']} rep {row['rep_no']}: "
            f"angle={row['min_angle'] or '-'}"
            + (f" body={row['min_body_line'] or '-'}" if row['exercise'] == 'pushup' else "")
            + f"  app={row['predicted_correct']}  truth={row['ground_truth_correct'] or '?'}{match}")

    def add_missed_rep(self):
        with self.lock:
            if self.last_exercise is None:
                say("Can't log a missed rep yet - no exercise seen. Do one counted rep first.")
                return
            row = {
                "timestamp": datetime.now().isoformat(timespec="seconds"),
                "tester_id": self.tester_id,
                "set_id": self.set_id,
                "exercise": self.last_exercise,
                "rep_no": "",
                "min_angle": "",
                "min_body_line": "",
                "predicted_correct": "",
                "ground_truth_correct": self.gt or "",
                "fault_tag": self.fault if self.gt == "false" else "",
                "app_counted": "false",
                "gt_flipped": "false",
                "note": "missed by app (observer-logged)",
            }
            self.rows.append(row)
            self._save()
        say(f"[set {row['set_id']}] logged a MISSED rep ({row['exercise']})")

    def flip(self, rep_no=None):
        with self.lock:
            target = None
            for r in reversed(self.rows):
                if r["app_counted"] != "true" or r["set_id"] != self.set_id:
                    continue
                if rep_no is None or r["rep_no"] == rep_no:
                    target = r
                    break
            if target is None:
                say("No matching rep in the current set to flip.")
                return
            if not target["ground_truth_correct"]:
                say("That rep is unlabelled - nothing to flip.")
                return
            target["ground_truth_correct"] = "false" if target["ground_truth_correct"] == "true" else "true"
            target["gt_flipped"] = "false" if target["gt_flipped"] == "true" else "true"
            if target["ground_truth_correct"] == "true":
                target["fault_tag"] = ""
            elif not target["fault_tag"]:
                target["fault_tag"] = "observer_flip"
            self._save()
        say(f"Flipped set {target['set_id']} rep {target['rep_no']} -> truth={target['ground_truth_correct']}")

    def note(self, text):
        with self.lock:
            if not self.rows:
                say("No rows yet to attach a note to.")
                return
            r = self.rows[-1]
            r["note"] = (r["note"] + "; " if r["note"] else "") + text
            self._save()
        say("Note attached to last row.")

    def status(self):
        with self.lock:
            counted = [r for r in self.rows if r["app_counted"] == "true"]
            labelled = [r for r in counted if r["ground_truth_correct"]]
            hits = sum(1 for r in labelled if r["ground_truth_correct"] == r["predicted_correct"])
            missed = sum(1 for r in self.rows if r["app_counted"] == "false")
            by_ex = {}
            for r in labelled:
                by_ex.setdefault(r["exercise"], [0, 0])
                by_ex[r["exercise"]][1] += 1
                if r["ground_truth_correct"] == r["predicted_correct"]:
                    by_ex[r["exercise"]][0] += 1
        say(f"Tester {self.tester_id} | current set {self.set_id} label={self._label()}")
        say(f"  reps counted by app: {len(counted)}  (labelled: {len(labelled)}, missed by app: {missed})")
        if labelled:
            say(f"  running accuracy: {hits}/{len(labelled)} = {hits / len(labelled):.1%}")
        for ex, (h, n) in sorted(by_ex.items()):
            say(f"    {ex:<9} {h}/{n} = {h / n:.1%}")

    def _label(self):
        if self.gt is None:
            return "UNLABELLED"
        return "CORRECT" if self.gt == "true" else f"INCORRECT({self.fault or 'untagged'})"

    # ---- persistence -----------------------------------------------------
    def _save(self):
        """Rewrite the whole CSV after every change (file is tiny).

        Written to a temp file then swapped in, so a crash mid-write can't
        leave a half-written CSV. If Excel has the file open, Windows will
        refuse the swap — rows stay safe in memory and are retried next save.
        """
        tmp = self.out_path + ".tmp"
        try:
            with open(tmp, "w", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=CSV_COLUMNS)
                w.writeheader()
                w.writerows(self.rows)
            os.replace(tmp, self.out_path)
        except PermissionError:
            say("! Could not write CSV (is it open in Excel?). Close it - data is kept in memory "
                "and will be written on the next rep/command.")


_print_lock = threading.Lock()


def say(msg):
    with _print_lock:
        print(msg, flush=True)


# --------------------------------------------------------------------------
# adb
# --------------------------------------------------------------------------
def find_adb(explicit):
    if explicit:
        return explicit
    found = shutil.which("adb")
    if found:
        return found
    local = os.environ.get("LOCALAPPDATA")
    if local:
        guess = os.path.join(local, "Android", "Sdk", "platform-tools", "adb.exe")
        if os.path.exists(guess):
            return guess
    sys.exit("adb not found. Pass it explicitly: --adb \"C:\\Users\\User\\AppData\\Local\\Android\\Sdk\\platform-tools\\adb.exe\"")


def logcat_reader(adb, session, stop_event):
    # debugPrint() output lands in logcat under the tag "flutter".
    # -s flutter  : only that tag (drops the thousands of system lines)
    # Clear the buffer first so reps from an earlier run aren't re-captured.
    subprocess.run([adb, "logcat", "-c"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cmd = [adb, "logcat", "-v", "brief", "-s", "flutter"]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, encoding="utf-8", errors="replace", bufsize=1)
    except FileNotFoundError:
        say(f"! Could not start adb at: {adb}")
        stop_event.set()
        return
    session.proc = proc
    for line in proc.stdout:
        if stop_event.is_set():
            break
        parsed = parse_validation_line(line)
        if parsed:
            session.add_app_rep(parsed)
        elif "error:" in line.lower() and "device" in line.lower():
            say("! adb: " + line.strip() + "  - is the phone plugged in with USB debugging on?")
    say("(logcat stream ended - phone disconnected? Restart the script to resume; "
        "rows so far are saved.)")


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
HELP = """
Commands (type then Enter):
  c               start a set of CORRECT-form reps
  i <fault>       start a set of INCORRECT-form reps, e.g.  i shallow   i hips_sag
  n               new set, same label as before
  x               flip ground truth of the LAST rep (tester didn't do what was intended)
  x <rep>         flip ground truth of rep <rep> in the current set
  m               app MISSED a rep you saw (logs a missed-rep row)
  note <text>     attach a note to the last row
  s               status / running accuracy
  h               this help
  q               save and quit
"""


def main():
    ap = argparse.ArgumentParser(description="Capture Rakan VALIDATION logs with ground-truth labels.")
    ap.add_argument("--tester", required=True, help="Anonymised tester ID, e.g. T01 (don't use real names)")
    ap.add_argument("--adb", help="Path to adb.exe if it isn't on PATH")
    ap.add_argument("--out-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))
    args = ap.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_path = os.path.join(args.out_dir, f"posture_{args.tester}_{stamp}.csv")

    adb = find_adb(args.adb)
    session = Session(args.tester, out_path)
    session.proc = None
    stop = threading.Event()

    say(f"Writing to: {out_path}")
    say(f"Using adb:  {adb}")
    say(HELP)
    say("Set the label FIRST (c or i <fault>), then have the tester start the set on the phone.\n")

    t = threading.Thread(target=logcat_reader, args=(adb, session, stop), daemon=True)
    t.start()

    try:
        while True:
            try:
                raw = input().strip()
            except EOFError:
                break
            if not raw:
                continue
            cmd, _, rest = raw.partition(" ")
            cmd = cmd.lower()
            rest = rest.strip()
            if cmd == "c":
                session.new_set("true")
            elif cmd == "i":
                session.new_set("false", rest.replace(" ", "_").lower())
            elif cmd == "n":
                if session.gt is None:
                    say("No label yet - use c or i <fault>.")
                else:
                    session.new_set(session.gt, session.fault)
            elif cmd == "x":
                if rest:
                    try:
                        session.flip(int(rest))
                    except ValueError:
                        say("Usage: x <rep number>")
                else:
                    session.flip()
            elif cmd == "m":
                session.add_missed_rep()
            elif cmd == "note":
                session.note(rest)
            elif cmd == "s":
                session.status()
            elif cmd in ("h", "help", "?"):
                say(HELP)
            elif cmd in ("q", "quit", "exit"):
                break
            else:
                say("Unknown command - type h for help.")
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        if session.proc:
            session.proc.terminate()
        with session.lock:
            session._save()
        say(f"\nSaved {len(session.rows)} rows -> {out_path}")
        session.status()


if __name__ == "__main__":
    main()
