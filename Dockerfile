# syntax=docker/dockerfile:1
# Minimal image for running `codex app-server` as a long-lived service.
# The Codex CLI is a self-contained binary shipped through npm; node exists
# only to run its launcher shim. lts-slim: every codex release triggers a
# rebuild (see .github/workflows/docker-image.yml), which also refreshes the
# base image.
FROM node:lts-slim

# CI passes the exact version resolved from npm so image tags and installed
# version can never drift apart.
ARG CODEX_VERSION=latest

# ca-certificates: the codex binary validates TLS against the system trust
# store, which node:slim does not ship (node itself uses bundled roots) -
# without it every outbound codex call fails, including login and model
# requests.
# git: codex expects a git checkout for workspace operations; harmless for
# pure chat consumers.
# bubblewrap: codex's Linux command sandbox; without the OS package it warns
# and uses a bundled copy. (Whether bwrap can actually confine inside Docker
# depends on the runtime's userns/seccomp settings - chat-style consumers
# that never run commands don't care.)
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git bubblewrap \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

# The node base image owns UID 1000 as "node"; replace it so the runtime user
# is meaningfully named and matches the yuzuyu pre-chowned-mount convention.
# Pre-create ~/.codex so a fresh volume inherits UID 1000 instead of being
# materialized root-owned at the mount point.
RUN userdel -r node \
    && useradd --create-home --uid 1000 codex \
    && mkdir -p /home/codex/.codex \
    && chown codex:codex /home/codex/.codex

USER codex
WORKDIR /home/codex

# auth.json (ChatGPT login + refreshed tokens), config.toml, and thread
# storage all live here; with this mounted, the container is freely
# replaceable and `thread/resume` survives recreation.
VOLUME /home/codex/.codex

EXPOSE 4500

CMD ["codex", "app-server", "--listen", "ws://0.0.0.0:4500"]
