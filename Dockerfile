# syntax=docker/dockerfile:1.26.0@sha256:ecfaec9ed6d810b56388c508f4121597bfbba70d41a6dfeee4d8cad5f295fc32
# Minimal image for running `codex app-server` as a long-lived service.
# The Codex CLI is a self-contained binary shipped through npm; node exists
# only to run its launcher shim.
#
# Everything here is pinned exactly: syntax frontend and base image by
# digest, codex by version. Renovate PRs the bumps (renovate.json), CI
# proves them (.github/workflows/ci.yml), and merging publishes
# (.github/workflows/docker-image.yml).
FROM node:24.19.0-slim@sha256:a9f5f7c91a432850b2a8a7797adf5eadb6c733ceed61167806cee7ea7fbc29df

# CODEX_VERSION is the single source of truth for what gets built: CI reads
# this pin to tag the published image, so tag and installed version can
# never drift apart. The marker comment below is what Renovate's custom
# manager matches (renovate.json).
# renovate: datasource=npm depName=@openai/codex
ARG CODEX_VERSION=0.148.0

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
# apt versions are intentionally not pinned: Debian drops superseded point
# releases from the archive, so version pins rot within weeks. The base
# image digest freezes them instead; bumping that pin refreshes them, and
# the weekly image scan covers the window in between.
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
