#!/bin/bash
set -eu
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PY=$(command -v python3 || command -v python)
"$PY" -I "$SCRIPT_DIR/build.py" "$@"
