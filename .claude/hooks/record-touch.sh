#!/bin/bash
# PostToolUse hook: record every edited path, plus the SwiftPM package that owns
# it, into a per-session list.
#
# Language-agnostic on purpose. Scoping the Stop gate off swiftlint.sh instead
# would miss a package where only Package.swift, Resources/ or an .entitlements
# file changed — exactly the edits most likely to break `swift build`.
#
# Consumers: stop-gate.sh (.touched), guard-bash.sh (.paths).
# Cost: ~5ms, one walk + two appends.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0

# Build products are generated; an edit under them is not a source change.
case "$FILE_PATH" in
  */.build/*|*/.xcodebuild/*|*/dist/*|*/.swiftpm/*) exit 0 ;;
esac

DIR=$(cd "$(dirname "$FILE_PATH")" 2>/dev/null && pwd) || exit 0
within_root() {
  case "$1" in "$CLAUDE_PROJECT_DIR"|"$CLAUDE_PROJECT_DIR"/*) return 0 ;; *) return 1 ;; esac
}

# Reject out-of-root paths BEFORE the .paths append, not after. The only consumer
# of .paths is guard-bash.sh, which prefix-matches "$ROOT/$submodule/", so a
# scratchpad or /tmp write can never match — it just pads the file forever.
within_root "$DIR" || exit 0

STATE_DIR="$CLAUDE_PROJECT_DIR/.claude/.hookstate"
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

echo "$FILE_PATH" >> "$STATE_DIR/$SESSION.paths" 2>/dev/null

# Walk up to the owning package. lidguard/ and lidguard-helper/ each carry their
# own Package.swift; lidguard-page/ is static HTML and has none, so it drops out
# of the Stop gate here rather than needing a special case there.
#
# Bounded at the workspace root: walking to / would let a stray Package.swift in
# $HOME enrol the whole home directory as a package for the Stop gate to build.
while [ "$DIR" != "/" ] && within_root "$DIR" && [ ! -f "$DIR/Package.swift" ]; do
  DIR=$(dirname "$DIR")
done
[ -f "$DIR/Package.swift" ] || exit 0
within_root "$DIR" || exit 0

echo "$DIR" >> "$STATE_DIR/$SESSION.touched" 2>/dev/null

exit 0
