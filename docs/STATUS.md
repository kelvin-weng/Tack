# Tack – build status

Shared progress log between Kelvin, Claude Code (builds the app) and the planning chat on claude.ai (owns requirements and plans). Claude Code updates this at the end of every session. The planning chat reads this file directly from the Tack folder: tell it "check STATUS.md". No pasting needed. When a requirement changes, the planning chat updates both the claude.ai doc and docs/REQUIREMENTS.md; Claude Code still checks the copy at the start of each session.

Last updated: 2 Nov 2026 (Tack 0.9 beta is public on GitHub).

## Where we are

| Milestone | State | Commit |
| --- | --- | --- |
| Technical spike | Done – see docs/SPIKE-RESULTS.md | `99f10a6` |
| M1 – App shell (onboarding, settings skeleton, launch at login) | Done, tested by Kelvin | `7c38116` |
| M2 – Pinning core | Done, tested by Kelvin | `56debf6` |
| M3 – Notch and menu bar manager | Done, tested by Kelvin (opacity removed, see below) | merge of `m3-notch-menu` |
| M4 – Should features | Done, tested by Kelvin (F11 and F13 dropped, see below) | merge of `m4-should-features` |
| M5 – Polish and testing | Done, tested by Kelvin | merge of `m5-polish` |

## Next session: pick up here

Claude Code: read CLAUDE.md, this file and docs/REQUIREMENTS.md (check whether the planning chat applied the changes below). Work on a new branch off `main` for the beta.

**The MVP is done (30 Oct).** Next, the beta (no Apple Developer Program, see below):
1. Public GitHub repo with MIT licence and a README covering download, "Open Anyway" on first launch, permissions and privacy. Kelvin approves before anything is pushed or made public.
2. Release build as a DMG on GitHub Releases, signed with Kelvin's Apple Development certificate. Check on a second Mac or user account that it opens via Open Anyway and that permissions survive an update.
3. Sparkle (opt-in, off by default) with its own update signing keys; appcast hosted on GitHub.

### Beta prep so far (branch `beta-prep`, 30 Oct, not pushed anywhere)
- Version 0.9. Release builds now use the hardened runtime and no longer carry the debugging entitlement (`get-task-allow`); permissions survived the change on Kelvin's Mac.
- `LICENSE` (MIT, Kelvin Weng) and a public `README.md` (features, install, Open Anyway steps, permissions, limitations, build from source).
- `scripts/make-dmg.sh` builds `dist/Tack-<version>.dmg` (app plus Applications shortcut, signed; `dist/` is git-ignored).
- **Open decisions for Kelvin before going public:** (1) Signing: decided 30 Oct, keep Kelvin's Apple Development certificate (he accepts that the certificate name is visible in the signature; it keeps permissions across updates). (2) Public repo contents: decided 30 Oct, publish docs/ and spike/; the "About the owner" notes moved from CLAUDE.md to git-ignored CLAUDE.local.md (Claude Code still reads it). Older commits still contain the section, so Kelvin chose (30 Oct) to **start the public repo fresh**: at publish time, make an orphan branch with one commit of the final tree (`git switch --orphan public && git commit -m "Tack 0.9 beta"`) and push only that branch. Local history stays as it is. A scan of tracked files found no other personal data. (3) GitHub: account `kelvin-weng`, new repo `Tack` (created 2 Nov). Feedback: GitHub Issues only for now, linked from the README and Settings › About (Kelvin, 2 Nov: no public email).
- Kelvin to test: DMG install on his main account (he chose this over a second account, 2 Nov). The local `dist/Tack-0.9.dmg` is marked as downloaded so the Open Anyway flow appears. The old /Applications/Tack.app is in the Trash. Not covered by this test: a Mac that has never had Tack or Kelvin's certificate.
- DMG test on Kelvin's main account (2 Nov): everything worked, with three fixes. (a) The signed DMG was itself blocked, needing a second Open Anyway; it's now unsigned (the app inside stays signed) and opened without a block when marked as downloaded. (b) White text on the teal buttons was hard to read: new `ProminentButtonStyle` (accent-tinted glass, black text). (c) Tack was missing from the Screen Recording list after a permissions reset, because the "already asked" flag skipped asking macOS; it now always asks. Kelvin re-checked (b) and (c) on 2 Nov: both OK.
- `gh` is installed and signed in as `kelvin-weng`.
- **GitHub repo:** github.com/kelvin-weng/Tack. Its `main` comes from the local `public` branch, which started from one fresh commit and is authored with GitHub's no-reply address.
- **Never push `main` or `beta-prep` to GitHub:** their history has the old personal notes and an address Kelvin doesn't want public. To publish changes, add a commit to `public` from the current tree with the no-reply author (`git commit-tree "HEAD^{tree}" -p public`, then move `public` to it and `git push origin public:main`).
- **Sparkle 2.10.1 added (2 Nov), tested by Kelvin:** a real update from 0.9 to a test 0.9.1 worked: the prompt came to the front, Tack relaunched without Open Anyway or new permission prompts. Off by default (`SUEnableAutomaticChecks` false, no request on launch). Settings › General has the toggle and Check for Updates…, also in the menu bar menu. Feed: `releases/latest/download/appcast.xml`, so every release must be a normal one, not a prerelease. Test feeds: `defaults write studio.kweng.Tack SUFeedURL <url>`, then `defaults delete` it.
- **Update signing key:** private half in Kelvin's login Keychain, public half in `app/Tack-Info.plist`. Kelvin to back it up. If it's lost, existing users can't verify new updates.
- **Releasing:** raise MARKETING_VERSION and CURRENT_PROJECT_VERSION, run `scripts/make-release.sh`, upload everything in `dist/v<version>/` to a normal (non-prerelease) GitHub Release tagged `v<version>`. Builds are universal (Apple and Intel).
- **Public since 2 Nov:** github.com/kelvin-weng/Tack and release v0.9. Checked without a login: repo, Issues, appcast feed, release notes and DMG all load, and the downloaded DMG is identical to the local one. Still to do: Kelvin's download-and-install test from the browser. Intel is untested (no Intel Mac).

