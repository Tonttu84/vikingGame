# Convenience entry points; the real logic lives in scripts/.

PORT ?= 8060

.PHONY: test sim smoke web serve clean

test:            ## unit tests (~2s)
	scripts/test.sh

sim:             ## balance sim; pass flags via ARGS="--n=500 --bot=none"
	scripts/sim.sh $(ARGS)

smoke:           ## boot + play the UI under xvfb
	scripts/ui_smoke.sh

web:             ## export the web build (build/web + itch.io zip)
	scripts/export_web.sh

serve: web       ## export, then play it at http://localhost:$(PORT)
	scripts/serve_web.sh $(PORT)

clean:
	rm -rf build
