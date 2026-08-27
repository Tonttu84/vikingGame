#!/usr/bin/env bash
# Run the unit test suite headlessly.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/godot_bin.sh
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s tests/run_tests.gd
