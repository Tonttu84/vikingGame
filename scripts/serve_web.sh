#!/usr/bin/env bash
# Serve an already-exported web build (build/web) on localhost.
# Usage: scripts/serve_web.sh [port]   (default 8060; run `make serve` to
# export and serve in one step). The build is single-threaded, so plain
# static hosting is enough — no COOP/COEP headers needed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f build/web/index.html ]; then
	echo "error: no web build found — run scripts/export_web.sh (or 'make web') first" >&2
	exit 1
fi

PYTHON="$(command -v python3 || command -v python)" || {
	echo "error: python 3 not found (needed for the local web server)" >&2
	exit 1
}

PORT="${1:-8060}"
BIND="${BIND:-127.0.0.1}"   # the Dockerfile sets 0.0.0.0 so -p can reach it
echo "Playtest at:  http://localhost:${PORT}  (Ctrl+C to stop)"
cd build/web
exec "$PYTHON" -c "
import http.server, mimetypes
mimetypes.add_type('application/wasm', '.wasm')
server = http.server.ThreadingHTTPServer(('${BIND}', ${PORT}), http.server.SimpleHTTPRequestHandler)
server.serve_forever()
"
