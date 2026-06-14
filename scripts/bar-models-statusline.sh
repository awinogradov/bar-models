#!/usr/bin/env bash
#
# bar-models status-line hook (M4b — "Official path").
#
# Claude Code pipes its status-line JSON to this command on stdin every turn. We
# capture the official 5-hour and weekly rate-limit percentages (and their reset
# times, when present) into ~/.claude/bar-models/snapshot.json, then pass stdin
# through to any wrapped prior status-line command so the user's existing status
# line still renders. Installed and registered as `statusLine` ONLY on explicit
# opt-in from the bar-models app ("Enable live limits").
#
# Safety: the snapshot write is best-effort and fully guarded — a missing `jq`,
# a parse error, or a disk error can never break the user's status line.
set -euo pipefail

# Claude Code may invoke this with a minimal PATH; make common bins discoverable
# so `jq` resolves even when launched from a notarized .app.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

DIR="$HOME/.claude/bar-models"
SNAPSHOT="$DIR/snapshot.json"
WRAPPED="$DIR/wrapped-command"

input="$(cat)"

# Capture the official numbers. Runs in a `|| true` context, so `set -e` is
# suspended inside — nothing here can abort the script.
write_snapshot() {
    command -v jq >/dev/null 2>&1 || return 0
    printf '%s' "$input" | jq empty >/dev/null 2>&1 || return 0 # not valid JSON → leave snapshot untouched

    local five seven five_reset seven_reset model ts tmp
    five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
    seven=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
    five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
    seven_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
    model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
    ts=$(date +%s)

    mkdir -p "$DIR"
    tmp=$(mktemp "$DIR/.snapshot.XXXXXX")
    {
        printf '{'
        printf '"ts": %s' "$ts"
        if [ -n "$five" ];        then printf ', "five_hour": %s' "$five"; fi
        if [ -n "$seven" ];       then printf ', "seven_day": %s' "$seven"; fi
        if [ -n "$five_reset" ];  then printf ', "five_hour_resets_at": %s' "$five_reset"; fi
        if [ -n "$seven_reset" ]; then printf ', "seven_day_resets_at": %s' "$seven_reset"; fi
        if [ -n "$model" ];       then printf ', "model": %s' "$(printf '%s' "$model" | jq -R .)"; fi
        printf '}\n'
    } > "$tmp"
    mv -f "$tmp" "$SNAPSHOT" # atomic publish — FSEvents never sees a torn file
}
write_snapshot || true

# Pass stdin through to any wrapped prior status-line command (preserving its exit
# status); print nothing when there was no prior status line.
if [ -s "$WRAPPED" ]; then
    printf '%s' "$input" | sh -c "$(cat "$WRAPPED")"
fi
