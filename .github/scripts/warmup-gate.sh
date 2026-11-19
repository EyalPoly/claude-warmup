#!/usr/bin/env bash
# Decides whether the calling workflow run should send a warmup ping.
#
# GitHub dispatches scheduled runs late and by a varying amount, so the cron
# time tells us nothing about when this is actually executing. This gate is
# what makes the ping land on time: the workflow polls frequently and only the
# first run to land at or after a target time proceeds.
#
# Requires GNU date (parses "@epoch" and honours TZ for both input and output),
# which is what ubuntu-latest runners provide.
#
# Env:
#   WARMUP_NOW    override "now" as a unix timestamp (tests only)
#   WARMUP_FORCE  "true" bypasses the time gate entirely (manual runs)
set -euo pipefail

: "${GITHUB_OUTPUT:=/dev/stdout}"

# Israel local times the 5-hour usage windows should be anchored at. Evaluated
# in Asia/Jerusalem, so IDT/IST transitions are handled without an edit.
TARGETS=(07:00 12:00 17:00)

# A run landing more than this past a target is too far off to be a useful
# anchor, so it stands down instead of shifting the window somewhere wrong.
GRACE=7200

now=${WARMUP_NOW:-$(date +%s)}

if [ "${WARMUP_FORCE:-false}" = "true" ]; then
  echo "force=true - bypassing time gate"
  {
    echo "should_ping=true"
    echo "slot=manual-$(date -u -d "@$now" +%Y%m%dT%H%M%SZ)"
  } >> "$GITHUB_OUTPUT"
  exit 0
fi

# Derived from $now rather than read separately, so a run executing across
# local midnight cannot pair one day's date with the next day's clock.
today=$(TZ=Asia/Jerusalem date -d "@$now" +%F)

should_ping=false
slot=""
for target_time in "${TARGETS[@]}"; do
  target=$(TZ=Asia/Jerusalem date -d "$today $target_time" +%s)
  delta=$(( now - target ))
  if [ "$delta" -ge 0 ] && [ "$delta" -le "$GRACE" ]; then
    should_ping=true
    slot="${today}-${target_time%%:*}"
    echo "in window for ${target_time} Israel time (${delta}s past target)"
  fi
done

echo "now: $(TZ=Asia/Jerusalem date -d "@$now" '+%F %T %Z')"
if [ "$should_ping" != true ]; then
  echo "no target within ${GRACE}s grace - standing down"
fi

{
  echo "should_ping=$should_ping"
  echo "slot=$slot"
} >> "$GITHUB_OUTPUT"