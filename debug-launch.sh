#!/bin/zsh
# Launch FreeStage under lldb (real debug mode) with unified-log capture.
#
# Why: `open` detaches the process, so NSLog/os_log output never reaches a
# console the user can read or copy. This script attaches lldb and streams all
# FreeStage log output to files under /tmp/freestage-debug/.
#
# Usage:
#   ./debug-launch.sh              # launch (Debug build)
#   tail -f /tmp/freestage-debug/unified.log   # watch log output
#   ./debug-launch.sh stop         # stop app + lldb + log stream

set -uo pipefail

APP="${FS_APP:-<home>/Library/Developer/Xcode/DerivedData/FreeStage-btbaqpxdnttqrcfegmnqlcqjygns/Build/Products/Debug/FreeStage.app}"
BIN="$APP/Contents/MacOS/FreeStage"
OUTDIR=/tmp/freestage-debug
UNIFIED="$OUTDIR/unified.log"
LLDBOUT="$OUTDIR/lldb.log"

mkdir -p "$OUTDIR"

stop() {
  pkill -f "FreeStage.app/Contents/MacOS/FreeStage" 2>/dev/null
  pkill -f "$OUTDIR/.*lldb" 2>/dev/null
  pkill -f "log stream.*FreeStage" 2>/dev/null
  echo "stopped."
}

if [[ "${1:-}" == "stop" ]]; then
  stop
  exit 0
fi

stop 2>/dev/null
sleep 1

# 1) Unified-log capture. NSLog and os_log both land here.
#    --level debug so Logger.debug/info definitely appear.
log stream --style compact --level debug \
  --predicate 'process == "FreeStage"' \
  > "$UNIFIED" 2>/dev/null &
echo $! > "$OUTDIR/logstream.pid"

sleep 1

# 2) Launch under lldb in batch mode. The inferior's stdout/stderr (which
#    includes NSLog) is also captured to $LLDBOUT.
lldb -b \
  -o "settings set target.disable-aslr false" \
  -o "run" \
  -- "$BIN" > "$LLDBOUT" 2>&1 &
echo $! > "$OUTDIR/lldb.pid"

echo "Launched under lldb (debug mode)."
echo "  unified log : $UNIFIED"
echo "  lldb stdout : $LLDBOUT"
echo "  watch       : tail -f $UNIFIED"
echo "  stop        : $0 stop"
