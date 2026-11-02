# Tack

**Keep your windows on top.**

Tack is a free, open-source Mac app that pins any window above everything else: a video call, your music, your notes. Manage your pins from the MacBook notch or the menu bar.

Requires macOS 26 (Tahoe) or later.

## Features

- **Pin any window** with a shortcut (⌃⌘P by default, change it in Settings) or from the notch or menu bar.
- **Use pinned windows as normal.** Click a pin and you're using the real app: type, click, scroll, drag.
- **Pins live in your notch.** Hover over the notch to see your pins, unpin them, jump to them or reorder them. On a Mac without a notch, the menu bar does the same.
- **Move, resize and snap.** Drag a pin by its top edge, and let go near a screen edge or corner to snap it into place.
- **Private by design.** No accounts, no tracking, no analytics. Nothing leaves your Mac.

## Install

1. Download **Tack.dmg** from the [Releases](../../releases) page.
2. Open it and drag **Tack** into **Applications**.
3. Open Tack from Applications or Spotlight.

### "Apple could not verify Tack"

Tack is a free side project and isn't notarised by Apple (that needs a paid developer account). So the first time you open it, macOS stops it. To allow it, once:

1. Click **Done** on the message.
2. Open **System Settings › Privacy & Security**.
3. Scroll down to the message about Tack and click **Open Anyway**, then confirm with your password or Touch ID.

After that, Tack opens normally. The source code is all here if you'd like to check it, or build it yourself.

### Permissions

Tack walks you through these when it first opens:

| Permission | Why |
| --- | --- |
| Screen Recording | To show a live copy of the windows you pin. Only pinned windows are captured, frames stay in memory and are never saved or sent anywhere. |
| Accessibility | To move, resize and bring forward the real window when you use a pin. |

## How it works

macOS doesn't let one app float another app's window, so Tack shows a live copy of the window on top of everything else, with the real window right underneath it. When you press on a pin, Tack swaps the real window in, in the same spot, and passes your click along.

Good to know:

- **Hover and scrolling start after one click.** While the copy is showing, the real window can't see your mouse. Controls that only appear on hover, like video call buttons, show up after you click.
- **Protected video shows as black.** macOS blocks every app from capturing protected video like Netflix. Click the pin to watch in the real window.
- **Lots of pins take some work.** Every pin is a live copy. Tack reminds you when 4 or more windows are pinned.
- **No Dock icon.** If you quit Tack, open it again from Applications or Spotlight. To have it start with your Mac, turn on **Open Tack at login** in Settings › General.

## Feedback

Found a bug or have an idea? [Open an issue](../../issues).

## Build it yourself

You need Xcode 26 or later.

```bash
git clone https://github.com/kelvin-weng/Tack.git
cd Tack/app
xcodebuild -project Tack.xcodeproj -scheme Tack -configuration Release -derivedDataPath build build
```

The app is at `app/build/Build/Products/Release/Tack.app`. To sign it with your own certificate, change `DEVELOPMENT_TEAM` in the project's signing settings.

Project notes (requirements, plans, build status) are in [docs/](docs).

## Licence

[MIT](LICENSE) © 2026 Kelvin Weng
