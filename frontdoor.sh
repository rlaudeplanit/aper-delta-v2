#!/bin/bash
###################################################
# frontdoor.sh - Legacy Wrapper -> launch.sh
###################################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="$SCRIPT_DIR/launch.sh"

if [ -f "$TARGET_SCRIPT" ]; then
  chmod +x "$TARGET_SCRIPT" 2>/dev/null
  exec "$TARGET_SCRIPT" "$@"
else
  echo "ERROR: launch.sh not found in $SCRIPT_DIR"
  exit 1
fi
