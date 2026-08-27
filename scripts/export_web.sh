#!/usr/bin/env bash
# Export the game to web (HTML5) and package it as an itch.io-ready zip.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/godot_bin.sh

GODOT_VERSION="4.5.stable"
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}"
TEMPLATE_URL="https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz"

NEEDED_TEMPLATES=(
	"web_nothreads_release.zip"
	"web_nothreads_debug.zip"
)

need_download=false
for f in "${NEEDED_TEMPLATES[@]}"; do
	if [ ! -f "${TEMPLATE_DIR}/${f}" ]; then
		need_download=true
	fi
done

if [ "${need_download}" = true ]; then
	echo "Web export templates missing, downloading ${TEMPLATE_URL} ..."
	TMP_DIR="$(mktemp -d)"
	trap 'rm -rf "${TMP_DIR}"' EXIT
	TPZ_PATH="${TMP_DIR}/export_templates.tpz"
	curl -sSL -o "${TPZ_PATH}" "${TEMPLATE_URL}"

	mkdir -p "${TEMPLATE_DIR}"
	# The .tpz is a zip whose entries live under "templates/"; extract only
	# the web_* files and strip that prefix.
	unzip -o -j "${TPZ_PATH}" "templates/web_*" -d "${TEMPLATE_DIR}"

	rm -f "${TPZ_PATH}"
	trap - EXIT
	rm -rf "${TMP_DIR}"

	for f in "${NEEDED_TEMPLATES[@]}"; do
		if [ ! -f "${TEMPLATE_DIR}/${f}" ]; then
			echo "error: expected template ${f} not found in ${TEMPLATE_DIR} after extraction" >&2
			exit 1
		fi
	done
else
	echo "Web export templates already present in ${TEMPLATE_DIR}, skipping download."
fi

"$GODOT" --headless --import >/dev/null 2>&1 || true

rm -rf build/web
mkdir -p build/web

"$GODOT" --headless --export-release "Web" build/web/index.html

if [ ! -f build/web/index.html ] || [ ! -f build/web/index.wasm ]; then
	echo "error: web export did not produce index.html/index.wasm in build/web" >&2
	exit 1
fi

ZIP_PATH="build/sons-of-the-north-web.zip"
rm -f "${ZIP_PATH}"
( cd build/web && zip -qr "../../${ZIP_PATH}" . )

echo "Web build zip: ${ZIP_PATH} ($(du -h "${ZIP_PATH}" | cut -f1))"
