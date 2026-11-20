#!/bin/bash
# SessionStart hook: drop per-session hook state left behind by dead sessions.
#
# `<session>.paths` is the reason this exists: guard-bash.sh reads it and never
# truncates it (by design — it must describe the whole session, not the last
# turn), so it grows all session and one accumulates per session forever.
#
# The hazard this has to avoid is deleting state out from under a session that
# is still alive. mtime is the liveness proxy: record-touch.sh appends on every
# edit, so an actively-working session's files are always fresh. What mtime does
# NOT cover is a session left idle for weeks and then resumed — hence the 30-day
# window rather than a tight one, and hence the rule below.
#
# THE RULE: a non-empty `<session>.touched` is an unconsumed build failure.
# stop-gate.sh truncates it on green and writes the still-failing packages back
# on red, so non-empty means "some session ended red and nobody has fixed it".
# Deleting that on age would silently discard the failure the gate exists to
# surface, so it is kept regardless of age — it costs one short line on disk.
# Only EMPTY .touched files (definitionally consumed) are eligible.
#
# Cost: one find, once per session.

[ -n "${CLAUDE_PROJECT_DIR:-}" ] || exit 0
STATE_DIR="$CLAUDE_PROJECT_DIR/.claude/.hookstate"
[ -d "$STATE_DIR" ] || exit 0

AGE=30

# .paths and .regates: age alone. Losing a .regates only resets the re-gate
# counter, and losing a .paths only costs the submodule-commit advisory for a
# session that has been silent for a month.
find "$STATE_DIR" -maxdepth 1 -type f \
  \( -name '*.paths' -o -name '*.regates' \) \
  -mtime +$AGE -delete 2>/dev/null

# .touched: age AND empty.
find "$STATE_DIR" -maxdepth 1 -type f -name '*.touched' \
  -mtime +$AGE -empty -delete 2>/dev/null

exit 0
