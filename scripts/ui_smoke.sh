#!/usr/bin/env bash
# Boot the battle UI under a virtual display and play a few turns for real:
# clicks, drag-and-drop, restarts. GUI input routing needs a window, so this
# runs under xvfb with software GL rather than --headless.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/godot_bin.sh
"$GODOT" --headless --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 1280x720x24" \
	"$GODOT" --rendering-driver opengl3 --resolution 1280x720 -s tests/ui_smoke.gd
