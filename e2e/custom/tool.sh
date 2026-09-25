#!/usr/bin/env bash
# Prints its mode, the configuration file it was given, and its other arguments.
set -euo pipefail
[[ "$1" == --config ]] || { echo "usage: tool --config FILE ARGS..." >&2; exit 2; }
config="$(cat "$2")"
shift 2
echo "mode=${TOOL_MODE:-none} config=${config} args=$*"
