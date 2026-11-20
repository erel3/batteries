#!/bin/bash
# PreToolUse hook: block irreversible shell commands the agent should never run
# unprompted in this repo.
# Cost: ~5ms, pure string matching.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

deny() {
  echo "BLOCKED by .claude/hooks/guard-bash.sh: $1" >&2
  echo "Ask the user before running this." >&2
  exit 2
}

# Read-only commands routinely QUOTE these patterns (grepping the justfile for
# `purge`, say), so search/print tools get a fast path. Safe ONLY for a SIMPLE
# command: `cat justfile && git reset --hard` is prefixed by a read-only tool but
# is not read-only. Anything with a separator falls through to the denies below,
# which are written with [^|;&]* so they match per-segment — and which grep
# evaluates line by line, so a multi-line command is already checked per line.
#
# A NEWLINE IS A SEPARATOR. Leaving it out of this class is the whole bypass:
# multi-line is the normal shape for agent-written bash (heredocs,
# `set -euo pipefail` preambles, loops), a `cat`/`echo` opening line is common,
# and the fast path would then wave the entire script through on line 1.
NL=$'\n'
case "$CMD" in
  *[\;\&\|\`]*|*'$('*|*"$NL"*) ;;   # compound / substituted / multi-line — no fast path
  *)
    case "$CMD" in
      grep\ *|rg\ *|ag\ *|ack\ *|echo\ *|cat\ *|jq\ *|less\ *|head\ *|tail\ *|rtk\ grep*) exit 0 ;;
    esac
    ;;
esac

# ── Git: history rewrites and working-tree nukes ──

echo "$CMD" | grep -Eq '\bgit\b[^|;&]*\bpush\b[^|;&]*(--force\b|[[:space:]]-f\b)' \
  && ! echo "$CMD" | grep -q -- '--force-with-lease' \
  && deny "force-push. Use --force-with-lease, or ask first."

echo "$CMD" | grep -Eq '\bgit\b[^|;&]*\breset\b[^|;&]*--hard\b' \
  && deny "'git reset --hard' discards uncommitted work."

echo "$CMD" | grep -Eq '\bgit\b[^|;&]*\bclean\b[^|;&]*-[a-zA-Z]*[fd]' \
  && deny "'git clean -fd' deletes untracked files (incl. gitignored local config)."

echo "$CMD" | grep -Eq '\brm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-{0,2}[a-zA-Z]*r[a-zA-Z]*f' \
  && echo "$CMD" | grep -Eq 'rm[^|;&]*[[:space:]](/|~|\$HOME|\*)' \
  && deny "'rm -rf' targeting a root/home/glob path."

# ── macOS state this app depends on and cannot restore itself ──
#
# A TCC reset costs manual work in System Settings to undo (Bluetooth,
# Notifications). A deny, not a warning: the damage lands outside the repo where
# no git operation can recover it.

echo "$CMD" | grep -Eq '\btccutil[^|;&]*\breset\b' \
  && deny "'tccutil reset' revokes Bluetooth / Notifications grants. Each must be re-granted by hand in System Settings, and the app is non-functional until then."

exit 0
