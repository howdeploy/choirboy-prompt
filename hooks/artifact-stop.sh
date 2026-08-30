#!/usr/bin/env bash
# Keep the current runtime agent working until the one-time artifact bootstrap
# has been authored and validated. The Python lifecycle never writes dossiers.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATOR="$PLUGIN_ROOT/scripts/artifact-generator.py"

if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$GENERATOR" ]; then
  echo "agent-plugin: artifact Stop hook requires python3 and $GENERATOR" >&2
  printf '{}\n'
  exit 0
fi

if ! response="$(python3 "$GENERATOR" stop)"; then
  echo "agent-plugin: artifact Stop hook failed open" >&2
  printf '{}\n'
  exit 0
fi

printf '%s\n' "$response"