## What M5 contains (tested by Kelvin, 26–30 Oct)
- Default pin shortcut ⌃⌘P (⌃⌥P clashed with VoiceOver); customising it in Settings › General works.
- Untested spike cases, all checked: Spotify OK (keeps updating); Messenger call OK; Mac without a notch OK (lid closed and reopened); separate Spaces per display OK (pins stay on their Space); Netflix black (DRM, by design; the Guide says so).
- Crash fixed: reading a capture frame whose memory wasn't mapped while displays reconfigured (lid close). Unreadable frames are now shown without fingerprinting.
- App icon (`app/Tack/AppIcon.icon`, Icon Composer, from design/icon layers) in Finder, About and the welcome step. Glyph: the crescent disc (`TackGlyph`) in menu bar, notch and pin toolbar.
- Pin corners use the window's exact corner shape: one BGRA snapshot per pin is cut into a small 9-slice mask of the window's four real corners; the border follows the measured radius; 12 pt minimum stays. (Fixed black corners on Finder.)
- Settings: opens in front from the menu bar; window title is the tab name; "How Tack Works" tab renamed Guide; tighter Guide spacing, new "Opening Tack again" and protected-video lines.
- Copy, VoiceOver labels, Reduce motion (from 26 Oct, see below).
- `scripts/install.sh` installs the Release build as /Applications/Tack.app, which is the copy Kelvin runs.

