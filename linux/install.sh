#!/usr/bin/env bash
# TokenMeter — Linux installer.
#
# Two independent halves (see docs/superpowers/specs/2026-08-26-linux-support.md):
#   1. The statusLine hook: copies statusline.sh + the hook installer +
#      the uninstaller into ~/.claude/tokenmeter/ and merges the hook
#      into ~/.claude/settings.json (backing it up first). This works on
#      ANY Linux desktop — even without GNOME you still get usage
#      percentages in the terminal status line.
#   2. The GNOME Shell extension (the top-bar UI). Installed to the
#      user's extensions directory and enabled; on Wayland a brand-new
#      extension only loads after logging out and back in, which this
#      script detects and says out loud.
#
# Everything is per-user ($HOME only): no sudo, no network access.
set -euo pipefail

fail() {
    echo "TokenMeter: $*" >&2
    exit 1
}

# Resolve the repo root from this script's location so the installer
# works from any working directory.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UUID="tokenmeter@sh4r11f.github.io"
TOKENMETER_DIR="$HOME/.claude/tokenmeter"
EXT_SRC="$REPO_ROOT/linux/gnome-extension/$UUID"
EXT_DEST="$HOME/.local/share/gnome-shell/extensions/$UUID"

SKIP_EXTENSION=0
for arg in "$@"; do
    case "$arg" in
        --no-extension) SKIP_EXTENSION=1 ;;
        -h|--help)
            echo "Usage: linux/install.sh [--no-extension]"
            echo "  --no-extension  install only the statusLine hook (no GNOME top-bar UI)"
            exit 0
            ;;
        *) fail "unknown option: $arg" ;;
    esac
done

command -v jq >/dev/null 2>&1 || fail "jq is required (sudo apt install jq)"

# ---- 1. The hook -----------------------------------------------------

# Owner-only data directory: it will hold settings.json backups, which
# can contain secrets.
mkdir -p "$TOKENMETER_DIR"
chmod 700 "$TOKENMETER_DIR"

# Install the hook script plus self-contained copies of the (un)installer
# so "Repair hook" and uninstalling keep working after the repo is gone.
install -m 755 "$REPO_ROOT/Resources/statusline.sh" "$TOKENMETER_DIR/statusline.sh"
install -m 755 "$REPO_ROOT/linux/install-hook.sh" "$TOKENMETER_DIR/install-hook.sh"
install -m 755 "$REPO_ROOT/linux/uninstall.sh" "$TOKENMETER_DIR/uninstall.sh"

# Run the hook installer from its installed location — the exact path
# the extension's "Repair hook" uses — so installation already proves
# the repair path works.
bash "$TOKENMETER_DIR/install-hook.sh"

# ---- 2. The GNOME Shell extension ------------------------------------

if [ "$SKIP_EXTENSION" = 1 ]; then
    echo "Skipping GNOME extension (--no-extension)."
    exit 0
fi
if ! command -v gnome-shell >/dev/null 2>&1; then
    echo "GNOME Shell not found — skipping the top-bar extension." >&2
    echo "The hook is installed; your terminal status line will still show usage." >&2
    exit 0
fi
command -v glib-compile-schemas >/dev/null 2>&1 \
    || fail "glib-compile-schemas not found (sudo apt install libglib2.0-bin)"

# Fresh copy of the extension (an upgrade replaces the old version).
rm -rf "$EXT_DEST"
mkdir -p "$EXT_DEST"
cp -r "$EXT_SRC/." "$EXT_DEST/"

# getSettings() needs the bundled schema compiled inside the extension.
glib-compile-schemas "$EXT_DEST/schemas/"

# Enabling: gnome-extensions(1) only knows extensions the running shell
# has scanned, which for a brand-new install happens at login. If it
# refuses, write the uuid into the enabled-extensions gsettings list
# directly (that is all "enable" does) so the extension starts
# automatically after the next login.
NEEDS_RELOGIN=0
if ! gnome-extensions enable "$UUID" 2>/dev/null; then
    NEEDS_RELOGIN=1
    gjs -c '
        const {Gio} = imports.gi;
        const uuid = ARGV[0];
        const settings = new Gio.Settings({schema_id: "org.gnome.shell"});
        const enabled = settings.get_strv("enabled-extensions");
        if (!enabled.includes(uuid)) {
            enabled.push(uuid);
            settings.set_strv("enabled-extensions", enabled);
        }
        const disabled = settings.get_strv("disabled-extensions");
        if (disabled.includes(uuid))
            settings.set_strv("disabled-extensions", disabled.filter(u => u !== uuid));
        Gio.Settings.sync();
    ' "$UUID" || fail "couldn't enable the extension — run: gnome-extensions enable $UUID"
fi

echo ""
echo "TokenMeter installed."
if [ "$NEEDS_RELOGIN" = 1 ]; then
    echo "  → Log out and back in to load the top-bar indicator"
    echo "    (Wayland only loads new extensions at login; it is already"
    echo "    marked enabled and will appear automatically)."
fi
echo "  → Then send a message in any Claude Code session; the top bar"
echo "    shows real percentages within a few seconds."
