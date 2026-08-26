#!/usr/bin/env bash
# TokenMeter — Linux uninstaller.
#
# Surgically removes TokenMeter's statusLine hook from
# ~/.claude/settings.json — restoring a wrapped pre-existing command
# exactly — and removes the GNOME extension. Unlike the mac app's
# "restore latest backup" approach, this never reverts settings changes
# you made after installing; the timestamped backups stay untouched in
# ~/.claude/tokenmeter/ as a manual fallback.
#
# The data directory itself (snapshots + backups) is only deleted with
# --purge, or after an explicit interactive confirmation.
set -euo pipefail

fail() {
    echo "TokenMeter: $*" >&2
    exit 1
}

UUID="tokenmeter@sh4r11f.github.io"
TOKENMETER_DIR="$HOME/.claude/tokenmeter"
SCRIPT_PATH="$TOKENMETER_DIR/statusline.sh"
SETTINGS_FILE="$HOME/.claude/settings.json"
EXT_DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

PURGE=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h|--help)
            echo "Usage: uninstall.sh [--purge]"
            echo "  --purge  also delete ~/.claude/tokenmeter (snapshots AND settings backups)"
            exit 0
            ;;
        *) fail "unknown option: $arg" ;;
    esac
done

command -v jq >/dev/null 2>&1 || fail "jq is required (sudo apt install jq)"

# ---- 1. Remove the hook from settings.json ---------------------------

RESOLVED="$(readlink -f "$SETTINGS_FILE" 2>/dev/null || printf '%s' "$SETTINGS_FILE")"

if [ -f "$RESOLVED" ]; then
    ROOT_JSON="$(cat "$RESOLVED")"
    printf '%s' "$ROOT_JSON" | jq -e . >/dev/null 2>&1 \
        || fail "$RESOLVED isn't valid JSON — fix it manually, nothing was changed"
    CURRENT="$(printf '%s' "$ROOT_JSON" | jq -r '.statusLine.command // empty')"

    if [ -z "$CURRENT" ] || [[ "$CURRENT" != *"$SCRIPT_PATH"* ]]; then
        echo "TokenMeter hook not present in settings.json — nothing to remove."
    else
        # Safety net first: back up before touching the file, same
        # scheme as the installer (owner-only, collision-safe).
        mkdir -p "$TOKENMETER_DIR" && chmod 700 "$TOKENMETER_DIR"
        STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
        BACKUP="$TOKENMETER_DIR/settings.json.bak-$STAMP"
        [ -e "$BACKUP" ] && BACKUP="$BACKUP.$$"
        cp "$RESOLVED" "$BACKUP"
        chmod 600 "$BACKUP"

        # A wrapped install looks like:
        #   TOKENMETER_WRAPPED_COMMAND='<original, ' escaped as '\''>' <script path>
        # Peel the wrapper off and put the original command back;
        # a plain install just drops the statusLine key.
        WRAP_PREFIX="TOKENMETER_WRAPPED_COMMAND='"
        WRAP_SUFFIX="' $SCRIPT_PATH"
        if [[ "$CURRENT" == "$WRAP_PREFIX"*"$WRAP_SUFFIX" ]]; then
            MIDDLE="${CURRENT#"$WRAP_PREFIX"}"
            MIDDLE="${MIDDLE%"$WRAP_SUFFIX"}"
            # Undo the installer's quoting: every '\'' was one ' originally.
            ORIGINAL="$(printf '%s' "$MIDDLE" | sed "s/'\\\\''/'/g")"
            NEW_JSON="$(printf '%s' "$ROOT_JSON" | jq -S --arg cmd "$ORIGINAL" \
                '.statusLine = {type: "command", command: $cmd}')"
            echo "Restored your original status line command."
        else
            NEW_JSON="$(printf '%s' "$ROOT_JSON" | jq -S 'del(.statusLine)')"
            echo "Removed the TokenMeter status line hook."
        fi

        # Owner-only from the first byte (same rationale as the installer):
        # the chmod below then restores the file's original mode.
        TMP="$RESOLVED.tokenmeter-tmp.$$"
        ( umask 077; printf '%s\n' "$NEW_JSON" > "$TMP" ) || { rm -f "$TMP"; fail "couldn't write $RESOLVED"; }
        chmod --reference="$RESOLVED" "$TMP"
        mv "$TMP" "$RESOLVED"
    fi
else
    echo "No settings.json found — nothing to remove."
fi

# ---- 2. Remove the GNOME extension -----------------------------------

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable "$UUID" 2>/dev/null || true
fi
# Also clear the uuid from the gsettings list directly, covering the
# "enabled for next login but shell never loaded it" state.
if command -v gjs >/dev/null 2>&1; then
    gjs -c '
        const {Gio} = imports.gi;
        const uuid = ARGV[0];
        const settings = new Gio.Settings({schema_id: "org.gnome.shell"});
        const enabled = settings.get_strv("enabled-extensions");
        if (enabled.includes(uuid))
            settings.set_strv("enabled-extensions", enabled.filter(u => u !== uuid));
        Gio.Settings.sync();
    ' "$UUID" 2>/dev/null || true
fi
if [ -d "$EXT_DEST" ]; then
    rm -rf "$EXT_DEST"
    echo "Removed the GNOME extension."
fi

# ---- 3. Data directory (only on explicit request) --------------------

if [ -d "$TOKENMETER_DIR" ]; then
    if [ "$PURGE" = 1 ]; then
        rm -rf "$TOKENMETER_DIR"
        echo "Deleted $TOKENMETER_DIR (snapshots and settings backups)."
    elif [ -t 0 ]; then
        # Interactive: ask, defaulting to keep — the backups in there are
        # the user's safety net.
        read -r -p "Also delete $TOKENMETER_DIR (snapshots AND settings backups)? [y/N] " REPLY
        case "$REPLY" in
            [yY]*) rm -rf "$TOKENMETER_DIR"; echo "Deleted $TOKENMETER_DIR." ;;
            *) echo "Kept $TOKENMETER_DIR (delete later with: rm -rf ~/.claude/tokenmeter)" ;;
        esac
    else
        echo "Kept $TOKENMETER_DIR (re-run with --purge to delete snapshots and backups)."
    fi
fi

echo "TokenMeter uninstalled."
