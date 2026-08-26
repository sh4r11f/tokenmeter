#!/usr/bin/env bash
# Exercises Resources/statusline.sh against fixture payloads, in an
# isolated fake $HOME, and asserts on the resulting status.json.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT="Resources/statusline.sh"
FAIL=0

assert_field() {
    local file="$1" jq_expr="$2" expected="$3" label="$4"
    local actual
    actual="$(jq -r "$jq_expr" "$file")"
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: $label — expected '$expected', got '$actual'"
        FAIL=1
    else
        echo "ok: $label"
    fi
}

run_case() {
    local fixture="$1"
    local fake_home
    fake_home="$(mktemp -d)"
    HOME="$fake_home" bash "$SCRIPT" < "$fixture" > "$fake_home/stdout.txt"
    echo "$fake_home"
}

# Portable permission read (GNU stat on Linux, BSD stat on macOS).
perms_of() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

echo "--- full payload ---"
home="$(run_case scripts/fixtures/full-payload.json)"
status_file="$home/.claude/tokenmeter/status.json"
assert_field "$status_file" '.rate_limits.five_hour.used_percentage' "42.3" "five_hour used_percentage"
assert_field "$status_file" '.rate_limits.seven_day.used_percentage' "18.1" "seven_day used_percentage"
grep -q "5h: 42% · 7d: 18%" "$home/stdout.txt" && echo "ok: stdout shows both windows with · separator" || { echo "FAIL: stdout separator wrong: $(cat "$home/stdout.txt")"; FAIL=1; }
# The snapshot dir also stores settings backups — both must be owner-only.
[ "$(perms_of "$home/.claude/tokenmeter")" = "700" ] && echo "ok: data dir is 700" || { echo "FAIL: data dir perms $(perms_of "$home/.claude/tokenmeter")"; FAIL=1; }
[ "$(perms_of "$status_file")" = "600" ] && echo "ok: status.json is 600" || { echo "FAIL: status.json perms $(perms_of "$status_file")"; FAIL=1; }
rm -rf "$home"

echo "--- no rate limits (non-subscriber) ---"
home="$(run_case scripts/fixtures/no-rate-limits.json)"
status_file="$home/.claude/tokenmeter/status.json"
assert_field "$status_file" '.rate_limits' "null" "rate_limits is null"
rm -rf "$home"

echo "--- five-hour only ---"
home="$(run_case scripts/fixtures/five-hour-only.json)"
status_file="$home/.claude/tokenmeter/status.json"
assert_field "$status_file" '.rate_limits.seven_day' "null" "seven_day absent"
rm -rf "$home"

echo "--- wrapped command ---"
home="$(mktemp -d)"
HOME="$home" TOKENMETER_WRAPPED_COMMAND='echo -n "orig"' bash "$SCRIPT" < scripts/fixtures/full-payload.json > "$home/stdout.txt"
grep -q "orig | 5h: 42%" "$home/stdout.txt" && echo "ok: wrapped command output preserved" || { echo "FAIL: wrapped output wrong: $(cat "$home/stdout.txt")"; FAIL=1; }
rm -rf "$home"

exit $FAIL
