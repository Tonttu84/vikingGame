#!/usr/bin/env bash
# Download the portable Godot 4.5 binary into ./bin — no admin rights needed.
# Linux x86_64, Windows x86_64 (Git Bash) and macOS. Anything else: download
# from godotengine.org and set GODOT=/path/to/binary instead.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="4.5-stable"
BASE="https://github.com/godotengine/godot/releases/download/${VERSION}"

if [ -x bin/godot ] && bin/godot --version >/dev/null 2>&1; then
	echo "bin/godot already present: $(bin/godot --version)"
	exit 0
fi

case "$(uname -s)" in
Linux) asset="Godot_v${VERSION}_linux.x86_64" ;;
MINGW*|MSYS*|CYGWIN*) asset="Godot_v${VERSION}_win64.exe" ;;
Darwin) asset="Godot_v${VERSION}_macos.universal" ;;
*)
	echo "error: unsupported platform '$(uname -s)'. Download Godot ${VERSION}" >&2
	echo "from godotengine.org and set GODOT=/path/to/binary instead." >&2
	exit 1
	;;
esac

rm -f bin/godot
mkdir -p bin
echo "Downloading Godot ${VERSION} (${asset}, portable, ~70MB) ..."
curl -sSL -o bin/godot.zip "${BASE}/${asset}.zip"
unzip -q -o bin/godot.zip -d bin
rm bin/godot.zip

# bin/godot is what scripts/godot_bin.sh looks for. On Linux it is the binary
# itself; on Windows and macOS it is a wrapper, because the Windows
# *_console.exe launcher (which keeps stdout on the terminal) finds the GUI
# exe by name, and the macOS build is an .app bundle.
case "$asset" in
*linux*)
	mv "bin/${asset}" bin/godot
	;;
*win64*)
	printf '#!/usr/bin/env bash\nexec "$(dirname "$0")/Godot_v%s_win64_console.exe" "$@"\n' "${VERSION}" > bin/godot
	;;
*macos*)
	printf '#!/usr/bin/env bash\nexec "$(dirname "$0")/Godot.app/Contents/MacOS/Godot" "$@"\n' > bin/godot
	;;
esac
chmod +x bin/godot
echo "Installed: $(bin/godot --version) at ./bin/godot"
