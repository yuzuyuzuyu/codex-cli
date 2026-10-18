# syntax=docker/dockerfile:1.28.0@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
# Minimal image for running `codex app-server` as a long-lived service.
# The Codex CLI is a self-contained binary shipped through npm; node exists
# only to run its launcher shim.
#
# Everything here is pinned exactly: syntax frontend and base image by
# digest, codex by version. Renovate PRs the bumps (renovate.json), CI
# proves them (.github/workflows/ci.yml), and merging publishes
# (.github/workflows/docker-image.yml).
FROM node:24.22.0-slim@sha256:a5f4366e834695d5f363b920c104953a535d3a9864d1bdf74566a0ebe01daee5

# CODEX_VERSION is the single source of truth for what gets built: CI reads
# this pin to tag the published image, so tag and installed version can
# never drift apart. The marker comment below is what Renovate's custom
# manager matches (renovate.json).
# renovate: datasource=npm depName=@openai/codex
ARG CODEX_VERSION=0.163.0

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
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get install -y --no-install-recommends ca-certificates git bubblewrap \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@openai/codex@${CODEX_VERSION}" \
    && npm cache clean --force

# Package managers are build tools; this runtime starts Node directly.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack /opt/yarn-v* \
  && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    /usr/local/bin/pnpm /usr/local/bin/pnpx /usr/local/bin/yarn /usr/local/bin/yarnpkg

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
