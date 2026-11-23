# Batteries: owner-only macOS app. SwiftPM builds the binaries; `just app` wraps them into
# dist/Batteries.app with the widget extension inside (no Xcode project, recipe after me/share-iina).

sign_id := env("CODESIGN_ID", "Developer ID Application: Andrey Kim (73R36N2A46)")
notarize_profile := env("NOTARIZE_PROFILE", "Notarize")
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
  # Local builds skip Apple's timestamp server; notarization (`just release`) needs it.
  ts="--timestamp=none"; [ "${RELEASE:-0}" = 1 ] && ts="--timestamp"
  codesign --force "$ts" -o runtime --entitlements Widget/Widget.entitlements --sign "{{sign_id}}" "{{appex}}"
  codesign --force "$ts" -o runtime --entitlements App/Batteries.entitlements --sign "{{sign_id}}" "{{app}}"
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

# Release, as LidGuard does: bump VERSION (BUMP=patch|minor|major), build with a secure timestamp,
# notarize and staple, commit, tag, push, publish a GitHub release with the zip. Needs RELEASE_NOTES.md.
# appctl reads github.com/Erel3/batteries/releases/latest to tell whether the installed copy is current.
release:
  #!/usr/bin/env bash
  set -euo pipefail
  test -f RELEASE_NOTES.md || { echo "Error: RELEASE_NOTES.md is required. Write release notes first."; exit 1; }
  test -z "$(git status --porcelain -- . ':!RELEASE_NOTES.md')" || { echo "Error: commit your changes first."; exit 1; }
  IFS=. read -r major minor patch < VERSION
  case "${BUMP:-patch}" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    *) version="$major.$minor.$((patch + 1))" ;;
  esac
  echo "$version" > VERSION
  RELEASE=1 just app
  ditto -c -k --keepParent "{{app}}" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --keychain-profile "{{notarize_profile}}" --wait
  xcrun stapler staple "{{app}}"
  rm -f dist/notarize.zip
  zip="dist/Batteries-$version.zip"
  ditto -c -k --keepParent "{{app}}" "$zip"
  git add VERSION
  git commit -m "chore: bump version to $version"
  git tag "v$version"
  git push origin main --tags
  gh release create "v$version" "$zip" --title "v$version" --notes-file RELEASE_NOTES.md
  rm -f RELEASE_NOTES.md
  echo "Released v$version"

test:
  swift test

lint:
  swiftlint --strict

clean:
  rm -rf .build dist
