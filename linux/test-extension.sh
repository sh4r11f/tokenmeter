#!/usr/bin/env bash
# Validation for the GNOME Shell extension that doesn't need a running
# shell: lib.js unit tests under gjs, gschema compilation, metadata
# sanity, and a syntax lint of the shell-dependent JS files.
set -uo pipefail
cd "$(dirname "$0")/.."

UUID="tokenmeter@sh4r11f.github.io"
EXT="linux/gnome-extension/$UUID"
FAIL=0

note_fail() {
    echo "FAIL: $*"
    FAIL=1
}

command -v gjs >/dev/null 2>&1 || { echo "SKIP: gjs not installed"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

echo "--- lib.js unit tests ---"
gjs -m linux/tests/test-lib.js || note_fail "lib.js unit tests failed"

echo "--- metadata.json sanity ---"
jq -e . "$EXT/metadata.json" >/dev/null || note_fail "metadata.json isn't valid JSON"
[ "$(jq -r '.uuid' "$EXT/metadata.json")" = "$UUID" ] \
    && echo "ok: uuid matches directory name" \
    || note_fail "metadata uuid doesn't match directory name"
SCHEMA_ID="$(jq -r '."settings-schema"' "$EXT/metadata.json")"
grep -q "id=\"$SCHEMA_ID\"" "$EXT/schemas/"*.gschema.xml \
    && echo "ok: settings-schema matches gschema id" \
    || note_fail "settings-schema doesn't match the gschema id"

echo "--- gschema compiles ---"
if command -v glib-compile-schemas >/dev/null 2>&1; then
    TMP="$(mktemp -d)"
    cp "$EXT/schemas/"*.gschema.xml "$TMP/"
    if glib-compile-schemas --strict "$TMP" 2>&1; then
        echo "ok: schema compiles strictly"
    else
        note_fail "gschema failed strict compilation"
    fi
    rm -rf "$TMP"
else
    echo "SKIP: glib-compile-schemas not installed"
fi

# extension.js and prefs.js import shell-private modules that only exist
# inside a running GNOME Shell, so executing them here must fail — but a
# resolve/import failure is expected, while a SyntaxError means the file
# itself is broken. That distinction makes this a usable syntax lint.
echo "--- JS syntax lint (via gjs module loader) ---"
for f in "$EXT/extension.js" "$EXT/prefs.js"; do
    ERR="$(gjs -m "$f" 2>&1)" && { echo "ok: $f"; continue; }
    if printf '%s' "$ERR" | grep -qi "SyntaxError"; then
        note_fail "$f has a syntax error: $ERR"
    else
        echo "ok: $f (parses; import of shell modules unavailable outside the shell, as expected)"
    fi
done

exit $FAIL
