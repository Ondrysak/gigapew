#!/usr/bin/env python3
"""Run visual-lab scenarios and collect their screenshots.

    python3 tools/lab.py shop boss          # selected scenarios
    python3 tools/lab.py all --out lab_shots
    python3 tools/lab.py --list

Renders in an invisible 1280x720 gamescope session (real GPU) when gamescope is
installed, else in a normal window. Screenshots and lab_report.txt land in
--out (default: lab_shots/, git-ignored). Exit status is non-zero when any
scenario check fails, the run times out, or no report is written.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GODOT = Path.home() / ".local/opt/godot/4.7.2/godot"
LAB_SCENE = "res://scenes/lab/lab.tscn"
REPORT = "lab_report.txt"


def scenario_names() -> list[str]:
    text = (ROOT / "scripts/lab/lab.gd").read_text()
    block = text.split("const SCENARIOS := {", 1)[1].split("}", 1)[0]
    return re.findall(r'&"([a-z_]+)"', block)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("scenarios", nargs="*", default=["all"])
    parser.add_argument("--out", default="lab_shots")
    parser.add_argument("--godot", default=os.environ.get("GODOT", str(DEFAULT_GODOT)))
    parser.add_argument("--window", action="store_true", help="render in a visible window instead of gamescope")
    parser.add_argument("--clean", action="store_true", help="hide the lab overlay label in captures")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--verbose", action="store_true", help="print all engine output")
    parser.add_argument("--sound", action="store_true", help="play audio through the real output device instead of the silent Dummy driver")
    args = parser.parse_args()

    known = scenario_names()
    if args.list:
        print("\n".join(known))
        return 0
    unknown = [name for name in args.scenarios if name != "all" and name not in known]
    if unknown:
        parser.error(f"unknown scenario(s) {unknown}; known: {', '.join(known)}")

    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    report = out / REPORT
    report.unlink(missing_ok=True)

    # The Dummy driver still mixes, so SFX-bus captures work, but nothing reaches the speakers.
    audio = [] if args.sound else ["--audio-driver", "Dummy"]
    command = [args.godot, *audio, "--path", str(ROOT), LAB_SCENE, "--", f"--scenario={','.join(args.scenarios)}", f"--out={out}"]
    if args.clean:
        command.append("--clean")
    if not args.window and shutil.which("gamescope"):
        command = ["gamescope", "--backend", "headless", "-W", "1280", "-H", "720", "-w", "1280", "-h", "720", "--"] + command

    process = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    for line in process.stdout.splitlines():
        if args.verbose or line.startswith("LAB") or "SCRIPT ERROR" in line or line.startswith("ERROR") or "   at: " in line:
            print(line)

    if not report.exists():
        print(f"lab: no report written ({report}); the engine likely crashed or failed to parse a script", file=sys.stderr)
        return 2
    failures = [line for line in report.read_text().splitlines() if line.startswith("FAIL")]
    print(f"lab: {out}  ({report.read_text().splitlines()[0]})")
    engine_error = any(line.startswith("SCRIPT ERROR") or line.startswith("ERROR:") for line in process.stdout.splitlines())
    return 1 if failures or engine_error or process.returncode != 0 else 0


if __name__ == "__main__":
    sys.exit(main())
