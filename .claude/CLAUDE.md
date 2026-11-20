# OpenWolf

@../.wolf/OPENWOLF.md

This project uses OpenWolf for context management. Read and follow .wolf/OPENWOLF.md every session. Check .wolf/cerebrum.md before generating code. Check .wolf/anatomy.md before reading files.

# CLAUDE.md

## Project Overview

Batteries = native macOS app replacing AirBuddy's battery features for the owner only (never distributed). Shows the battery of every device (Mac, AirPods, BLE keyboards/mice, Sony headphones, DualSense, iPhone), alerts on per-device low/high thresholds, and has a Notification Center widget in the exact format of macOS's own Batteries widget.

**Why it exists**: AirBuddy 3 went the "superapp" way and lost the owner's trust (closed source, silent self-updates, broken on macOS 27). Owner rules: no menu bar icon (battery cost), nothing acts without the owner's control, no self-updating.

**State**: core, agent app and widget built (`just app` → `dist/Batteries.app`); owner installs with `just install`. Read `.wolf/STATUS.md` first, then `docs/RESEARCH.md`.

## Conventions (from the owner's other apps)

- Layout follows `~/Work/projects/lidguard-workspace/lidguard/` (SPM `Package.swift`, `Sources/`, `Tests/`, `Scripts/`, `justfile`, `.swiftlint.yml`, `VERSION`). Single repo, no submodules.
- A widget is a `.appex`, which SwiftPM cannot produce. Reference for building an app + appex without an Xcode project: `~/Work/projects/me/share-iina/justfile` (swiftc, hand-written Info.plists, Developer ID signing).
- Signing: `Developer ID Application: Andrey Kim (73R36N2A46)`; notarize profile `Notarize` (keychain). Local only, so notarizing is optional.
- 2-space indent. `just lint`, `just test` before calling anything done.
- `.claude/hooks/` are copied from lidguard-workspace (see that repo's `.claude/hooks/README.md` for why each exists): swiftlint + plist/JSON syntax + secrets on every edit, `swift build && swift test` gate on Stop for touched packages, `guard-bash.sh` denies `git reset --hard`, `git clean -fd`, force push, `rm -rf` on root/home/glob, `tccutil reset`.
- Never commit unless asked. Angular commit format.
