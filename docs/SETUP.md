# Setup checklist (one-off, ~1 hour mostly downloading)

1. Update macOS to 26 if you haven't (System Settings > General > Software Update).
2. Install Xcode 26 from the Mac App Store (large download, ~10+ GB). Open it once and let it install components.
3. Install the command line tools: open Terminal and run `xcode-select --install` (skip if it says already installed).
4. Install Claude Code: follow the official install guide at https://docs.claude.com/en/docs/claude-code/overview, then run `claude` in Terminal and sign in.
5. Install git if prompted (it comes with the command line tools).
6. Optional: create a free GitHub account if you don't have one (needed later for open-sourcing and updates).

## Starting the spike
1. In Terminal: `cd ~/Desktop/Tack`
2. Run `claude`
3. Say: "Read CLAUDE.md and docs/SPIKE.md, then build the spike step by step."

Not needed yet: Apple Developer account (US$99/yr). Deferred until beta.
