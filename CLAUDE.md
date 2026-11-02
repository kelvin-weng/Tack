# Tack – project rules for Claude Code

Tack is a macOS 26 menu-bar/notch utility that pins any window on top. Full requirements: docs/REQUIREMENTS.md. Read it before planning any work. Do not add features that aren't in it; propose them instead.

## Stack
- Swift 6, SwiftUI with AppKit where needed (NSPanel, NSWindow levels, NSStatusItem).
- ScreenCaptureKit for window mirroring. Accessibility API (AXUIElement) for moving/raising source windows.
- macOS 26 deployment target only. Use Liquid Glass and SF Symbols.
- No third-party dependencies except Sparkle (later, for updates). Ask before adding any other package.
- App runs as an agent app (LSUIElement = YES): no Dock icon.
- Not sandboxed; distributed directly, not via the App Store.

## Privacy rules (non-negotiable)
- No analytics, telemetry, crash reporters or accounts.
- No network calls at all, except Sparkle update checks when the user has opted in.
- Captured frames stay in memory only; never written to disk.

## Working style
- Work in small, testable steps. After each step, tell Kelvin how to run it and what he should see.
- Build from the command line with xcodebuild where possible, and fix build errors yourself before handing over.
- Keep code organised by feature: Pinning/, Capture/, Notch/, MenuBar/, Onboarding/, Settings/.
- Comment only where the "why" isn't obvious.
- Commit to git after each working step with a clear message.

## Current phase
MVP build. See docs/MVP-PLAN.md and work one milestone at a time. The real app lives in app/. spike/ is reference only: reuse proven ideas, don't build on it directly. Spike findings are in docs/SPIKE-RESULTS.md.

## Progress log
docs/STATUS.md says where the build is and what to do next. Read it at the start of every session and update it at the end.

## Hand-off rule
Requirements and plans are owned by Kelvin's planning chat on claude.ai. If something you find should change docs/REQUIREMENTS.md, propose the change and give Kelvin a short summary to paste back there, as you did after the spike.
