# Tack – Requirements (v1.0)

Approved by Kelvin, 19 Oct 2026. Revised after the technical spike (docs/SPIKE-RESULTS.md), 19 Oct 2026, and MVP testing, 26–29 Oct 2026. Source of truth: the "Tack – Requirements (v1.0)" doc on claude.ai. This file is a copy for Claude Code.

## 1. Overview

Tack is a free, open-source macOS 26 utility that keeps any window floating on top, managed from the MacBook notch or the menu bar.

| Item | Decision |
| --- | --- |
| Audience | Kelvin and everyday Mac users |
| Core jobs | Keep a browser pop-up video call (e.g. Messenger) or Spotify visible over other work |
| Ambition | Free side project, showcased on kweng.studio |
| Platform | macOS 26 only (full Liquid Glass, current APIs) |
| Signature feature | Notch pin manager, like an iPhone Live Activity; menu bar equivalent always available |
| Positioning | Keep any window on top, natively, for free, with a home in your notch |

## 2. Technical approach

macOS doesn't let one app change another app's window level, so Tack mirrors windows with ScreenCaptureKit and uses swap-in-place for interaction.

Approaches considered:
- Mirror (chosen): capture the window live and show it in a floating panel.
- Accessibility re-raising (rejected): flickery and unreliable.
- Window-level injection (rejected): requires disabling SIP; can't ship.

