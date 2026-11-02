"""Tack icon v3: flat Icon Composer layers + single-colour glyph, matched to the approved 3D render."""
import math, os
from shapely.geometry import Point, Polygon
from shapely import affinity

OUT = "/mnt/user-data/outputs/icon"
os.makedirs(OUT, exist_ok=True)
C = 1024

def path_from_poly(p, scale=1.0, nd=1):
    def ring(coords):
        pts = list(coords)[:-1]
        return "M " + " L ".join(f"{x*scale:.{nd}f} {y*scale:.{nd}f}" for x, y in pts) + " Z"
    d = ring(p.exterior.coords)
    for hole in p.interiors:
        d += " " + ring(hole.coords)
    return d

def svg(body, size=C, vb=None):
    vb = vb or f"0 0 {size} {size}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="{vb}">\n'
            f'{body}\n</svg>\n')

# ---- geometry (1024 canvas), calibrated to the render ----
SX, SY, SR = 512, 512, 304                     # sphere
DX, DY, DRX, DRY, DROT = 548, 470, 190, 160, -18  # dent: slightly up-right of centre, tilted

sphere = affinity.translate(affinity.scale(Point(0, 0).buffer(1, resolution=128), 324, 315), 510, 514)  # matches render (slightly squished)
def ellipse(cx, cy, rx, ry, rot):
    e = affinity.scale(Point(0, 0).buffer(1, resolution=128), rx, ry)
    return affinity.translate(affinity.rotate(e, rot, origin=(0, 0)), cx, cy)

dent = ellipse(DX, DY, DRX, DRY, DROT)
# Rim light: the crescent on the dent's lower-left inner edge (as in the render)
rim = dent.difference(affinity.translate(dent, 20, -18)).buffer(-2).buffer(2)
# Soft shoulder: a wider halo around the dent, one step lighter than the dent floor
shoulder = ellipse(DX, DY, DRX + 46, DRY + 40, DROT).intersection(sphere)

layers = {
    "1_sphere.svg":   f'<path d="{path_from_poly(sphere)}" fill="#00CEC8"/>',
    "2_shoulder.svg": f'<path d="{path_from_poly(shoulder)}" fill="#00BDB8"/>',
    "3_dent.svg":     f'<path d="{path_from_poly(dent)}" fill="#00A6A1"/>',
    "4_dent-rim.svg": f'<path d="{path_from_poly(rim)}" fill="#E6FFFE"/>',
}
for n, b in layers.items():
    open(os.path.join(OUT, n), "w").write(svg(b))

# ---- glyph: ball with the dent's rim crescent cut out (single colour, transparent bg) ----
# 32-unit grid -> crisp at 16 pt (@2x = 32 px) and fine at 13 pt.
G = 32
k = G / C
gball = Point(16, 16).buffer(14.5, resolution=64)
gdent = ellipse(DX * k + 0.2, DY * k, DRX * k * 1.05, DRY * k * 1.05, DROT)
gcres = gdent.difference(affinity.translate(gdent, 1.7, -1.5))   # ~2.4 units thick at widest
glyph = gball.difference(gcres)
open(os.path.join(OUT, "tack-glyph.svg"), "w").write(
    svg(f'<path d="{path_from_poly(glyph, nd=2)}" fill="#000000"/>', size=G))
print("ok", glyph.area, gcres.area)

# ---- alternate glyph: blu tack lump stuck to a surface, thumb hollow on top ----
from shapely.geometry import Point as P, box
body = affinity.translate(affinity.scale(P(0, 0).buffer(1, resolution=96), 14.6, 13.6), 16, 18.4)
body = body.intersection(box(0, 0, 32, 27.6))                       # flat base: stuck down
thumb = affinity.translate(affinity.scale(P(0, 0).buffer(1, resolution=96), 7.2, 5.0), 16.6, 4.4)
lump = body.difference(thumb).buffer(2.8, resolution=32).buffer(-2.8, resolution=32)
lump = lump.buffer(-3.2, resolution=48).buffer(3.2, resolution=48)  # round the base corners too
minx, miny, maxx, maxy = lump.bounds
lump = affinity.translate(lump, 16 - (minx + maxx) / 2, 16 - (miny + maxy) / 2)
open(os.path.join(OUT, "tack-glyph-alt-profile.svg"), "w").write(
    svg(f'<path d="{path_from_poly(lump, nd=2)}" fill="#000000"/>', size=G))
print("alt ok", lump.bounds)
