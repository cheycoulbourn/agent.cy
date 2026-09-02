#!/usr/bin/env python3
"""L1 evidence: measures the rendered diameter and interior fill of the app's
circular close controls from simulator screenshots.
Run: python3 measure-close-controls.py    (screenshots are 3x, iPhone 17 Pro)

BEFORE cases read the discovery captures that live next to this script and show
the four geometries the app used to ship (44 pt glass, 48 pt glass, 40 pt and
44 pt opaque). AFTER cases read ../B1/task-4/, the captures taken once every
icon control became the one shared glass circle, and are checked against the
acceptance bar: 44 pt +/- 0.7, and one interior fill per appearance.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_measure_lib import load_png
os.chdir(os.path.dirname(os.path.abspath(__file__)))

TARGET_PT = 44.0
TOLERANCE_PT = 0.7


def widest_circle(path, y0, y1, x0, x1, gx, gy):
    w, h, bpp, px = load_png(path)
    def g(x, y):
        o = (y * w + x) * bpp
        return (px[o], px[o + 1], px[o + 2])
    ground = g(gx, gy)
    best = (0, 0, 0, 0)
    for y in range(y0, y1):
        start = None
        for x in range(x0, x1):
            p = g(x, y)
            if max(abs(p[i] - ground[i]) for i in range(3)) > 5:
                if start is None:
                    start = x
            elif start is not None:
                if x - start > best[2]:
                    best = (start, x - 1, x - start, y)
                start = None
        if start is not None and x1 - 1 - start > best[2]:
            best = (start, x1 - 1, x1 - 1 - start, y)
    s, e, wd, y = best
    return ground, wd / 3.0, g((s + e) // 2, y)

# Pre-Task-4 captures: four different geometries carrying the same job.
BEFORE_CASES = [
    ("weekly-focus Close  (light)", "sheet-weeklyFocus-light.png", 230, 420, 40, 300, 1150, 420),
    ("weekly-focus Close  (dark)",  "sheet-weeklyFocus-dark.png",  230, 420, 40, 300, 1150, 420),
    ("voice-spark Close   (light)", "sheet-voiceSpark-light.png",  270, 400, 40, 300,  600, 300),
]

# Task 4 captures: one glass circle everywhere.
AFTER_CASES = [
    ("weekly-focus-setup",            "../B1/task-4/weekly-focus-setup-%s.png",            230, 420,  40,  300, 1150, 420),
    ("voice-spark",                   "../B1/task-4/voice-spark-%s.png",                   250, 420,  40,  300,  900, 329),
    ("day-agenda-add-live-post",      "../B1/task-4/day-agenda-add-live-post-%s.png",      250, 420, 950, 1200,  600, 329),
    ("post-editor-spark-development", "../B1/task-4/post-editor-spark-development-%s.png", 230, 390,  40,  300,  700, 300),
]

print("== BEFORE (four geometries) ==")
for label, f, *args in BEFORE_CASES:
    if not os.path.exists(f):
        print(f"{label}: capture missing")
        continue
    ground, pt, fill = widest_circle(f, *args)
    print(f"{label}: ground={ground}  diameter={pt:.2f} pt  interior fill={fill}")

print()
print("== AFTER (one glass circle) ==")
failures = 0
fills = {}
for mode in ("light", "dark"):
    for label, pattern, *args in AFTER_CASES:
        path = pattern % mode
        if not os.path.exists(path):
            print(f"{label} ({mode}): capture missing at {path}")
            failures += 1
            continue
        ground, pt, fill = widest_circle(path, *args)
        ok = abs(pt - TARGET_PT) <= TOLERANCE_PT
        fills.setdefault(mode, {}).setdefault(fill, []).append(label)
        print(f"{label:32s} ({mode:5s}): ground={ground}  diameter={pt:.2f} pt  "
              f"interior fill={fill}  {'ok' if ok else 'FAIL'}")
        if not ok:
            failures += 1

print()
for mode, by_fill in fills.items():
    if len(by_fill) == 1:
        print(f"{mode}: one interior fill across all controls -- {list(by_fill)[0]}")
    else:
        print(f"{mode}: FAIL -- {len(by_fill)} different interior fills: {by_fill}")
        failures += 1

print()
if failures:
    print(f"measure-close-controls: {failures} failure(s)")
    sys.exit(1)
print("measure-close-controls: every control is 44 pt +/- 0.7 with one interior fill per appearance.")
