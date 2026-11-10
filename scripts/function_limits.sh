#!/usr/bin/env bash
# Report the functions in src/ over the function limits (docs/decisions.md,
# D4): cyclomatic complexity 15, 60 lines, 5 parameters. Warnings only: a
# flagged function never fails the report, so the gate stays green while the
# flagged functions are fixed or accepted; a Lizard error still does. GDScript has no linter here; Lizard reads it.
set -uo pipefail
cd "$(dirname "$0")/.."
if command -v lizard >/dev/null 2>&1; then
	run=(lizard)
elif python3 -m lizard --version >/dev/null 2>&1; then
	run=(python3 -m lizard)
elif python -m lizard --version >/dev/null 2>&1; then
	run=(python -m lizard)
elif command -v uvx >/dev/null 2>&1; then
	run=(uvx lizard)
else
	echo "function limits: Lizard not found (pip install lizard, or install uv); skipped" >&2
	exit 0
fi
# Lizard exits 1 when it flags a function; anything higher is a real failure.
"${run[@]}" -l GDScript -w -C 15 -L 60 -a 5 src
rc=$?
[ "$rc" -le 1 ] || { echo "function limits: Lizard failed (exit $rc)" >&2; exit "$rc"; }
exit 0
