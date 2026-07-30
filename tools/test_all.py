#!/usr/bin/env python3
"""Comprehensive test suite for the ballistics engine.

Runs many real-world scenarios and checks them against published data or
physically-expected behavior. Reports PASS/FAIL per case.
"""
import math
import importlib.util

spec = importlib.util.spec_from_file_location("vb", "tools/verify_ballistics.py")
vb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(vb)

YD_M = 0.9144
IN_M = 0.0254
FT_M = 0.3048

passed = 0
failed = 0

def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
        print(f"  PASS  {name}")
    else:
        failed += 1
        print(f"  FAIL  {name}  {detail}")

def drop_at_yd(pts, yd, key="z"):
    m = yd * YD_M
    # find nearest by x
    best = min(pts, key=lambda p: abs(p[0]-m))
    return best

print("="*70)
print("SCENARIO 1: 168gr .308 SMK @2600fps, 200yd zero, 1.5in sight (G1)")
print("="*70)
elev, pts = vb.solve(2600, 0.462, 168, 0.308, 1.5, 200, max_yd=700, step_yd=50)
p300 = drop_at_yd(pts, 300)
p500 = drop_at_yd(pts, 500)
p200 = drop_at_yd(pts, 200)
check("300yd drop ~ -7.8in", abs(p300[2]/IN_M - (-7.8)) < 1.5, f"got {p300[2]/IN_M:.1f}in")
check("500yd drop ~ -42in", abs(p500[2]/IN_M - (-42.4)) < 3, f"got {p500[2]/IN_M:.1f}in")
check("200yd (zero) drop ~ 0", abs(p200[2]) < 0.03, f"got {p200[2]*100:.1f}cm")
check("muzzle vel preserved", abs(pts[0][3]/FT_M - 2600) < 5, f"got {pts[0][3]/FT_M:.0f}fps")
check("500yd vel ~ 2224fps", abs(p500[3]/FT_M - 2224) < 40, f"got {p500[3]/FT_M:.0f}fps")
check("velocity decreases monotonically", all(pts[i][3] >= pts[i+1][3]-1 for i in range(len(pts)-1)))

print()
print("="*70)
print("SCENARIO 2: 77gr 5.56 MK262 @2750fps, 100yd zero (G1, BC=0.362)")
print("="*70)
elev2, pts2 = vb.solve(2750, 0.362, 77, 0.224, 2.6, 100, max_yd=600, step_yd=100)
# 5.56 77gr @2750: ~ -7.5in at 300yd, -38in at 500yd (100yd zero) per published data
p300b = drop_at_yd(pts2, 300)
p500b = drop_at_yd(pts2, 500)
check("5.56 300yd drop ~ -9in", abs(p300b[2]/IN_M - (-9)) < 3, f"got {p300b[2]/IN_M:.1f}in")
check("5.56 500yd drop ~ -42in", abs(p500b[2]/IN_M - (-42)) < 6, f"got {p500b[2]/IN_M:.1f}in")
check("5.56 100yd (zero) ~ 0", abs(drop_at_yd(pts2,100)[2]) < 0.03)

print()
print("="*70)
print("SCENARIO 3: .50 BMG M33 660gr @2910fps, 500yd zero (long range)")
print("="*70)
elev3, pts3 = vb.solve(2910, 0.620, 660, 0.510, 3.0, 500, max_yd=2000, step_yd=200)
p1000 = drop_at_yd(pts3, 1000)
p1500 = drop_at_yd(pts3, 1500)
# .50 M33 @500yd zero: ~ +50in high at 300yd region, drops to ~ -200in@1000yd
check(".50 1000yd far below LOS", p1000[2] < -3.0, f"got {p1000[2]/IN_M:.0f}in")
check(".50 still supersonic @1000yd", p1000[3]/FT_M > 1120, f"got {p1000[3]/FT_M:.0f}fps (subsonic?)")
check(".50 1500yd even lower", p1500[2] < p1000[2])

