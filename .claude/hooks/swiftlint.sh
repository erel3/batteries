#!/bin/bash
# PostToolUse hook: swiftlint --strict the Swift file that was just edited.
# `just lint` runs the same thing over the whole tree, so catching a violation
# here saves an edit -> lint -> fix round-trip.
# Cost: ~0.2-0.4s for one file.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[[ "$FILE_PATH" != *.swift ]] && exit 0
[ -f "$FILE_PATH" ] || exit 0

# Generated build products. The previous `!= */Sources/*` filter also let Tests/
# and every Package.swift through unlinted, which is precisely where a violation
# survives until a full lint run. Everything else is delegated to .swiftlint.yml
# (see the --force-exclude handling below) so there is one exclusion list, not two.
case "$FILE_PATH" in
  */.build/*|*/.xcodebuild/*|*/dist/*|*/.swiftpm/*) exit 0 ;;
esac

# A missing toolchain is an environment gap, not a code defect. Without these
# guards an uninstalled swiftlint exits 127, which this hook turns into exit 2
# and BLOCKS the edit with "swiftlint: command not found".
command -v swiftlint >/dev/null 2>&1 || exit 0
command -v xcrun >/dev/null 2>&1 || exit 0

# Run from the directory owning .swiftlint.yml, with a path relative to it.
# Both halves are load-bearing: `excluded:` entries are resolved against the
# config's own directory, and swiftlint applies them to an explicitly-passed
# path ONLY under --force-exclude AND only when it resolved the config from cwd.
# Invoked from the workspace root instead, lidguard/'s `excluded: Scripts` is
# silently ignored and the hook blocks on a file the project deliberately exempts.
DIR=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd) || exit 0
BASE=$(basename "$FILE_PATH")

# Stop the walk at the workspace root. Ascending all the way to / means a stray
# .swiftlint.yml in $HOME silently changes how every file in this repo is linted.
within_root() {
  [ -z "${CLAUDE_PROJECT_DIR:-}" ] && return 0
  case "$1" in "$CLAUDE_PROJECT_DIR"|"$CLAUDE_PROJECT_DIR"/*) return 0 ;; *) return 1 ;; esac
}

CFG_DIR="$DIR"
while [ "$CFG_DIR" != "/" ] && within_root "$CFG_DIR" && [ ! -f "$CFG_DIR/.swiftlint.yml" ]; do
  CFG_DIR=$(dirname "$CFG_DIR")
done
# within_root must be re-tested here: the loop exits when it walks OUT of the
# root, leaving CFG_DIR pointing at that out-of-root directory, and a bare -f
# check would then happily adopt the config it was supposed to refuse.
if within_root "$CFG_DIR" && [ -f "$CFG_DIR/.swiftlint.yml" ]; then
  # Strip the prefix WITHOUT a trailing slash, then the separator separately.
  # `${DIR#"$CFG_DIR"/}` no-ops when DIR == CFG_DIR (the value has no trailing
  # slash for the pattern to match), which yields an absolute REL for any file
  # sitting directly in the config directory — e.g. lidguard/Package.swift.
  # That silently voids the relative-path invariant --force-exclude depends on.
  REL="${DIR#"$CFG_DIR"}"
  REL="${REL#/}"
  REL="${REL:+$REL/}$BASE"
  RUN_DIR="$CFG_DIR"
else
  REL="$BASE"          # no config anywhere above — SwiftLint defaults apply
  RUN_DIR="$DIR"
fi

# swiftlint loads SourceKit out of the active toolchain; without this it fails
# to launch when the default toolchain is not Xcode's.
TOOLCHAIN_DIR=$(dirname "$(dirname "$(xcrun --find swiftc 2>/dev/null)")")

# </dev/null so swiftlint can't inherit leftover hook stdin.
OUTPUT=$(cd "$RUN_DIR" && DYLD_FRAMEWORK_PATH="$TOOLCHAIN_DIR/lib" \
  swiftlint lint --quiet --strict --force-exclude "$REL" </dev/null 2>&1)
STATUS=$?

[ $STATUS -eq 0 ] && exit 0

# exit 1 + this message means swiftlint found nothing to lint. The file's
# existence was checked above, so the only remaining cause is an `excluded:`
# entry in .swiftlint.yml — a deliberate exemption, not a violation.
case "$OUTPUT" in
  *"No lintable files found"*) exit 0 ;;
esac

{
  echo "swiftlint --strict failed on $FILE_PATH ('just lint' will reject this):"
  echo "$OUTPUT"
} >&2

exit 2
