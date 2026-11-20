# Batteries: owner-only macOS app. SwiftPM builds the binaries; `just app` wraps them into
# dist/Batteries.app with the widget extension inside (no Xcode project, recipe after me/share-iina).

sign_id := env("CODESIGN_ID", "Developer ID Application: Andrey Kim (73R36N2A46)")
app := "dist/Batteries.app"
appex := app + "/Contents/PlugIns/BatteriesWidget.appex"

# Build the core library, the app and widget binaries, and the `batteries` CLI (debug)
build:
  swift build

# Read every device once and print it (`just run --json`, `just run --no-phone`)
run *args: build
  .build/debug/batteries {{args}}

# Build and sign dist/Batteries.app with the widget inside. Does not install or launch anything.
app:
  #!/usr/bin/env bash
  set -euo pipefail
  swift build -c release
  bin=$(swift build -c release --show-bin-path)
  rm -rf "{{app}}"
  mkdir -p "{{app}}/Contents/MacOS" "{{appex}}/Contents/MacOS"
  cp "$bin/BatteriesApp" "{{app}}/Contents/MacOS/Batteries"
  cp "$bin/BatteriesWidget" "{{appex}}/Contents/MacOS/BatteriesWidget"
  cp App/Info.plist "{{app}}/Contents/Info.plist"
  # Assets.car (CFBundleIconName, what notifications on newer macOS read) plus AppIcon.icns for older readers
  mkdir -p "{{app}}/Contents/Resources"
  xcrun actool App/Assets.xcassets --compile "{{app}}/Contents/Resources" --platform macosx \
    --minimum-deployment-target 15.0 --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
  cp Widget/Info.plist "{{appex}}/Contents/Info.plist"
  version=$(cat VERSION)
  build=$(date +%y%m%d%H%M)
  for plist in "{{app}}/Contents/Info.plist" "{{appex}}/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "$version" "$plist"
    plutil -replace CFBundleVersion -string "$build" "$plist"
  done
  # Inside out: the extension first, then the app that seals it.
  codesign --force --timestamp=none -o runtime --entitlements Widget/Widget.entitlements --sign "{{sign_id}}" "{{appex}}"
  codesign --force --timestamp=none -o runtime --entitlements App/Batteries.entitlements --sign "{{sign_id}}" "{{app}}"
  codesign --verify --deep --strict "{{app}}"
  echo "Built {{app}} v$version"

# Owner only: quits a running copy, replaces /Applications/Batteries.app and registers its widget.
# Launching it stays a separate step: `open /Applications/Batteries.app`.
install: app
  pkill -x Batteries || true
  # a widget process from the old build keeps running and reports the old version; WidgetKit then
  # rejects every snapshot ("Bundle version did not match"). macOS relaunches it from the new build.
  pkill -x BatteriesWidget || true
  rm -rf /Applications/Batteries.app
  ditto "{{app}}" /Applications/Batteries.app
  # an app never opened is unknown to LaunchServices, and the widget gallery then ignores its extension
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R /Applications/Batteries.app
  pluginkit -a /Applications/Batteries.app/Contents/PlugIns/BatteriesWidget.appex

# Redraw the app icon set (Scripts/generate_icon.swift); `just icon preview.png` also writes a 1024 px PNG
icon *preview:
  swift Scripts/generate_icon.swift {{preview}}

test:
  swift test

lint:
  swiftlint --strict

clean:
  rm -rf .build dist
