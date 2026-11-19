#!/bin/bash
# Launch smoke test — start the built app and fail if it does not stay up.
# Usage: ./scripts/smoke-launch.sh [app-bundle] [seconds]
#        defaults: .build/AIBattery.app (run build-app.sh first), 20 seconds
#
# Why: codesign and the unit tests both pass on a bundle that dies at launch. Two real ways:
#   - dyld cannot load Sparkle.framework (the bundle was assembled wrong);
#   - Swift 6 language mode: a main-actor callback the system invokes off the main thread
#     traps with "Incorrect actor executor assumption".
#
# Meant for CI, where there are no accounts and no Keychain items. On a machine that has the
# app installed, this build reads the same accounts and raises a Keychain prompt — it is a
# different ad-hoc signature. Don't answer Deny: that signs the account out.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="${1:-.build/AIBattery.app}"
UPTIME="${2:-20}"
BIN="$APP/Contents/MacOS/AIBattery"

if [ ! -x "$BIN" ]; then
  echo "✗ $BIN not found — run ./scripts/build-app.sh first"
  exit 1
fi

LOG=$(mktemp)
# The app's own log while it runs: StatusItemCheck writes one line, 10 s after launch,
# saying whether the menu bar item reached the screen. Printed at the end; a "looks
# hidden" line becomes a CI warning, not a failure.
APPLOG=$(mktemp)
log stream --level info --style compact \
  --predicate 'subsystem == "com.KyleNesium.AIBattery" AND category == "general"' >"$APPLOG" 2>&1 &
LOGPID=$!
disown "$LOGPID" # no "Terminated" job notice when the trap stops it
trap 'kill "$LOGPID" 2>/dev/null; rm -f "$LOG" "$APPLOG"' EXIT
sleep 1 # let the stream attach before the app starts

# Run the binary itself, not `open`: the script then owns the PID, the exit status and stderr,
# which is where both dyld and the Swift runtime print why they stopped.
"$BIN" >"$LOG" 2>&1 &
PID=$!

for ((elapsed = 1; elapsed <= UPTIME; elapsed++)); do
  sleep 1
  if ! kill -0 "$PID" 2>/dev/null; then
    wait "$PID" && STATUS=0 || STATUS=$?
    if [ "$STATUS" -gt 128 ]; then
      WHY="killed by signal $((STATUS - 128))"
    else
      WHY="exit status $STATUS"
    fi
    echo "✗ $(basename "$APP") exited after ~${elapsed}s ($WHY)"
    echo "── last output"
    tail -n 40 "$LOG"
    exit 1
  fi
done

kill -TERM "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
echo "✓ $(basename "$APP") stayed up for ${UPTIME}s on macOS $(sw_vers -productVersion)"

MENU_BAR=$(grep -m1 'Menu bar item' "$APPLOG" | sed 's/.*\(Menu bar item\)/\1/' || true)
if [ -z "$MENU_BAR" ]; then
  echo "  menu bar: no line in the app's log (the uptime may be shorter than the 10 s check)"
elif echo "$MENU_BAR" | grep -q 'looks hidden'; then
  echo "::warning title=Menu bar item::$MENU_BAR"
  echo "⚠ $MENU_BAR"
else
  echo "  $MENU_BAR"
fi
