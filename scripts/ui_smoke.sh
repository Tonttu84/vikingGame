#!/usr/bin/env bash
# Boot the battle UI under a virtual display and play a few turns for real:
# clicks, drag-and-drop, restarts. GUI input routing needs a window, so this
# runs under xvfb with software GL rather than --headless. Without xvfb
# (Windows, macOS) it opens a real window for the ~20s it takes.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/godot_bin.sh
"$GODOT" --headless --import >/dev/null 2>&1 || true
if command -v xvfb-run >/dev/null 2>&1; then
	xvfb-run -a -s "-screen 0 1280x800x24" \
		"$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x800 -s tests/ui_smoke.gd
else
	echo "xvfb-run not found; running the smoke test on the real display" >&2
	"$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x800 -s tests/ui_smoke.gd
fi
