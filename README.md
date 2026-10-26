# codex-cli

Docker image that runs OpenAI's Codex CLI as a long-lived `codex app-server`
service (JSON-RPC over WebSocket), so a ChatGPT subscription can be used
through the official app-server protocol.

CI publishes `ghcr.io/yuzuyuzuyu/codex-cli` (linux/amd64 + linux/arm64) on
every merge that touches the image build or package lock, tagged `latest` plus the exact
`@openai/codex` version installed. The version comes from the
`package.json` pin and integrity-checked `package-lock.json`. Manual dispatch
rebuilds that reviewed version; an optional version input must match the lock.

Persistent state (ChatGPT login, config, threads) lives in
`/home/codex/.codex`, so mount a volume there. The server requires WebSocket
auth for non-loopback listeners (`codex app-server --help`); clients send the
capability token as `Authorization: Bearer <token>` on the upgrade.
`docker-compose.yml` is a working local example:

```sh
openssl rand -hex 32 > ws-token
docker compose up -d
docker compose exec codex codex login --device-auth   # once; persists in the volume
```

## Dependency pinning and updates

Application and build dependencies are pinned:

- `@openai/codex` and platform binaries: exact versions and integrity hashes in the npm lock
- Buildx, BuildKit and QEMU: explicit versions, with image digests
- base image and Dockerfile syntax frontend: version tag + digest
- the published image referenced by `docker-compose.yml`: version tag + digest
- every GitHub Action: commit SHA

A self-hosted Renovate runner (`.github/workflows/renovate.yml`, daily) turns
each upstream release into a PR. `ci.yml` gates every PR: it
builds the image, runs it, and checks the installed codex version against
the pin. Green minor/patch and digest PRs automerge; majors and red PRs
wait for a human (`renovate.json`). Merging an image or package-lock bump triggers
`docker-image.yml`, which publishes with the pinned version as the tag,
after which Renovate PRs the matching digest bump into
`docker-compose.yml`.

Merges are the only thing that changes the image, so `image-scan.yml` runs
Trivy against the published `latest` weekly. A fixable CRITICAL/HIGH CVE
fails the run and lands in the Security tab; the remedy is merging the
Renovate PR that refreshes the base image, or dispatching a rebuild to pick
up new apt versions.

The npm resolver waits three days before selecting new releases, including
transitive platform packages. Container installs use `npm ci --ignore-scripts`
and verify lockfile integrity. The shared runner retains third-party Docker
digests through their three-day observation period even when tags move; major
versions retain the seven-day gate. Our published image needs no second delay.

APT packages intentionally come from authenticated Debian repositories during
rebuilds so security fixes remain available. The base digest fixes the starting
image, not later APT downloads. CI and image scanning remain required.

### One-time setup

Renovate authenticates as a GitHub App. This is not cosmetic: PRs opened
with the built-in `GITHUB_TOKEN` never trigger workflows, so the CI gate
would not run and nothing could automerge.

1. Create a GitHub App (no webhook) with repository permissions: Checks
   (read), Commit statuses (read), Contents (read/write), Issues
   (read/write), Metadata (read), Pull requests (read/write), Workflows
   (read/write). Workflows write is what lets it bump action digests under
   `.github/workflows/`.
2. Install the app on this repository.
3. Add the repository variable `RENOVATE_APP_CLIENT_ID` (the app's Client
   ID, shown on its settings page) and the secret `RENOVATE_APP_PRIVATE_KEY`
   (the app's PEM private key). Also add
   the secret `RENOVATE_GITHUB_LOOKUP_TOKEN`: a scope-less classic PAT of a
   user account (the fleet uses the `yuzuyu-bot` machine user). Renovate uses
   it only for github.com datasource lookups, because GitHub applies an
   organisation's IP allow list to App tokens even for public repos and
   `aquasecurity/trivy-action` lives in one.
4. In repository settings, enable "Allow auto-merge", and add a branch
   ruleset on `main` requiring the `build` status check from CI (repo
   admins as bypass actors, so direct pushes still work). Skipping this
   step downgrades "green PRs merge themselves, red ones wait" from
   enforced to advisory. Dependabot alerts and automated security fixes
   are also on; Dependabot version updates stay off because Renovate owns
   the bumps and the two would open duplicate PRs.
