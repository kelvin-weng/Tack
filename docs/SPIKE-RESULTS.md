# Tack – spike results

19 Oct 2026. MacBook Pro 14" (M1 Pro, notch), macOS 26.6.2, Xcode 27.1. External 34" ultrawide (3440x1440 pt at 2x) arranged above the MacBook, Spaces shared across displays. Spike code: `spike/`.

## Summary

| Test | Result | One line |
| --- | --- | --- |
| 1. Mirroring | PASS | Sharp, smooth, correct aspect; Messenger call in sync with audio. |
| 2. Swap in place | PASS | With press handoff, the pin behaves like the real window: clicks, drags, text selection and call buttons work first time. |
| 2b. Overlapping pins | PASS | Last-touched pin stays on top; no presses leak between pins. |
| 3. Notch panel | PASS | Looks like part of the hardware notch; hover expand/collapse smooth; doesn't block the menu bar. |
| 4. Performance | PARTIAL PASS | Realistic mix (2 videos + 4 static pins) runs without stutter. 6 large video pins stutter slightly. Needs designed-in frame skipping and idle throttling. |

The approach in REQUIREMENTS section 2 (mirror + swap in place) is viable. Seven findings below change or add requirements.

## Key findings

1. **Press handoff (Kelvin's idea).** Swap in on mouse-*down*; when the real window is ready, replay only the mouse-down if the button is still held, so the real app owns the rest of the gesture (window drag, text selection, scrubbing). If already released, replay a click. Press reaches the real window in ~35–75 ms typically (worst seen 173 ms). This removed every drag problem between displays: macOS moves the real window natively and the pin follows.
2. **Hover and scroll need a click.** The pin catches the mouse, so apps never see hover (Messenger hides call buttons until hover). Forwarding mouse moves to the window was delivered but ignored by Chrome; working around it needs private APIs. Kelvin accepts: one click reveals hover controls.
3. **Occlusion stops rendering.** If a pin is an opaque rectangle fully covering its source window, macOS reports the window as hidden and Chrome stops drawing video (mirror goes black after a few seconds). A pin must never opaquely cover its whole window; rounded transparent corners (12 pt) are enough.
4. **ScreenCaptureKit sends frames for unchanged windows.** Every captured window gets a full new frame (dirty rect = whole window) whenever anything on its display updates; static windows arrived at 50–57 fps. Redrawing those pins made it worse (each redraw triggered more captures). Skipping identical frames dropped static pins to ~1 shown frame/s and keeps the Mac smooth, but the pixel fingerprint costs 1–4 ms per frame (dominated by locking the surface). The MVP should design this in properly and profile it with Instruments.
5. **Cost is driven by moving pixels, not pin count.** WindowServer carries most of the load (compositing + capturing large videos). Base the soft warning on how much moving content is pinned.
6. **macOS menu-bar rule.** AppKit pushes a window down when its top is above the menu bar of the screen holding most of it. This applies to Tack's own panels too (fixed by overriding `constrainFrameRect`), and to source windows moved via Accessibility (no fix; avoided by press handoff).
7. **Pin stack.** While a pin's real window is in use, other pins must drop below it, or a handed-over press lands on another pin.

## 1. Mirroring – PASS
- YouTube in Chrome: sharp on Retina. Messenger video call: smooth, in sync with audio.
- 60 fps cap (display is 120 Hz). Mirrors show the source video's own rate (30–60 fps).
- Not tested: Spotify (low risk), DRM-protected content (e.g. Netflix in Safari, Apple TV app), which may capture as black.

## 2. Swap in place – PASS
- Messenger call (Chrome pop-up): mute, unmute, drag across displays and hang-up all worked first time. When the call window closed, its pin closed too.
- First click: the click must be replayed only after the real window is focused and topmost under the cursor, or Chrome treats it as an activation click and ignores it.
- Moving a pin: the real window must move on every mouse event (syncing afterwards lagged visibly), from a fixed cursor offset (summing deltas drifted). With press handoff this is only needed for the first ~50 ms of a drag.
- A plain click on the drag area (top 32 pt, 3 pt threshold) still swaps in; releasing a drag brings the real window forward, like dragging a real title bar.
- Following a native drag of the real window must never push back on it (an early feedback loop made the window snap back).
- Swapping back can flash briefly (the clicked app draws over the pin's spot before Tack reacts). A global mouse-down monitor plus hiding the pin via alpha made it rare; revisit in MVP.

## 2b. Overlapping pins – PASS
- While a pin's real window is in use, other pins drop to normal level just below it; afterwards they float again and the last-used pin goes on top. Matches "the pin being actively used always rises to the top".

## 3. Notch panel – PASS
- Notch size from `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`: 185x32 pt on this Mac.
- One fixed-size transparent panel above the menu bar (main menu level + 3); the black shape (outward top flares, rounded bottom corners) animates inside it with a SwiftUI spring. Clicks pass through except over the expanded shape.
- Kelvin: idle notch looks normal; wings and list look right; animations "perfect"; only expands when hovered, so it doesn't get in the way. Screenshots: `~/Desktop/Screenshot 2026-10-19 at 9.27.04 pm.png`, `9.27.10 pm.png`.
- MVP: when a window's title equals its app name (Calendar, Activity Monitor), don't show the name twice.

## 4. Performance – PARTIAL PASS
Release build, mirrors showing, 30 s averages from `top`.

| Scenario | WindowServer CPU / mem | TackSpike CPU / mem | replayd | Mac idle | Feel |
| --- | --- | --- | --- | --- | --- |
| A: 6 YouTube videos, no pins | 37.6% / 1.9 GB | 0.1% / 14 MB | 0% | – | – |
| B: 6 video pins, first spike build | 97.0%* / 2.8 GB | 16.4% / 28 MB | 7.9% | 43% | Whole Mac stuttered |
| B3: 6 video pins, optimised | 89.5% / 2.3 GB | 18.2% / 25 MB | 8.0% | 48% | "Much less, still a little" |
| R: 2 video + 4 static pins, optimised | 86.8% / 2.4 GB | 21.2% / 27 MB | 8.2% | 57% | – |
| R2: same, + skip identical frames + idle throttle | 90.7% / 2.3 GB | 19.3% / 25 MB | 7.3% | 53% | No stutter; typing updates show |

\* Inflated: Mission Control was opened during the run.

- No fans and no thermal or performance warnings in any run.
- Video pins were ~1720x720 pt each on the 2x ultrawide (~5 MP per pin): an extreme case.
- Optimisations kept: YUV 420v capture (~1.5 bytes/pixel instead of 4), queue depth 3 (was 5), 1 fps while swapped in, skip identical frames, 10 fps after ~0.5 s without change. Together these cut ~0.5 GB of WindowServer memory and removed the stutter for a realistic mix; CPU stayed high with large playing videos.
- 120 fps round not run: 60 fps already loads WindowServer heavily with video pins.

## Permissions
- Screen Recording: prompt on first launch; the app needed a relaunch after granting before windows could be listed.
- Accessibility: prompt on first launch.
- Development only: ad-hoc signed builds lose both permissions on every rebuild. Fixed by signing with a free Apple Development certificate (personal team); the Apple WWDR G3 intermediate certificate had to be installed manually first.

## Recommended requirement changes
1. **Section 2, interaction:** add press handoff as the interaction model.
2. **Section 2, limitation:** hover and scrolling on a pin need a click first. Explain on the "How Tack works" screen.
3. **Section 2, rule:** a pin never fully, opaquely covers its source window (keep rounded transparent corners even with the border off, F14).
4. **F5:** moving a pin needs a drag area (spike: top 32 pt); dropping a drag swaps the real window in.
5. **Open item "Pin performance soft limit":** base the warning on pinned moving content (size of video/animated pins), not count. Suggested copy: "Lots of moving pins can slow your Mac down."
6. **Proposed "Smooth motion (120 fps)" setting:** defer to post-1.0; revisit after MVP profiling.
7. **F13 (hide pins from screen sharing):** `sharingType = .none` works on pin panels; it doesn't change capture load.

## Next
- MVP architecture: capture pipeline with change detection and idle throttling designed in, profiled with Instruments.
- Quick checks to fold into MVP testing: Spotify, a DRM-protected video, a notch-less display, Spaces separate per display.
