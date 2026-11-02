# Tack – MVP build plan

The spike passed, so we're building the real app now. Build it in a new Xcode project in app/, not in spike/. Reuse spike code where it's proven, but restructure it cleanly. Work one milestone at a time. At the end of each milestone, tell Kelvin how to test it, wait for his OK, then commit.

Requirement IDs (F1–F14) refer to docs/REQUIREMENTS.md.

## M1 – App shell
- Agent app (no Dock icon), menu bar item with placeholder glyph, Quit.
- Onboarding: welcome, Screen Recording and Accessibility permission screens with plain-language explanations, detecting when each is granted (F8).
- Settings window skeleton (General, Pins, How Tack works, About). Launch at login (F10).
- Test: fresh install walks through onboarding; permissions detected without guesswork.

## M2 – Pinning core
- Pin frontmost window via global hotkey (default ⌃⌘P, customisable) (F1). Unpin via hotkey and hover button (F4).
- Mirror with ScreenCaptureKit; swap-in-place with press handoff; move via top edge; resize syncs real window (F5).
- Multiple pins (F3); active pin's real window never covered; rounded see-through corners.
- Pins stay on their Space (F7). Graceful handling of closed or minimised sources (F9).
- Performance: skip unchanged frames, lower capture rate for idle pins.
- Test: Messenger call + Spotify + 2 static windows pinned at once; everything from spike tests 1, 2 and 2b still passes.

## M3 – Notch and menu bar manager
- Collapsed notch: glyph left, count right; normal notch when nothing is pinned.
- Expanded panel on hover: rows with app icon, title, drag handle on the right; unpin, jump to window; drag to reorder layers; keyboard reordering.
- Menu bar menu mirrors the panel; pin-from-list (F2, F6).
- Fallback for displays without a notch (menu bar only).

## M4 – Should features
- Snapping to corners and edges (F12), border toggle and colour (F14). F11 (opacity) and F13 (hide from screen sharing) dropped 26 Oct.
- Soft warning when 4 or more windows are pinned.

## M5 – Polish and testing
- Final permission and "How Tack works" copy (including the hover/scroll limitation).
- App icon and glyph (Icon Composer), accent colour.
- VoiceOver labels and keyboard navigation pass.
- Untested cases from the spike: Spotify, a live Messenger call, copy-protected video (Netflix), a Mac without a notch, separate Spaces per display.

## After the MVP (beta)
Apple Developer Program, Developer ID signing and notarisation, Sparkle (opt-in), GitHub repo with MIT licence, DMG.
