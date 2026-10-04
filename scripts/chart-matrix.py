#!/usr/bin/env python3
"""Emit the lint matrix: one entry per chart, with that chart's lint inputs.

Usage: chart-matrix.py [changed-file ...]
With no arguments every chart is listed (push to main, manual runs). With
changed paths, only charts under charts/<name>/ that changed are listed; a
change outside charts/ (workflows, this script) lists every chart.

Per-chart inputs live beside the chart in ci/lint-inputs.json (keys: set,
examples-set, render-defaults), so a chart's lint is described by the chart.
Writes `matrix=<json>` and `any=<true|false>` to $GITHUB_OUTPUT.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARTS = sorted(d for d in os.listdir(os.path.join(ROOT, "charts"))
                if os.path.isfile(os.path.join(ROOT, "charts", d, "Chart.yaml")))


def inputs(name):
    p = os.path.join(ROOT, "charts", name, "ci", "lint-inputs.json")
    try:
        with open(p) as f:
            d = json.load(f)
    except FileNotFoundError:
        d = {}
    return {"chart": name,
            "set": d.get("set", ""),
            "examples-set": d.get("examples-set", ""),
            "render-defaults": bool(d.get("render-defaults", True))}


# Guard: release.yml's `chart` choices must be exactly the charts here, or a
# new chart is unreleasable (missing) or a deleted one still offered (extra).
with open(os.path.join(ROOT, ".github", "workflows", "release.yml")) as f:
    text = f.read()
block = text.split("options:", 1)[1].split("confirm:", 1)[0]
offered = sorted(l.strip()[2:].strip() for l in block.splitlines() if l.strip().startswith("- "))
if offered != CHARTS:
    sys.exit(f"release.yml chart options {offered} != charts/ {CHARTS}")

changed = sys.argv[1:]
if not changed or any(not c.startswith("charts/") for c in changed):
    pick = CHARTS
else:
    pick = sorted({c.split("/")[1] for c in changed} & set(CHARTS))
matrix = {"include": [inputs(n) for n in pick]}
out = f"matrix={json.dumps(matrix)}\nany={'true' if pick else 'false'}\n"
dest = os.environ.get("GITHUB_OUTPUT")
if dest:
    with open(dest, "a") as f:
        f.write(out)
print(out, end="")
