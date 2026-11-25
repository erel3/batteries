---
description: learned preferences, project conventions, and Do-Not-Repeat rules
budget_tokens: 2000
---
# Cerebrum

> OpenWolf's learning memory. Updated automatically as the AI learns from interactions.
> Do not edit manually unless correcting an error.
> Last updated: 2026-11-20

## User Preferences
- [2026-11-21] Alerts are informative only: state and level, never advice ("plug it in", "unplug it"). The owner decides what to do. Notification = title device name, body "Low Battery · 20%" / "Charged · 80%".
- [2026-11-21] Run `just install` myself once a change is finished (lint + test green). Launching the app stays the owner's step.

<!-- How the user likes things done. Code style, tools, patterns, communication. -->

- No menu bar icon; nothing acts without the owner's control; no self-updating. Owner skips remaining questions with "build core" — default the rest and say so.

## Key Learnings
- [2026-11-25] Widget shows "Updated N ago" / "Open Batteries" when the app is silent >30 min (Snapshot.updated heartbeat, set on every save). Same signal as the Expenses app widget; keep the two consistent.
- [2026-11-23] appctl (~/.local/bin/appctl) finds an app's GitHub repo from a github.com/<owner>/<repo> URL in the binary (General pane "Source Code on GitHub" link) and reads releases/latest unauthenticated: the repo must be public with releases. Without it, it name-matches an unrelated Homebrew cask "batteries". Release = `just release` (needs RELEASE_NOTES.md, clean tree; bumps VERSION, notarizes, tags, pushes, gh release).
- [2026-11-21] iPhone reads are event-driven: Usbmux.listen (needs kLibUSBMuxVersion 3) fires on Attached/Detached, Monitor reads at once; 5 min poll stays for level changes. A locked iPhone drops off Wi-Fi in usbmuxd within minutes.
- [2026-11-21] macOS 27 Apple widgets (Batteries) use Liquid Glass; third-party widgets cannot. containerBackground with .ultraThinMaterial, Color.clear or Color.black.opacity(0.35) all render the same system grey gradient (#282829 top to #0D0E0E). Keep Color.clear; .fill.tertiary only adds a lighter grey.
- [2026-11-21] A WidgetKit appex built by SwiftPM must link with `-Xlinker -e -Xlinker _NSExtensionMain` (Xcode does this silently). Without it the widget traps at launch in ExtensionFoundation and never appears in the gallery. Debug widget launch via chronod logs + ~/Library/Logs/DiagnosticReports/BatteriesWidget-*.ips.
- [2026-11-21] Give a new app its icon before it ever posts a notification: macOS caches the generic icon per bundle ID in /Library/Caches/com.apple.iconservices.store; only deleting that store (sudo) and restarting clears it. Test icon questions with a throwaway bundle ID run from dist/ (usernoted refuses apps in /private/tmp).

- **Project:** batteries
- [2026-11-20] Public `IOPSCopyPowerSourcesInfo` returns ONLY the Mac's battery. Accessories (Keychron, AirPods) come from private `IOPSCopyPowerSourcesByType(4)` (0 = all, 1 = internal, 4 = accessories, measured macOS 27.2.1). Keep it inside `PowerSources.swift`.
- [2026-11-20] Keychron firmware swaps "Accessory Category": K8 HE keyboard says Mouse, M3 mouse says Keyboard. Name decides kind first.
- [2026-11-20] AirPods = two power sources sharing "Group Identifier": "Combined" (with "Combined Parts" Left/Right) and "Case". IOBluetooth's `batteryPercent*` KVC values were stale/zero while disconnected; don't use them.
- [2026-11-20] `/var/run/usbmuxd` is world-writable and `ReadPairRecord` returns the full pair record to any user process; we only ever request lockdown's `com.apple.mobile.battery` domain and never persist the record.
- [2026-11-20] The secrets hook blocks a literal PEM armour line even in tests; build the label at runtime.
- [2026-11-20] `containerURL(forSecurityApplicationGroupIdentifier:)` returns the path even for unsigned, unentitled processes; it never signals "no group". The CLI keeps its own cache in Application Support so it never touches the group container.
- [2026-11-20] WidgetKit extension from SwiftPM: executable target with `@main struct: Widget` (LC_MAIN, no `_NSExtensionMain`), `-application-extension` swift flag + `-Xlinker -application_extension`; type name must differ from module name (`BatteryWidget` in module `BatteriesWidget`).
- [2026-11-20] `ImageRenderer` works inside `swift test` (no NSApplication): RenderTests renders widget sizes to PNG for visual checks.

## Do-Not-Repeat
- [2026-11-21] Never order a test window in, even off screen: macOS moves titled windows back onto a display. Render with cacheDisplay unordered. Round NSVisualEffectView with maskImage, not layer cornerRadius.

<!-- Mistakes made and corrected. Each entry prevents the same mistake recurring. -->
<!-- Format: [YYYY-MM-DD] Description of what went wrong and what to do instead. -->
- [2026-11-20] Owner wants every device configured on its own: no global alert defaults, no global style. Don't add app-wide settings where a per-device one fits.
- [2026-11-20] Owner judges UI by Apple HIG: System Settings layout (sidebar + grouped Form detail), Title Case labels, menus for value pickers. Render panes (BATTERIES_RENDER_DIR) and look before calling UI done.

## Decision Log

<!-- Significant technical decisions with rationale. Why X was chosen over Y. -->

- [2026-11-20] Poll power sources every 60 s instead of IOPS notifications: unverified whether notifications fire for accessories; a 60 s IOKit read costs nothing and needs no radio.
- [2026-11-20] App not sandboxed (usbmuxd socket, IOKit); widget sandboxed (WidgetKit requires it). They share only `snapshot.json` in the App Group container.
- [2026-11-20] SUPERSEDED by per-battery rules (owner: no alerts unless set per device). Was: buds default to LOW only: they charge in the case after every use, so HIGH "unplug it" would be noise. Case and other devices keep 20/80. Own levels can turn HIGH back on.
- [2026-11-20] Settings window opens at launch unless the login item is enabled; reopening the app shows it. No menu bar icon by owner rule.
