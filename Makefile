# Convenience entry points; the real logic lives in scripts/.

PORT ?= 8060

# Recipes call bash explicitly: on Windows, GNU make defaults to cmd.exe and
# execs a bare `scripts/x.sh` line itself, via its `#!/usr/bin/env bash`
# shebang, which needs an `env` cmd does not have. Git for Windows' bash is
# used there (C:\Windows\system32\bash.exe is WSL); override with
# `make BASH=...` if Git lives elsewhere.
ifeq ($(OS),Windows_NT)
BASH ?= C:/Program Files/Git/bin/bash.exe
SHELL := $(BASH)
else
BASH ?= bash
endif

.PHONY: test sim smoke godot web serve clean

test:            ## unit tests (~2s)
	"$(BASH)" scripts/test.sh

sim:             ## balance sim; pass flags via ARGS="--n=500 --bot=none"
	"$(BASH)" scripts/sim.sh $(ARGS)

smoke:           ## boot + play the UI under xvfb
	"$(BASH)" scripts/ui_smoke.sh

godot:           ## download portable Godot 4.5 into ./bin (no admin needed)
	"$(BASH)" scripts/get_godot.sh

web:             ## export the web build (build/web + itch.io zip)
	"$(BASH)" scripts/export_web.sh

serve: web       ## export, then play it at http://localhost:$(PORT)
	"$(BASH)" scripts/serve_web.sh $(PORT)

clean:
	"$(BASH)" -c 'rm -rf build'

# --- Docker: the CI environment (Godot 4.5 on Linux) on any host running
# Docker. `make docker-<target>` runs `make <target>` inside the container
# with the repo bind-mounted at /work; export templates persist in a named
# volume so `docker-web` downloads them once. docker-serve is reachable at
# http://localhost:$(PORT) on the host.
IMAGE ?= sons-of-the-north-dev
export MSYS_NO_PATHCONV = 1   # Git Bash would otherwise mangle the -v paths

.PHONY: docker-image
docker-image:    ## build the dev image once (~750MB)
	docker build -t $(IMAGE) .

docker-%: docker-image  ## e.g. make docker-test / docker-sim ARGS=... / docker-serve
	docker run --rm -i -p $(PORT):$(PORT) \
		-v "$(CURDIR):/work" -v sons-of-the-north-godot:/root/.local/share/godot \
		$(IMAGE) make $* ARGS="$(ARGS)" PORT=$(PORT)
