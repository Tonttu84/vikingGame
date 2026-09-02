# The CI environment (Godot 4.5 on Linux) as a dev container, for hosts where
# the native toolchain is awkward. The repo is bind-mounted at /work, so the
# image holds only the tools: `make docker-<target>` (see the Makefile).
FROM ubuntu:24.04

ARG GODOT_VERSION=4.5-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
	ca-certificates curl unzip zip make python3 \
	xvfb libgl1-mesa-dri libgl1 libx11-6 libxcursor1 libxinerama1 libxrandr2 \
	libxi6 libxext6 libasound2t64 libpulse0 libdbus-1-3 fontconfig \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -sSL -o /tmp/godot.zip \
	"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
	&& unzip -q /tmp/godot.zip -d /tmp \
	&& mv "/tmp/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot \
	&& rm /tmp/godot.zip \
	&& godot --version

# Pin the binary: a Windows host's bin/godot wrapper comes along with the
# bind mount and would otherwise win over PATH in scripts/godot_bin.sh.
ENV GODOT=/usr/local/bin/godot
# scripts/serve_web.sh binds here; 0.0.0.0 so the host can reach it via -p.
ENV BIND=0.0.0.0
WORKDIR /work
