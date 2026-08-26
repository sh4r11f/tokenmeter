#!/usr/bin/env bash
# TokenMeter statusline hook (portable: macOS and Linux).
#
# Claude Code pipes a JSON payload (see its documented statusLine hook
# schema) to this script's stdin on every status-line render, and prints
# this script's stdout as the status line text. We extract rate_limits,
# write a snapshot to status.json for the TokenMeter UI (macOS menu bar
# app or GNOME Shell extension) to read, and pass the original status
# line through so the terminal keeps working.
#
# If SettingsInstaller wrapped an existing statusLine command, its
# original command string arrives in $TOKENMETER_WRAPPED_COMMAND and we
# run it first, feeding it the same stdin JSON.
#
# Deliberate soft-fail policy: this script must never break the user's
# status line, so capture problems are reported on stderr (visible in
# Claude Code's debug output) while stdout always gets the best status
# text we can produce.
set -uo pipefail

INPUT="$(cat)"
STATUS_DIR="$HOME/.claude/tokenmeter"
STATUS_FILE="$STATUS_DIR/status.json"

# Create our data directory owner-only on first use: it also holds
# settings.json backups, which can contain secrets (env vars, API key
# helpers). An existing directory's permissions are enforced by the
# installer instead, so we don't fight a deliberate user change on
# every render.
if [ ! -d "$STATUS_DIR" ]; then
    mkdir -p "$STATUS_DIR" && chmod 700 "$STATUS_DIR"
fi

# Run the user's original statusline command first (if we wrapped one)
# so its output can be prepended to ours. Its errors are suppressed on
# purpose: a broken wrapped command should degrade to "just TokenMeter's
# numbers," not a broken status line.
PREFIX=""
if [ -n "${TOKENMETER_WRAPPED_COMMAND:-}" ]; then
    PREFIX="$(printf '%s' "$INPUT" | eval "$TOKENMETER_WRAPPED_COMMAND" 2>/dev/null)"
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "TokenMeter: jq not found, skipping usage capture (install jq: https://jqlang.org)" >&2
    printf '%s' "$PREFIX"
    exit 0
fi

# Not valid JSON on stdin: pass through whatever the wrapped command
# produced and skip capture — never write a snapshot we can't trust.
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$PREFIX"
    exit 0
fi

NOW_EPOCH="$(date +%s)"
FIVE_HOUR="$(printf '%s' "$INPUT" | jq -c '.rate_limits.five_hour // empty')"
SEVEN_DAY="$(printf '%s' "$INPUT" | jq -c '.rate_limits.seven_day // empty')"

# rate_limits is absent for API-key (pay-per-token) usage; record that
# explicitly as null so the UI can say "no subscription data" instead of
# showing a stale or bogus number.
RATE_LIMITS_JSON="null"
if [ -n "$FIVE_HOUR" ] || [ -n "$SEVEN_DAY" ]; then
    RATE_LIMITS_JSON="$(jq -n \
        --argjson five "${FIVE_HOUR:-null}" \
        --argjson seven "${SEVEN_DAY:-null}" \
        '{five_hour: $five, seven_day: $seven}')"
fi

# Write atomically (temp file + mv) so the watching UI never reads a
# half-written file. The subshell umask makes the snapshot owner-only
# without changing the umask for anything else in this script.
TMP_FILE="$STATUS_FILE.tmp.$$"
if ( umask 077; jq -n --argjson captured "$NOW_EPOCH" --argjson rate_limits "$RATE_LIMITS_JSON" \
        '{captured_at: $captured, rate_limits: $rate_limits}' > "$TMP_FILE" ); then
    mv "$TMP_FILE" "$STATUS_FILE"
else
    rm -f "$TMP_FILE"
    echo "TokenMeter: failed to write status snapshot to $STATUS_FILE" >&2
fi

# Build the human-readable summary for the terminal status line.
# LC_ALL=C pins printf's float parsing to "." decimals, matching jq's
# output regardless of the user's locale (e.g. de_DE expects "42,3" and
# would otherwise reject "42.3").
SUFFIX=""
if [ -n "$FIVE_HOUR" ]; then
    FIVE_PCT="$(printf '%s' "$FIVE_HOUR" | jq -r '.used_percentage')"
    SUFFIX="5h: $(LC_ALL=C printf '%.0f' "$FIVE_PCT")%"
fi
if [ -n "$SEVEN_DAY" ]; then
    SEVEN_PCT="$(printf '%s' "$SEVEN_DAY" | jq -r '.used_percentage')"
    [ -n "$SUFFIX" ] && SUFFIX="$SUFFIX · "
    SUFFIX="${SUFFIX}7d: $(LC_ALL=C printf '%.0f' "$SEVEN_PCT")%"
fi

if [ -n "$PREFIX" ] && [ -n "$SUFFIX" ]; then
    printf '%s | %s' "$PREFIX" "$SUFFIX"
elif [ -n "$SUFFIX" ]; then
    printf '%s' "$SUFFIX"
else
    printf '%s' "$PREFIX"
fi