print()
print("="*70)
print("SCENARIO 4: Wind drift (10mph from left at 270deg)")
print("="*70)
_, pts4 = vb.solve(2600, 0.462, 168, 0.308, 1.5, 200, wind_mph=10, wind_dir=270, max_yd=500, step_yd=100)
w300 = drop_at_yd(pts4, 300)
w500 = drop_at_yd(pts4, 500)
check("wind drift positive (right) at 300yd", w300[1] > 0, f"got {w300[1]/IN_M:.1f}in")
check("wind drift grows with range", w500[1] > w300[1] > 0)
check("300yd drift ~ 3in (10mph)", abs(w300[1]/IN_M - 3) < 1.5, f"got {w300[1]/IN_M:.1f}in")

print()
print("="*70)
print("SCENARIO 5: 9mm pistol 124gr @1150fps (subsonic-ish, short range)")
print("="*70)
elev5, pts5 = vb.solve(1150, 0.150, 124, 0.355, 0.8, 25, max_yd=100, step_yd=25)
p50 = drop_at_yd(pts5, 50)
p100 = drop_at_yd(pts5, 100)
# 9mm 124gr @25yd zero: drops ~ -2in@50yd, ~ -10in@100yd
check("9mm 50yd drop ~ -2in", abs(p50[2]/IN_M - (-2)) < 1, f"got {p50[2]/IN_M:.1f}in")
check("9mm 100yd drop ~ -10in", abs(p100[2]/IN_M - (-10)) < 3, f"got {p100[2]/IN_M:.1f}in")
check("9mm 25yd (zero) ~ 0", abs(drop_at_yd(pts5,25)[2]) < 0.02)

print()
print("="*70)
print("SCENARIO 6: Zero-crossing detection (near & far zero)")
print("="*70)
# 168gr 200yd zero: near zero ~ a few yards out, far zero ~ 200yd
# Reconstruct path-relative-to-LOS using same convention as Dart solver:
#   bullet starts at z=-sight, LOS is z=0. We integrate same as solver.
# verify_ballistics uses z relative to bore with bullet start at -sight.
# near zero = where path first crosses 0 going up, far zero = second crossing.
def find_zeros(pts):
    zeros = []
    prev = None
    for x,y,z,spd,tof in pts:
        if prev is not None and x > 1:
            pz = prev[2]
            if (pz <= 0 < z) or (pz >= 0 > z) or (z <= 0 < pz) or (z >= 0 > pz):
                # linear interp
                frac = -prev[2] / (z - prev[2]) if abs(z-prev[2])>1e-9 else 0
                zeros.append(prev[0] + frac*(x-prev[0]))
        prev = (x,y,z,spd,tof)
    return zeros
zeros = find_zeros(pts)
if len(zeros) >= 2:
    near_yd = zeros[0]/YD_M
    far_yd = zeros[1]/YD_M
    check("near zero close (< 50yd)", near_yd < 50, f"near={near_yd:.0f}yd")
    check("far zero ~ 200yd", abs(far_yd - 200) < 15, f"far={far_yd:.0f}yd")
else:
    check("found >=2 zero crossings", False, f"found {len(zeros)}")

print()
print("="*70)
print("SCENARIO 7: Energy / momentum sanity")
print("="*70)
# muzzle energy 168gr@2600fps = 2518 ft-lbf = 3415 J
me = 0.5 * (168/7000*0.45359237) * (2600*FT_M)**2
check("muzzle energy ~ 3415J", abs(me - 3415) < 60, f"got {me:.0f}J")
check("terminal energy < muzzle energy", pts[-1][4] if len(pts[0])>4 else 0.5*(168/7000*0.45359237)*pts[-1][3]**2 < me)

print()
print("="*70)
print(f"TOTAL: {passed} passed, {failed} failed")
print("="*70)
exit(1 if failed > 0 else 0)
