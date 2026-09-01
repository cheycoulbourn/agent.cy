#!/usr/bin/env python3
"""L1 evidence: measures the rendered diameter and interior fill of the app's
circular close controls from simulator screenshots in this directory.
Run: python3 measure-close-controls.py    (screenshots are 3x, iPhone 17 Pro)"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from png_measure_lib import load_png
os.chdir(os.path.dirname(os.path.abspath(__file__)))

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
    s, e, wd, y = best
    return ground, wd / 3.0, g((s + e) // 2, y)

CASES = [
    ("weekly-focus Close  (light)", "sheet-weeklyFocus-light.png", 230, 420, 40, 300, 1150, 420),
    ("weekly-focus Close  (dark)",  "sheet-weeklyFocus-dark.png",  230, 420, 40, 300, 1150, 420),
    ("voice-spark Close   (light)", "sheet-voiceSpark-light.png",  270, 400, 40, 300,  600, 300),
]
for label, f, *args in CASES:
    ground, pt, fill = widest_circle(f, *args)
    print(f"{label}: ground={ground}  diameter={pt:.2f} pt  interior fill={fill}")