Swap-in-place interaction:
1. The real window is kept positioned exactly underneath its pin.
2. Pressing the pin brings the real window forward in the same spot and hands it the press, so the first click, drag or text selection goes straight to the actual app.
3. Clicking elsewhere hands display back to the pin.
4. Moving or resizing the pin moves and resizes the real window to match. A pin is moved by dragging its top edge (where the title or tab bar is); a plain click there works like any other click, and letting go of a drag brings the real window forward.
5. Pinned source windows are never minimised (minimised windows can't be captured).
6. While a pin's real window is in use, other pins move below it so nothing covers it.
7. A pin never completely covers its real window with a solid rectangle (its corners stay rounded and see-through). Otherwise macOS treats the window as hidden and apps such as Chrome stop drawing video.

By default the pin catches every click. Clicks never pass through to whatever is behind it.

Known limitation: while the pin is showing, the real window doesn't see hover or scrolling, so controls that only appear on hover (e.g. video call buttons) need one click to reveal. Explained on the "How Tack works" screen.

| Permission | Why Tack needs it |
| --- | --- |
| Screen Recording | To capture the pinned window and show it on top |
| Accessibility | To move, resize and raise the real window for swap-in-place |

## 3. Functional requirements

v1.0 ships every Must and Should item.

| ID | Requirement | Priority |
| --- | --- | --- |
| F1 | Pin the frontmost window with a customisable global hotkey | Must |
| F2 | Pin a window chosen from a list in the notch or menu bar | Must |
| F3 | Support multiple pins at once | Must |
| F4 | Unpin via the same hotkey, a hover button on the pin, or the notch/menu bar | Must |
| F5 | Move and resize pins; swap-in-place on press (section 2) | Must |
| F6 | Notch pin manager and menu bar equivalent (section 4) | Must |
| F7 | Pins stay on the Space where they were created | Must |
| F8 | Permission onboarding with plain-language explanations | Must |
| F9 | Graceful handling when a source window closes or is minimised | Must |
| F10 | Launch at login | Must |
| F11 | Opacity per pin. Dropped 26 Oct: the real window sits right under its pin, so fading the pin only reveals the real window, never the desktop. | Dropped |
| F12 | Snap pins to screen corners and edges | Should |
| F13 | Hide pins from screenshots and screen sharing. Dropped 26 Oct: since macOS 15, screenshots and sharing use ScreenCaptureKit, which ignores the standard setting; no supported alternative. | Dropped |
| F14 | Setting to turn the pin border on or off (corners stay rounded either way), plus a border colour picker (default #00CEC8, with Reset) | Should |

Behaviour rules:
- The pin being actively used always rises to the top of the pin stack.
- No hard limit on pins. When 4 or more windows are pinned, the notch panel and menu bar menu show "Lots of pins can slow your Mac down." (A size-based rule was tried and dropped: it flickered and warned at just 2 large videos.)
- Pins showing a window that isn't changing should cost almost nothing (skip unchanged frames, lower the capture rate while idle).

Later (post-1.0): click-through mode; auto-pin rules; pin a cropped region; Shortcuts support; pins on all Spaces and over full-screen apps; "Smooth motion" setting (capture at 120 fps instead of 60); opacity per pin, by moving the real window off-screen while its pin is faded (untried; risks apps stopping drawing and slower swap-in).

Out of scope: Now Playing or media info in the notch.

## 4. Notch and menu bar pin manager

| State | Behaviour |
| --- | --- |
| Nothing pinned | The notch looks completely normal; hovering opens a small panel with "Pin a Window" |
| Collapsed, pins active | Tack glyph on the left of the notch, pin count on the right |
| Expanded (on hover) | Extends smoothly from the notch, stays black, keeps the notch's curves and corner angles |

Expanded panel:
- One row per pin: app icon and window title.
- Drag a row (from anywhere on it; the three-line handle on the right is the visual cue) to reorder front-to-back layers.
- Row actions: unpin and jump to window.
- Reordering also works without dragging (accessibility): ⌥⌘↑/↓ on a focused row, and Move Forward / Move Back actions for VoiceOver.

The menu bar menu mirrors the panel exactly; it is the only manager on Macs/displays without a notch.

## 5. Design language and screens

- Presence: no Dock icon (LSUIElement). Settings opens from the notch or menu bar.
- Pins: thin rounded border with a soft glow (toggle in Settings). Hover shows a floating toolbar: unpin, Tack badge.
- Style: Liquid Glass for menu, Settings and toolbar; SF Symbols; accent close to #00CEC8.
- Writing tone: short, friendly, plain English, e.g. "Tack needs to see your windows to float them. Nothing leaves your Mac."

| Area | Screens and states |
| --- | --- |
| Onboarding | Welcome · Screen Recording permission · Accessibility permission · your pin shortcut · done |
| Notch | Idle · collapsed with pins · expanded panel |
| Menu bar | Menu mirroring the notch panel |
| Pin | Normal · hover (toolbar) · active (real window swapped in) · source unavailable |
| Settings | General (hotkey, launch at login, updates) · Pins (border on/off, border colour) · How Tack works (including the hover/scroll limitation) · About |

## 6. Name and icon

- Name: Tack. Tagline: "Keep your windows on top".
- Other Mac apps called Tack exist; tagline + distinct icon set Tack apart.
- Icon (updated 29 Oct): a round, translucent glass sphere in the putty colour, pressed like blu tack: a deep, soft dent a little above and right of centre, smooth shoulders easing into the sphere, and the ball slightly squished and spread by the press. No thumbprint lines.
- Colour: putty material close to #00CEC8.
- Glyph: single-colour disc with the dent's rim crescent cut out (design/icon/tack-glyph.svg), legible at 16 pt (menu bar) and 13 pt (notch). Alternative: side view of a pressed lump (tack-glyph-alt-profile.svg).
- Production: layered in Icon Composer (light, dark, tinted, clear).
- Files: design/icon/ (flat Icon Composer layers, glyphs, reference renders, README). design/tack-icon-sketch-v2.svg is superseded.

## 7. Privacy, distribution and support

| Area | Decision |
| --- | --- |
| Distribution | Direct download, not the Mac App Store (sandbox blocks Accessibility control of other apps' windows) |
| Signing | Apple Developer Program (US$99/yr), deferred until beta |
| Source code | Open source on GitHub, MIT licence |
| Privacy | No analytics, no accounts, no network traffic except opt-in update checks |
| Transparency | Every permission explained in context, plus a "How Tack works" screen |
| Updates | Sparkle; off by default, opt-in in Settings; manual "Check for Updates…" always available |
| Support | GitHub Issues plus a feedback email |
| Accessibility | VoiceOver labels, non-drag reordering, Reduce motion respected. The notch panel opens on hover only, so VoiceOver and keyboard users manage pins from the menu bar menu, which has every action; How Tack works says so. |
| Language | English only at launch |
| Hotkey | Customisable in Settings › General; default ⌃⌘P (⌃⌥ avoided because it's VoiceOver's command key) |

## 8. Open items

- [ ] Final permission and "How Tack works" copy (onboarding should say that macOS restarts Tack after Screen Recording is granted). Drafted in the app in M5; Kelvin to review.
- [ ] Default global hotkey: decided 29 Oct, ⌃⌘P
- [ ] Marketing and kweng.studio page (parked)
- [ ] Soft warning rule: decided 26 Oct, warn at 4 or more pins (no profiling threshold needed)

Next: technical spike (done, docs/SPIKE-RESULTS.md) → MVP → beta → release.