### M5 first part (tested by Kelvin on 26 Oct in the Release build)
- Customisable pin shortcut (F1 Must; it wasn't in any milestone plan): Settings › General and a new onboarding step "Your pin shortcut" (welcome → Screen Recording → Accessibility → shortcut → done). Needs ⌘, ⌥ or ⌃; Escape cancels; Reset; warns if another app already uses it; the menu shows the current shortcut. Saved in UserDefaults key `hotkey`.
- Final onboarding and How Tack Works copy, including the Screen Recording "Quit & Reopen" note (closes that REQUIREMENTS open item once the planning chat agrees).
- Accessibility: VoiceOver labels for pins ("Pinned copy of …") and minimised rows, decorative images hidden, headings marked, Reduce motion respected (notch, onboarding, snapping). VoiceOver tested OK by Kelvin.
- Timing in the Release build: press-to-real-window median 91 ms (22–129 ms, 20 presses), about the same as debug. The spike's ~55 ms skipped the readiness checks that fixed the swallowed first click. Kelvin finds it fine; no change planned.

### What M4 contains
- Snapping (F12): when a drag of a pin ends within 24 pt of a screen edge or corner, the window slides (0.15 s) to sit 10 pt inside the usable screen area. The real app owns the drag, so the snap happens on release. Tested OK by Kelvin on both displays.
- Border (F14): thin accent-coloured edge with a soft inner glow; corners stay see-through. Settings › Pins › "Show a border around pins" (on by default). Tested OK.
- Border colour (new, Kelvin's request): Settings › Pins › Border colour, with Reset to Tack's teal.
- Warning: "Lots of pins can slow your Mac down." in the notch panel and menu bar menu when 4 or more windows are pinned.
- Hide from screen sharing (F13): built, didn't work, removed (see below).

## What M3 contains (for the planning chat)
- Notch panel (REQUIREMENTS section 4): glyph left and count right when pins exist; normal notch when nothing is pinned. Hover expands it: one row per pin (app icon, title, unpin, drag handle). Clicking a row jumps to the window. "Pin a Window" at the bottom lists windows to pin (F2).
- Reordering front-to-back layers: drag a row (whole row, ☰ as the cue); keyboard ⌥⌘↑/↓ on a focused row; VoiceOver "Move Forward / Move Back" actions.
- Menu bar menu mirrors the panel (F6) and is the only manager without a notch; Tack rebuilds the notch whenever screens change.
- Decisions Kelvin approved on 19 Oct: (A) with nothing pinned the notch looks normal, but hovering still opens a small panel with "Pin a Window" (needed for F2); (B) a basic per-pin opacity control was built, then removed on 26 Oct (see below); (C) the whole row can be dragged, ☰ is the visual cue.

## Notes collected for later milestones
- M5: the cursor doesn't change to a resize arrow over a pin's edge before pressing (a background app can't set the cursor). Resizing itself works.
- M5 untested cases: Spotify; a live Messenger call in the real app (the same logic passed in the spike); copy-protected video (Netflix); a Mac without a notch; separate Spaces per display.
- Notch rows: when a window's title equals its app name, only one is shown (done in M3).
- Accessibility limit: the notch panel opens on hover only, so VoiceOver and keyboard users manage pins from the menu bar menu (which has every action). Mention in How Tack Works if the planning chat agrees.

## Requirement changes waiting for the planning chat
**Settings tab "How Tack Works" renamed "Guide" (30 Oct, Kelvin's feedback: the long label made the tab button wider than the others).** Please update REQUIREMENTS section 5 (Settings row). The page itself is still titled "How Tack works" and now also explains how to reopen Tack after quitting.

**Glyph chosen (30 Oct): the crescent disc (design/icon/tack-glyph.svg).** Please update REQUIREMENTS section 6: drop the alternative.

**Known limitation (30 Oct): protected video (Netflix) is black in a pin.** macOS blanks DRM video in every screen capture; Tack can't work around it. Mentioned in the Guide. Worth a line in REQUIREMENTS (behaviour rules or a limitations note).

**Support: GitHub Issues only for now (Kelvin, 2 Nov: no public email).** Please update REQUIREMENTS section 7 (Support). The app and README link to Issues only.

**No Apple Developer Program, decided by Kelvin on 29 Oct.** Tack is published as a download on GitHub Releases, not notarised. Effect for users: on first open macOS says it can't check Tack for malware; they allow it once in System Settings › Privacy & Security › Open Anyway (the README must explain this). Claude Code keeps signing with Kelvin's free Apple Development certificate rather than ad-hoc, so Screen Recording and Accessibility permissions survive updates (to verify on a second Mac or user account). Sparkle still works (it uses its own update keys, not Apple's). Please update REQUIREMENTS section 7 (Signing), MVP-PLAN "After the MVP" and SETUP.md.

**Applied by the planning chat on 29 Oct to both the claude.ai doc and docs/REQUIREMENTS.md (and MVP-PLAN.md). Uncommitted: Claude Code, please review the diff and commit.** Icon brief: delivered by the planning chat on 29 Oct into design/icon/ (see its README; it supersedes the brief below, and REQUIREMENTS section 6 is updated). Claude Code: build the Icon Composer file and replace pin.fill with tack-glyph.svg.
**Drop F11 (opacity per pin), decided by Kelvin on 26 Oct.** Why: the real window sits directly under its pin (that's how swap-in-place works), so fading the pin only shows the real window, never the desktop. macOS has no way to make another app's window see-through. Moving the real window off-screen while a pin is faded was considered but not tried (risks: apps stop drawing, slower swap-in, multi-display edge cases); it could come back as a post-1.0 idea. Please update both the claude.ai doc and docs/REQUIREMENTS.md:
- Section 3: remove F11 (or move to Later).
- Section 4: row actions are unpin and jump to window (no opacity).
- Section 5: pin hover toolbar is unpin and Tack badge (no opacity); Settings › Pins has no default opacity.
- MVP-PLAN M3/M4: remove opacity.
The app no longer has any opacity control (notch, menu bar, Settings).

**Drop F13 (hide pins from screenshots and screen sharing), decided by Kelvin on 26 Oct.** Built with the standard macOS setting (`NSWindow.sharingType = .none`); Kelvin's test showed the pins still appear. Since macOS 15, screenshots and screen sharing use ScreenCaptureKit, which ignores that setting, and there's no supported alternative. Remove F13 from section 3 and "hide from screen sharing" from Settings › Pins in section 5.

**Change the soft warning rule, decided by Kelvin on 26 Oct.** Section 3 currently says the warning is based on the size of moving pins, not the number. New rule: show "Lots of pins can slow your Mac down." whenever 4 or more windows are pinned; 3 or fewer, no warning. Why: the size-based version flickered on and off (it crossed its threshold whenever a video paused or a pin was clicked into), and with large videos it warned at just 2 pins. M5 profiling no longer needs to set a threshold.

**Add: border colour (Kelvin's request, 26 Oct).** Settings › Pins gets a colour picker for the pin border (default Tack's accent #00CEC8, with Reset). Add to F14 / section 5.

**Default hotkey: decided by Kelvin on 29 Oct: ⌃⌘P.** Why not ⌃⌥P: ⌃⌥ is VoiceOver's command key, so it does nothing while VoiceOver is on. Close the open item in section 8 and set the default in section 7.

**Copy open item:** the final onboarding and How Tack Works text is in the app (M5). The planning chat can review it there or ask Claude Code for the text. How Tack Works now covers: pinning and unpinning, live copies, clicking a pin, hover and scrolling, moving/snapping/resizing, layer order, the 4-pin warning, privacy.

## Practical notes
- **Kelvin runs the installed copy:** `scripts/install.sh` builds Release, replaces /Applications/Tack.app and opens it. Use it at the end of every step so Kelvin always tests /Applications/Tack.app (he opens it from Spotlight/Applications).
- Build: `cd app && xcodebuild -project Tack.xcodeproj -scheme Tack -configuration Debug -derivedDataPath build build`. App: `app/build/Build/Products/Debug/Tack.app`. Same with `-configuration Release` for `app/build/Build/Products/Release/Tack.app` (the one Kelvin last ran; permissions carry over between the two).
- To show onboarding again: `defaults write studio.kweng.Tack onboarding.completed -bool NO`, then relaunch. Add `defaults delete studio.kweng.Tack onboarding.shortcutSeen` to see the shortcut step.
- Signing: free Apple Development certificate (team W5Y8WBXP97), so macOS keeps Tack's permissions across rebuilds.
- Default pin hotkey: ⌃⌘P (customisable in Settings › General).
- "Open Tack at login": Kelvin was asked on 30 Oct to switch it off and on again in /Applications/Tack.app so it stops pointing at the debug build.
- spike/ is reference only.
