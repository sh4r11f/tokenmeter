#!/usr/bin/env bash
# TokenMeter statusline hook.
#
# Claude Code pipes a JSON payload (see its documented statusLine hook
# schema) to this script's stdin on every status-line render, and prints
# this script's stdout as the status line text. We extract rate_limits,
# write a snapshot to status.json for TokenMeter.app to read, and pass
# the original status line through so the terminal keeps working.
#
# If SettingsInstaller wrapped an existing statusLine command, its
# original command string arrives in $TOKENMETER_WRAPPED_COMMAND and we
# run it first, feeding it the same stdin JSON.
set -uo pipefail

INPUT="$(cat)"
STATUS_DIR="$HOME/.claude/tokenmeter"
STATUS_FILE="$STATUS_DIR/status.json"
mkdir -p "$STATUS_DIR"

PREFIX=""
if [ -n "${TOKENMETER_WRAPPED_COMMAND:-}" ]; then
    PREFIX="$(printf '%s' "$INPUT" | eval "$TOKENMETER_WRAPPED_COMMAND" 2>/dev/null)"
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "TokenMeter: jq not found, skipping usage capture (brew install jq)" >&2
    printf '%s' "$PREFIX"
    exit 0
fi

if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$PREFIX"
    exit 0
fi

NOW_EPOCH="$(date +%s)"
FIVE_HOUR="$(printf '%s' "$INPUT" | jq -c '.rate_limits.five_hour // empty')"
SEVEN_DAY="$(printf '%s' "$INPUT" | jq -c '.rate_limits.seven_day // empty')"

RATE_LIMITS_JSON="null"
if [ -n "$FIVE_HOUR" ] || [ -n "$SEVEN_DAY" ]; then
    RATE_LIMITS_JSON="$(jq -n \
        --argjson five "${FIVE_HOUR:-null}" \
        --argjson seven "${SEVEN_DAY:-null}" \
        '{five_hour: $five, seven_day: $seven}')"
fi

TMP_FILE="$STATUS_FILE.tmp.$$"
jq -n --argjson captured "$NOW_EPOCH" --argjson rate_limits "$RATE_LIMITS_JSON" \
    '{captured_at: $captured, rate_limits: $rate_limits}' > "$TMP_FILE" \
    && mv "$TMP_FILE" "$STATUS_FILE"

SUFFIX=""
if [ -n "$FIVE_HOUR" ]; then
    FIVE_PCT="$(printf '%s' "$FIVE_HOUR" | jq -r '.used_percentage')"
    SUFFIX="5h: $(printf '%.0f' "$FIVE_PCT")%"
fi
if [ -n "$SEVEN_DAY" ]; then
    SEVEN_PCT="$(printf '%s' "$SEVEN_DAY" | jq -r '.used_percentage')"
    [ -n "$SUFFIX" ] && SUFFIX="$SUFFIX \xc2\xb7 "
    SUFFIX="${SUFFIX}7d: $(printf '%.0f' "$SEVEN_PCT")%"
fi

if [ -n "$PREFIX" ] && [ -n "$SUFFIX" ]; then
    printf '%s | %s' "$PREFIX" "$SUFFIX"
elif [ -n "$SUFFIX" ]; then
    printf '%s' "$SUFFIX"
else
    printf '%s' "$PREFIX"
fi
