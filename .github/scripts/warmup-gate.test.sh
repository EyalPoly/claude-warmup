#!/usr/bin/env bash
# Verifies the warmup gate, including across an Israel DST transition.
# Run on a GNU-date system (ubuntu-latest): .github/scripts/warmup-gate.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate="$here/warmup-gate.sh"

failures=0

# israel_local_time -> expected "should_ping,slot"
check() {
  local label=$1 israel_time=$2 want=$3
  local now got
  now=$(TZ=Asia/Jerusalem date -d "$israel_time" +%s)

  local out
  out=$(mktemp)
  GITHUB_OUTPUT="$out" WARMUP_NOW="$now" bash "$gate" >/dev/null 2>&1
  got="$(grep '^should_ping=' "$out" | cut -d= -f2),$(grep '^slot=' "$out" | cut -d= -f2-)"
  rm -f "$out"

  if [ "$got" = "$want" ]; then
    echo "ok   - $label ($israel_time) -> $got"
  else
    echo "FAIL - $label ($israel_time): want '$want', got '$got'"
    failures=$(( failures + 1 ))
  fi
}

echo "== IDT (UTC+3, summer) =="
check "one minute before first target" "2026-07-27 05:59" "false,"
check "exactly at first target"        "2026-07-27 06:00" "true,2026-07-27-06"
check "inside grace after first"       "2026-07-27 07:59" "true,2026-07-27-06"
check "just past grace"                "2026-07-27 08:01" "false,"
check "second target"                  "2026-07-27 11:10" "true,2026-07-27-11"
check "third target"                   "2026-07-27 16:00" "true,2026-07-27-16"
check "evening, all slots done"        "2026-07-27 18:30" "false,"
check "middle of the night"            "2026-07-27 02:00" "false,"

echo "== IST (UTC+2, winter) - same local times, no file edit =="
check "winter first target"            "2026-01-15 06:05" "true,2026-01-15-06"
check "winter before first target"     "2026-01-15 05:30" "false,"
check "winter third target"            "2026-01-15 16:30" "true,2026-01-15-16"

echo "== DST boundary days =="
check "day IDT ends"                   "2026-10-25 11:00" "true,2026-10-25-11"
check "day IDT starts"                 "2026-03-27 16:00" "true,2026-03-27-16"

echo "== force bypass =="
out=$(mktemp)
GITHUB_OUTPUT="$out" WARMUP_FORCE=true WARMUP_NOW=$(TZ=Asia/Jerusalem date -d "2026-07-27 02:00" +%s) \
  bash "$gate" >/dev/null 2>&1
if grep -q '^should_ping=true' "$out" && grep -q '^slot=manual-' "$out"; then
  echo "ok   - force pings outside any window"
else
  echo "FAIL - force did not bypass the gate"
  failures=$(( failures + 1 ))
fi
rm -f "$out"

echo
if [ "$failures" -eq 0 ]; then
  echo "all gate tests passed"
else
  echo "$failures gate test(s) failed"
  exit 1
fi