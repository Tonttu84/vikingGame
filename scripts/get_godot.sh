#!/usr/bin/env bash
# Download the portable Godot 4.5 binary into ./bin — no admin rights needed.
# Linux x86_64 only (school/lab machines); other platforms: download from
# godotengine.org and set GODOT=/path/to/binary instead.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -x bin/godot ]; then
	echo "bin/godot already present: $(bin/godot --version)"
	exit 0
fi

URL="https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_linux.x86_64.zip"
mkdir -p bin
echo "Downloading Godot 4.5 (portable, ~70MB) ..."
curl -sSL -o bin/godot.zip "$URL"
unzip -q -o bin/godot.zip -d bin
mv bin/Godot_v4.5-stable_linux.x86_64 bin/godot
chmod +x bin/godot
rm bin/godot.zip
echo "Installed: $(bin/godot --version) at ./bin/godot"
