#!/usr/bin/env bash
# Tests for linux/install-hook.sh and linux/uninstall.sh.
#
# Every case runs inside a throwaway fake $HOME, so nothing here can
# touch the real ~/.claude. gnome-extensions and gjs are replaced with
# no-op stubs on PATH, so the uninstaller's extension cleanup can't
# reach the real GNOME settings (gjs would otherwise write through the
# real dconf daemon even under a fake HOME).
set -uo pipefail
cd "$(dirname "$0")/.."

FAIL=0

note_fail() {
    echo "FAIL: $*"
    FAIL=1
}

# Stub out desktop tooling; record invocations for optional assertions.
STUB_BIN="$(mktemp -d)"
cat > "$STUB_BIN/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
echo "stub gnome-extensions $*" >> "${STUB_LOG:-/dev/null}"
exit 0
EOF
cat > "$STUB_BIN/gjs" <<'EOF'
#!/usr/bin/env bash
echo "stub gjs" >> "${STUB_LOG:-/dev/null}"
exit 0
EOF
chmod 755 "$STUB_BIN/gnome-extensions" "$STUB_BIN/gjs"
export PATH="$STUB_BIN:$PATH"

# Creates a fake home with statusline.sh in place (install-hook.sh
# requires it) and prints the fake home path.
make_home() {
    local home
    home="$(mktemp -d)"
    mkdir -p "$home/.claude/tokenmeter"
    cp Resources/statusline.sh "$home/.claude/tokenmeter/statusline.sh"
    chmod 755 "$home/.claude/tokenmeter/statusline.sh"
    printf '%s' "$home"
}

perms_of() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [ "$actual" = "$expected" ]; then
        echo "ok: $label"
    else
        note_fail "$label — expected '$expected', got '$actual'"
    fi
}

echo "--- fresh install: no settings.json ---"
H="$(make_home)"
HOME="$H" bash linux/install-hook.sh > /dev/null || note_fail "fresh install exited nonzero"
SETTINGS="$H/.claude/settings.json"
assert_eq "$(jq -r '.statusLine.command' "$SETTINGS")" "$H/.claude/tokenmeter/statusline.sh" "fresh install points at statusline.sh"
assert_eq "$(jq -r '.statusLine.type' "$SETTINGS")" "command" "statusLine type is command"
assert_eq "$(perms_of "$SETTINGS")" "600" "new settings.json is owner-only"
assert_eq "$(perms_of "$H/.claude/tokenmeter")" "700" "data dir is owner-only"
ls "$H"/.claude/tokenmeter/settings.json.bak-* >/dev/null 2>&1 && note_fail "no backup expected when settings.json didn't exist"
rm -rf "$H"

echo "--- install preserves unrelated keys, creates 600 backup, keeps file perms ---"
H="$(make_home)"
printf '{"model": "sonnet", "permissions": {"defaultMode": "auto"}}' > "$H/.claude/settings.json"
chmod 644 "$H/.claude/settings.json"
HOME="$H" bash linux/install-hook.sh > /dev/null || note_fail "install exited nonzero"
SETTINGS="$H/.claude/settings.json"
assert_eq "$(jq -r '.model' "$SETTINGS")" "sonnet" "unrelated key preserved"
assert_eq "$(jq -r '.permissions.defaultMode' "$SETTINGS")" "auto" "nested unrelated key preserved"
assert_eq "$(perms_of "$SETTINGS")" "644" "pre-existing settings.json keeps its permissions"
BACKUP="$(ls "$H"/.claude/tokenmeter/settings.json.bak-* 2>/dev/null | head -1)"
if [ -n "$BACKUP" ]; then
    echo "ok: backup created"
    assert_eq "$(perms_of "$BACKUP")" "600" "backup is owner-only"
    assert_eq "$(jq -r '.model' "$BACKUP")" "sonnet" "backup holds the pre-install contents"
    jq -e '.statusLine' "$BACKUP" >/dev/null 2>&1 && note_fail "backup should predate the statusLine entry"
else
    note_fail "no backup created"
fi
rm -rf "$H"

echo "--- second install is idempotent ---"
H="$(make_home)"
printf '{"model": "sonnet"}' > "$H/.claude/settings.json"
HOME="$H" bash linux/install-hook.sh > /dev/null
OUT="$(HOME="$H" bash linux/install-hook.sh)"
echo "$OUT" | grep -q "already installed" && echo "ok: reports already installed" || note_fail "expected 'already installed', got: $OUT"
# Only the first (modifying) install backs up; the no-op re-run must not
# pile up backup files.
assert_eq "$(ls "$H"/.claude/tokenmeter/settings.json.bak-* 2>/dev/null | wc -l | tr -d ' ')" "1" "no second backup on idempotent re-run"
rm -rf "$H"

