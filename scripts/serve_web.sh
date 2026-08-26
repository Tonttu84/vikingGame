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

PORT="${1:-8060}"
echo "Playtest at:  http://localhost:${PORT}  (Ctrl+C to stop)"
cd build/web
exec python3 -c "
import http.server, mimetypes
mimetypes.add_type('application/wasm', '.wasm')
server = http.server.ThreadingHTTPServer(('127.0.0.1', ${PORT}), http.server.SimpleHTTPRequestHandler)
server.serve_forever()
"
