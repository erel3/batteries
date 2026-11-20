#!/bin/bash
# Stop hook (asyncRewake): build + unit-test every SwiftPM package the session
# actually touched.
#
# Per-file swiftlint says nothing about whether the code compiles or the suite
# passes, so without this the agent ends turns on unverified work. Runs in the
# BACKGROUND — the turn ends immediately and the agent is re-woken only on
# failure.
#
# Cost when green: SwiftPM's build cache makes a re-run ~0.8s per package
# (measured: lidguard 0.83s build + ~1s test, lidguard-helper 0.79s).
# Scope: `swift build` + `swift test` only. Bundling, codesigning and
# notarization stay in `just build` / `just release`, which are never run from a
# hook.

INPUT=$(cat)

# Loop guard: never re-gate a turn that this hook itself woke up.
[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$ROOT" || exit 0
command -v swift >/dev/null 2>&1 || exit 0   # no toolchain is an env gap, not a defect

# Scope = packages THIS SESSION edited. record-touch.sh appends each one as it
# fires; deriving it from git state instead would re-test whatever an earlier
# session left dirty or unpushed, on every single turn.
STATE_DIR="$ROOT/.claude/.hookstate"
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
MARKER="$STATE_DIR/$SESSION.touched"

# Compact .paths. record-touch.sh appends one line per edit and never truncates
# (guard-bash.sh needs it to describe the whole session), so re-editing the same
# file all session leaves it majority-duplicate. Safe: the only consumer does
# set-membership, so order and multiplicity carry no meaning. The prefix filter
# retires entries written before out-of-root paths were rejected at the source.
#
# Runs BEFORE the marker check — a turn with no Swift edits still gets compacted.
PATHS="$STATE_DIR/$SESSION.paths"
if [ -s "$PATHS" ]; then
  awk -v p="$ROOT/" 'index($0, p) == 1' "$PATHS" | sort -u > "$PATHS.tmp" 2>/dev/null
  # Only replace when the content actually changes. An unconditional rewrite
  # would bump the mtime every turn, and mtime is exactly the liveness signal
  # prune-hookstate.sh reaps on — a file rewritten each turn can never age out.
  if [ -s "$PATHS.tmp" ] && ! cmp -s "$PATHS.tmp" "$PATHS"; then
    mv -f "$PATHS.tmp" "$PATHS" 2>/dev/null
  else
    rm -f "$PATHS.tmp" 2>/dev/null
  fi
fi

[ -s "$MARKER" ] || exit 0

# Normalise to repo-relative here (cwd is $ROOT) so every message below reads
# "lidguard-helper", not an absolute path.
PACKAGES=()
while IFS= read -r d; do
  d="${d#"$ROOT"/}"
  [ -n "$d" ] || continue
  [ -f "$d/Package.swift" ] || continue
  PACKAGES+=("$d")
done < <(sort -u "$MARKER")

[ ${#PACKAGES[@]} -eq 0 ] && { : > "$MARKER"; exit 0; }
# NOTE: the marker is deliberately NOT consumed yet — see the bottom of the file.
# Clearing it up front loses the failure whenever the woken turn doesn't touch a
# Swift file (agent asks a question, or the real fix was in a plist), and the
# next Stop would then pass green over red code.

FAILURES=""
FAILED=()
for d in "${PACKAGES[@]}"; do
  if ! OUT=$(cd "$d" && swift build </dev/null 2>&1); then
    FAILED+=("$d")
    FAILURES="${FAILURES}
== $d: swift build ==
$(echo "$OUT" | tail -40)"
    continue
  fi
  if ! OUT=$(cd "$d" && swift test </dev/null 2>&1); then
    FAILED+=("$d")
    FAILURES="${FAILURES}
== $d: swift test ==
$(echo "$OUT" | grep -E "error:|failed|XCTAssert|✘|Fatal error" | head -40)"
  fi
done

# Green: consume the marker and reset the re-gate counter.
if [ -z "$FAILURES" ]; then
  : > "$MARKER"
  rm -f "$STATE_DIR/$SESSION.regates"
  exit 0
fi

# Red: carry the still-broken packages forward, so a woken turn that edits no
# Swift file can't end green over red code.
#
# That carry-forward is also the loop risk: under asyncRewake an empty marker is
# what guarantees termination, so bound it. After REGATE_CAP consecutive red
# gates we clear the marker anyway and say so — the agent is told once more and
# the session stops re-waking on it.
REGATE_CAP=2
REGATE_FILE="$STATE_DIR/$SESSION.regates"
N=$(cat "$REGATE_FILE" 2>/dev/null)
case "$N" in ''|*[!0-9]*) N=0 ;; esac
N=$((N + 1))

if [ "$N" -gt "$REGATE_CAP" ]; then
  : > "$MARKER"
  rm -f "$REGATE_FILE"
  FAILURES="${FAILURES}
(Re-gated $REGATE_CAP times without going green — NOT re-checking again this
session. Verify by hand with 'just test' before you call this done.)"
else
  echo "$N" > "$REGATE_FILE"
  printf '%s\n' "${FAILED[@]}" | grep -v '^$' | sort -u > "$MARKER"
fi

{
  echo "Stop gate failed on packages changed this session:"
  echo "$FAILURES"
} >&2

exit 2
