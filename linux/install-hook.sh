#!/usr/bin/env bash
# TokenMeter — hook installer (Linux).
#
# The bash+jq port of TokenMeterCore's SettingsInstaller: adds (or
# repairs) the `statusLine` entry in ~/.claude/settings.json so Claude
# Code feeds its status payload through TokenMeter's statusline.sh.
#
# Semantics, kept identical to the Swift installer:
#   - Every unrelated settings.json key is preserved.
#   - A timestamped backup is written BEFORE any modification.
#   - A pre-existing statusLine command is wrapped (it keeps running,
#     TokenMeter's capture is layered on top), never overwritten.
#   - Malformed settings.json aborts loudly; the file is never touched.
#   - Re-running is idempotent ("already installed").
#
# linux/install.sh copies this script to ~/.claude/tokenmeter/ so the
# GNOME extension's "Repair hook" menu item can re-run it later, without
# the repo checkout. It requires statusline.sh to already sit next to it
# (install.sh puts it there).
set -euo pipefail

fail() {
    echo "TokenMeter: $*" >&2
    exit 1
}

TOKENMETER_DIR="$HOME/.claude/tokenmeter"
SCRIPT_PATH="$TOKENMETER_DIR/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"

command -v jq >/dev/null 2>&1 || fail "jq is required (sudo apt install jq)"

# The hook script must exist before we point settings.json at it — a
# dangling statusLine command would break every status-line render.
[ -f "$SCRIPT_PATH" ] || fail "statusline.sh not found at $SCRIPT_PATH — run linux/install.sh from the tokenmeter repo first"
chmod 755 "$SCRIPT_PATH"

# The data directory holds settings.json backups, which can contain
# secrets (env vars, API key helpers) — keep it owner-only.
chmod 700 "$TOKENMETER_DIR"

# Follow a symlinked settings.json to its real file, like the Swift
# installer's resolvingSymlinksInPath(). readlink -f also canonicalizes
# a not-yet-existing path, which is exactly what we want on first run.
RESOLVED="$(readlink -f "$SETTINGS_FILE" 2>/dev/null || printf '%s' "$SETTINGS_FILE")"

# Load current settings; a missing or empty file simply means "{}".
# Anything unparseable aborts before we change a single byte.
ROOT_JSON="{}"
FILE_EXISTED=0
if [ -f "$RESOLVED" ]; then
    FILE_EXISTED=1
    [ -r "$RESOLVED" ] || fail "couldn't read $RESOLVED"
    if [ -s "$RESOLVED" ]; then
        ROOT_JSON="$(cat "$RESOLVED")"
        printf '%s' "$ROOT_JSON" | jq -e . >/dev/null 2>&1 \
            || fail "$RESOLVED isn't valid JSON — fix it manually, nothing was changed"
    fi
fi

EXISTING_COMMAND="$(printf '%s' "$ROOT_JSON" | jq -r '.statusLine.command // empty')"

# Already pointing at our script (directly or wrapped)? Nothing to do.
if [ -n "$EXISTING_COMMAND" ] && [[ "$EXISTING_COMMAND" == *"$SCRIPT_PATH"* ]]; then
    echo "TokenMeter hook already installed."
    exit 0
fi

OUTCOME="installed"
NEW_COMMAND="$SCRIPT_PATH"
if [ -n "$EXISTING_COMMAND" ]; then
    # Wrap the user's existing command instead of replacing it: it runs
    # first via $TOKENMETER_WRAPPED_COMMAND and its output is prepended
    # (see statusline.sh). Single quotes are escaped as '\'' — the same
    # scheme the Swift installer uses — so the command round-trips
    # exactly through the shell.
    ESCAPED="$(printf '%s' "$EXISTING_COMMAND" | sed "s/'/'\\\\''/g")"
    NEW_COMMAND="TOKENMETER_WRAPPED_COMMAND='$ESCAPED' $SCRIPT_PATH"
    OUTCOME="wrapped"
fi

# Backup before modifying — only when there is a file to back up. 600:
# settings.json can contain secrets. A same-second re-run gets a $$
# suffix rather than overwriting the earlier backup.
if [ "$FILE_EXISTED" = 1 ]; then
    STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    BACKUP="$TOKENMETER_DIR/settings.json.bak-$STAMP"
    [ -e "$BACKUP" ] && BACKUP="$BACKUP.$$"
    cp "$RESOLVED" "$BACKUP"
    chmod 600 "$BACKUP"
    echo "Backed up settings to $BACKUP"
fi

# Merge: only the statusLine key changes, every other key passes through
# jq untouched. -S sorts keys, matching the Swift writer's sortedKeys.
# The subshell umask makes the temp file owner-only from its very first
# byte — settings contents never sit at default permissions, even
# momentarily, before the chmod below decides the final mode.
TMP="$RESOLVED.tokenmeter-tmp.$$"
mkdir -p "$(dirname "$RESOLVED")"
( umask 077; printf '%s' "$ROOT_JSON" | jq -S --arg cmd "$NEW_COMMAND" \
    '.statusLine = {type: "command", command: $cmd}' > "$TMP" ) \
    || { rm -f "$TMP"; fail "couldn't write $RESOLVED"; }

# Preserve the original file's permissions across the atomic replace;
# a brand-new settings.json starts out owner-only.
if [ "$FILE_EXISTED" = 1 ]; then
    chmod --reference="$RESOLVED" "$TMP"
else
    chmod 600 "$TMP"
fi
mv "$TMP" "$RESOLVED"

if [ "$OUTCOME" = "wrapped" ]; then
    echo "TokenMeter hook installed alongside your existing status line."
else
    echo "TokenMeter hook installed."
fi
