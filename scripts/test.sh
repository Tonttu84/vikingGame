#!/usr/bin/env bash
# Run the unit test suite headlessly.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --import >/dev/null 2>&1 || true
godot --headless -s tests/run_tests.gd
