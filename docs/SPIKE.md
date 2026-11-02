# Tack – technical spike brief

Goal: prove the four risky parts of Tack work on Kelvin's MacBook before building the real app. Code is throwaway; speed over polish. Put it in spike/ as one small Xcode project (macOS 26, SwiftUI + AppKit, not sandboxed).

## Tests (each is pass/fail)

1. Mirroring
   - Use ScreenCaptureKit (SCShareableContent, SCContentFilter for a single window, SCStream) to mirror one chosen window into a borderless NSPanel at a floating level.
   - Test with a Messenger web video call pop-up in a browser, and with Spotify.
   - Pass: smooth live video, no noticeable lag, correct aspect ratio, sharp on Retina.

2. Swap in place
   - Use the Accessibility API to position the real window exactly under the pin.
   - On click of the pin: raise the real window (AXRaise + activate app) and hide the pin's mirror. When another app/window becomes frontmost: show the mirror again.
   - Moving/resizing the pin moves/resizes the real window.
   - Pass: clicking mute/hang-up on the call works first time; swap feels seamless with no visible jump.

3. Notch panel
   - Draw a black borderless window around the notch (use NSScreen.safeAreaInsets / auxiliaryTopLeftArea / auxiliaryTopRightArea to find it).
   - Collapsed: placeholder glyph left of the notch, pin count right.
   - On hover: expand smoothly downward, black, matching the notch's curves and corner radii. Show a list of pins.
   - Pass: looks like part of the hardware notch; hover expand/collapse is smooth.

4. Performance
   - Run 6 pins at once.
   - Pass: no stutter, fans/heat acceptable; record CPU and memory from Activity Monitor.

## Also note during the spike
- How permission prompts behave (Screen Recording, Accessibility) and what happens after granting (relaunch needed?).
- Whether apps protecting their content show black in the mirror.
- Any surprises that should change docs/REQUIREMENTS.md.

## Output
A short SPIKE-RESULTS.md in docs/: each test pass/fail, numbers, problems, and recommended requirement changes.
