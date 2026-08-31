#!/usr/bin/env bash
# Kimi blocks Stop only when a command hook exits 2 and writes the reason to
# stderr. Claude's {decision:block} stdout protocol is not accepted by Kimi.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$PLUGIN_ROOT/scripts/artifact-generator.py"

if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$GENERATOR" ]; then
  echo "agent-plugin: Kimi artifact Stop hook unavailable; failing open" >&2
  exit 0
fi

set +e
python3 "$GENERATOR" stop-kimi
status=$?
set -e
case "$status" in
  0) exit 0 ;;
  2) exit 2 ;;
  *)
    echo "agent-plugin: Kimi artifact Stop hook failed open" >&2
    exit 0
    ;;
esac
