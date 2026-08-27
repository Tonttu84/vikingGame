#!/usr/bin/env bash
# Run the balance simulation harness. Extra args are passed through, e.g.:
#   scripts/sim.sh --n=1000 --bot=none --seed=7 --verbose
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/godot_bin.sh
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless -s src/sim/simulate.gd -- "$@"