echo "--- existing statusLine gets wrapped, then unwrapped on uninstall ---"
H="$(make_home)"
# The existing command contains single quotes to prove the '\'' escaping
# round-trips exactly.
EXISTING="echo 'hello world' | cut -c1-5"
jq -n --arg cmd "$EXISTING" '{statusLine: {type: "command", command: $cmd}, model: "opus"}' > "$H/.claude/settings.json"
OUT="$(HOME="$H" bash linux/install-hook.sh)"
echo "$OUT" | grep -q "alongside" && echo "ok: reports wrapped install" || note_fail "expected wrapped message, got: $OUT"
CMD="$(jq -r '.statusLine.command' "$H/.claude/settings.json")"
case "$CMD" in
    TOKENMETER_WRAPPED_COMMAND=*"$H/.claude/tokenmeter/statusline.sh") echo "ok: wrapped command shape" ;;
    *) note_fail "unexpected wrapped command: $CMD" ;;
esac
# The wrapped command must actually run: pipe a payload through it and
# check the original command's output is prepended.
PAYLOAD='{"rate_limits": {"five_hour": {"used_percentage": 42.3, "resets_at": 1755470000}}}'
LINE="$(printf '%s' "$PAYLOAD" | HOME="$H" bash -c "$CMD")"
assert_eq "$LINE" "hello | 5h: 42%" "wrapped original output is prepended"
# Uninstall (non-interactive stdin → keeps the data dir) restores the
# original command exactly.
HOME="$H" bash linux/uninstall.sh < /dev/null > /dev/null || note_fail "uninstall exited nonzero"
assert_eq "$(jq -r '.statusLine.command' "$H/.claude/settings.json")" "$EXISTING" "original command restored exactly"
assert_eq "$(jq -r '.model' "$H/.claude/settings.json")" "opus" "unrelated key survives uninstall"
[ -d "$H/.claude/tokenmeter" ] && echo "ok: data dir kept without --purge" || note_fail "data dir should be kept without --purge"
rm -rf "$H"

echo "--- plain install is removed cleanly on uninstall ---"
H="$(make_home)"
printf '{"model": "sonnet"}' > "$H/.claude/settings.json"
HOME="$H" bash linux/install-hook.sh > /dev/null
HOME="$H" bash linux/uninstall.sh < /dev/null > /dev/null || note_fail "uninstall exited nonzero"
assert_eq "$(jq -r '.statusLine // "gone"' "$H/.claude/settings.json")" "gone" "statusLine removed"
assert_eq "$(jq -r '.model' "$H/.claude/settings.json")" "sonnet" "unrelated key preserved"
rm -rf "$H"

echo "--- uninstall --purge deletes the data dir ---"
H="$(make_home)"
HOME="$H" bash linux/install-hook.sh > /dev/null
HOME="$H" bash linux/uninstall.sh --purge < /dev/null > /dev/null || note_fail "purge uninstall exited nonzero"
[ -d "$H/.claude/tokenmeter" ] && note_fail "--purge should delete the data dir" || echo "ok: data dir purged"
rm -rf "$H"

echo "--- malformed settings.json aborts without touching anything ---"
H="$(make_home)"
printf 'not json' > "$H/.claude/settings.json"
if HOME="$H" bash linux/install-hook.sh > /dev/null 2>&1; then
    note_fail "malformed settings should exit nonzero"
else
    echo "ok: malformed settings rejected"
fi
assert_eq "$(cat "$H/.claude/settings.json")" "not json" "malformed file left untouched"
ls "$H"/.claude/tokenmeter/settings.json.bak-* >/dev/null 2>&1 && note_fail "no backup expected on abort"
rm -rf "$H"

echo "--- symlinked settings.json is resolved, not replaced ---"
H="$(make_home)"
mkdir -p "$H/real"
printf '{"model": "sonnet"}' > "$H/real/settings.json"
ln -s "$H/real/settings.json" "$H/.claude/settings.json"
HOME="$H" bash linux/install-hook.sh > /dev/null || note_fail "symlink install exited nonzero"
[ -L "$H/.claude/settings.json" ] && echo "ok: symlink still a symlink" || note_fail "symlink was replaced by a regular file"
assert_eq "$(jq -r '.statusLine.type' "$H/real/settings.json")" "command" "hook written through the symlink"
rm -rf "$H"

rm -rf "$STUB_BIN"
exit $FAIL
