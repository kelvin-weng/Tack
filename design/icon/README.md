# Tack icon – handoff for Claude Code (29 Oct)

Approved look: a round, translucent glass sphere in the putty colour (#00CEC8), pressed like blu tack. The dent is deep and soft, a little above and right of centre, with smooth shoulders, and the ball is slightly squished by the press. No thumbprint lines. See `reference/render-light.png` (target look), `render-dark.png` and `render-angled.png`.

This supersedes the brief in docs/STATUS.md ("not a perfect circle", "thumbprint dent") and `design/tack-icon-sketch-v2.svg`. REQUIREMENTS.md section 6 has been updated to match.

## App icon – Icon Composer layers
All four are flat, opaque, 1024×1024, with no mask and no baked effects. Bottom to top:

| File | What | Colour |
|---|---|---|
| `1_sphere.svg` | the ball (very slightly wider than tall, from the squash) | #00CEC8 |
| `2_shoulder.svg` | soft shoulder halo around the dent | #00BDB8 |
| `3_dent.svg` | dent floor | #00A6A1 |
| `4_dent-rim.svg` | light catching the dent's lower-left rim | #E6FFFE |

Suggested setup (tune against `render-light.png`):
- Background: automatic system light/dark (not exported).
- Group A = `1_sphere`. Group B = `2_shoulder` + `3_dent` + `4_dent-rim`, so the dent gets its own depth.
- Group A: translucency high, specular on, shadow on (neutral), refraction low. Keep it clear glass rather than solid.
- Group B: specular on, translucency medium. `4_dent-rim` can drop to about 80% opacity if it looks too crisp.
- Dark appearance: give the sphere more teal body. Clear glass goes almost black on a dark background (see `render-dark.png`).
- Check the Tinted and Clear variants. The rim crescent should still read as a dent.

## Glyph (menu bar and notch)
- `tack-glyph.svg` (main): a disc with the dent's rim crescent cut out. Single colour (black) on a transparent background, 32×32 viewBox. Use it as a template image in the menu bar (16 pt) and tinted #00CEC8 in the notch (13 pt). It replaces `pin.fill`.
- `tack-glyph-alt-profile.svg` (alternative): side view of a pressed lump with a flat base. Kelvin to choose. The main glyph is crisper at 16 pt, but its crescent cut-out could read as a moon (Focus/Do Not Disturb), so check it next to the system icons in the real menu bar.

`reference/layers-and-glyph-check.png` shows the layers over the render, and the glyphs at real sizes.

## Sources
- `reference/render-source.html`: three.js scene that produced the renders. It needs three@0.170 served locally.
- `reference/generate-layers.py`: regenerates the layers and glyphs (needs shapely).
