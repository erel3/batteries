#!/bin/bash
# PostToolUse hook: parse-check the non-Swift files a macOS bundle is built from.
# A malformed Info.plist / .entitlements / LaunchAgent plist is not caught by
# swiftlint or by `swift build` — it surfaces as a bundle that silently fails to
# launch, or as a codesign error deep inside `just build`.
# Cost: ~30ms, syntax only — no schema validation.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  */.build/*|*/.xcodebuild/*|*/dist/*) exit 0 ;;
esac

case "$FILE_PATH" in
  *.plist|*.entitlements|*.xcprivacy)
    command -v plutil >/dev/null 2>&1 || exit 0
    OUTPUT=$(plutil -lint "$FILE_PATH" </dev/null 2>&1)
    ;;
  *.json)
    command -v jq >/dev/null 2>&1 || exit 0
    OUTPUT=$(jq empty "$FILE_PATH" </dev/null 2>&1)
    ;;
  *.yml|*.yaml)
    command -v python3 >/dev/null 2>&1 || exit 0
    # `command -v python3` proves the interpreter, NOT the module. Without this
    # probe a missing PyYAML surfaces as an ImportError that blocks every .yml
    # edit — an environment gap the agent would try to pip-install its way out of.
    python3 -c 'import yaml' >/dev/null 2>&1 || exit 0
    OUTPUT=$(FILE="$FILE_PATH" python3 -c '
import os, sys, yaml
try:
    with open(os.environ["FILE"]) as fh:
        list(yaml.safe_load_all(fh))
except Exception as exc:
    print(str(exc).strip())
    sys.exit(1)
' </dev/null 2>&1)
    ;;
  *) exit 0 ;;
esac
STATUS=$?

[ $STATUS -eq 0 ] && exit 0

{
  echo "Invalid syntax in $FILE_PATH:"
  echo "$OUTPUT"
} >&2

exit 2
