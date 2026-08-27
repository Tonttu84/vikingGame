# Resolve the Godot binary into $GODOT. Sourced by the other scripts after
# they cd to the repo root. No admin rights are ever needed: Godot is a
# portable executable, and `make godot` downloads it into ./bin.
#
# Priority: $GODOT env var > ./bin/godot > `godot` on PATH.
if [ -n "${GODOT:-}" ]; then
	if [ ! -x "$GODOT" ] && ! command -v "$GODOT" >/dev/null 2>&1; then
		echo "error: GODOT='$GODOT' is not an executable" >&2
		exit 1
	fi
elif [ -x "bin/godot" ]; then
	GODOT="$(pwd)/bin/godot"
elif command -v godot >/dev/null 2>&1; then
	GODOT=godot
else
	echo "error: Godot not found. Any of these works (no admin rights needed):" >&2
	echo "  make godot                    # downloads it into ./bin" >&2
	echo "  GODOT=/path/to/godot make ... # point at a binary you downloaded" >&2
	echo "  put 'godot' on your PATH" >&2
	exit 1
fi
