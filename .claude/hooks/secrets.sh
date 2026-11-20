#!/bin/bash
# PostToolUse hook: block committed-shaped credentials from landing in a tracked
# file. Batteries handles one secret: the iPhone pair record Finder created (a
# full-access key to the phone). It is read from usbmuxd into memory only and must
# never be written to a source file, a fixture or a log.
#
# Only unambiguous shapes are matched. Generic `password = "..."` would fire on
# the settings UI strings and the sudoers/plist samples, and an advisory that is
# usually wrong teaches the model to discount hook output in general.
# Cost: ~10ms, one grep.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE_PATH" ] && exit 0
[ -f "$FILE_PATH" ] || exit 0

# A file no repo can see is a file no repo can leak. `check-ignore` alone is not
# enough: outside a work tree it fails the same way an un-ignored file does, so
# scratchpad and /tmp paths would be gated as if they were tracked.
DIR=$(dirname "$FILE_PATH")
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Gitignored files (local .env, dist/, .build/) can never be pushed — skip them.
git -C "$DIR" check-ignore -q "$FILE_PATH" 2>/dev/null && exit 0

# Telegram bot token is first: <8-10 digit bot id>:<35 char secret>.
PATTERNS='[0-9]{8,10}:[A-Za-z0-9_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|glpat-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|sk-(proj-)?[A-Za-z0-9_-]{32,}'

# -e is required: the private-key pattern starts with '-' and would otherwise be
# parsed as a grep option.
HITS=$(grep -nEo -e "$PATTERNS" "$FILE_PATH" 2>/dev/null | head -5)
[ -z "$HITS" ] && exit 0

{
  echo "Credential-shaped literal written to tracked file $FILE_PATH:"
  # Line number + enough of the match to identify the token class, never the
  # whole secret.
  echo "$HITS" | cut -c1-40
  echo "Keep keys in memory only (the pair record comes from usbmuxd at runtime), or gitignore the file."
} >&2

exit 2
