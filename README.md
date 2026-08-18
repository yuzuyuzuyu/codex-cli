# codex-cli

Docker image that runs OpenAI's Codex CLI as a long-lived `codex app-server`
service (JSON-RPC over WebSocket), so a ChatGPT subscription can be used
through the official app-server protocol.

CI polls npm every 6 hours and publishes
`ghcr.io/yuzuyuzuyu/codex-cli:latest` plus one tag per `@openai/codex`
release (linux/amd64 + linux/arm64). Pushes to main rebuild the current
version; manual dispatch accepts a version override.

Persistent state (ChatGPT login, config, threads) lives in
`/home/codex/.codex` — mount a volume there. The server requires WebSocket
auth for non-loopback listeners (`codex app-server --help`); clients send the
capability token as `Authorization: Bearer <token>` on the upgrade.
`docker-compose.yml` is a working local example:

```sh
openssl rand -hex 32 > ws-token
docker compose up -d
docker compose exec codex codex login --device-auth   # once; persists in the volume
```
