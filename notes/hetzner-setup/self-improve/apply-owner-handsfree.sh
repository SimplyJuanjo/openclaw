#!/usr/bin/env bash
set -euo pipefail

OWNER_E164="${1:-${OWNER_E164:-}}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/openclaw}"
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/mnt/openclaw/.openclaw}"
APPROVALS_FILE="${EXEC_APPROVALS_FILE:-${CONFIG_DIR}/exec-approvals.json}"
SELF_IMPROVE_CODEX_BIN="${SELF_IMPROVE_CODEX_BIN:-/opt/host-tools/npm-global/bin/codex}"
SELF_IMPROVE_CODEX_MODEL="${SELF_IMPROVE_CODEX_MODEL:-gpt-5-codex}"
SELF_IMPROVE_CODEX_HOME="${SELF_IMPROVE_CODEX_HOME:-/home/node/.codex}"
SELF_IMPROVE_CODEX_HOME_HOST="${SELF_IMPROVE_CODEX_HOME_HOST:-/mnt/openclaw/host-tools/codex-home}"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

[[ -n "$OWNER_E164" ]] || fail "Usage: $0 <owner_e164>  (or export OWNER_E164)"
[[ -d "$COMPOSE_DIR" ]] || fail "Compose directory not found: $COMPOSE_DIR"

require_cmd docker
require_cmd jq
require_cmd rm
require_cmd mkdir
require_cmd chmod
require_cmd chown

compose_files=(-f docker-compose.yml)
[[ -f "${COMPOSE_DIR}/docker-compose.override.yml" ]] &&
  compose_files+=(-f docker-compose.override.yml)
[[ -f "${COMPOSE_DIR}/docker-compose.self-improve.override.yml" ]] &&
  compose_files+=(-f docker-compose.self-improve.override.yml)

compose() {
  (
    cd "$COMPOSE_DIR"
    docker compose "${compose_files[@]}" "$@"
  )
}

run_cli() {
  compose run --rm -T openclaw-cli "$@"
}

repair_codex_home_permissions() {
  mkdir -p "$SELF_IMPROVE_CODEX_HOME_HOST"
  if ! chown -R 1000:1000 "$SELF_IMPROVE_CODEX_HOME_HOST" 2>/dev/null; then
    echo "WARN: Could not chown $SELF_IMPROVE_CODEX_HOME_HOST to 1000:1000. If Codex fails with permission errors, run:"
    echo "  sudo chown -R 1000:1000 $SELF_IMPROVE_CODEX_HOME_HOST"
  fi
  chmod 700 "$SELF_IMPROVE_CODEX_HOME_HOST" 2>/dev/null || true
  find "$SELF_IMPROVE_CODEX_HOME_HOST" -type d -exec chmod 700 {} + 2>/dev/null || true
  find "$SELF_IMPROVE_CODEX_HOME_HOST" -type f -exec chmod 600 {} + 2>/dev/null || true
}

owner_json="$(printf '["%s"]' "$OWNER_E164")"

echo "Applying owner-only + hands-free profile for $OWNER_E164 ..."
run_cli config set commands.bash true
run_cli config set tools.elevated.enabled true
run_cli config set commands.allowFrom.whatsapp "$owner_json" --strict-json
run_cli config set tools.elevated.allowFrom.whatsapp "$owner_json" --strict-json

run_cli config set tools.exec.security full
run_cli config set tools.exec.ask off
run_cli config set approvals.exec.enabled false
run_cli config set tools.exec.pathPrepend '["/opt/host-tools/npm-global/bin","/home/node/.openclaw/bin"]' --strict-json

run_cli config set agents.defaults.cliBackends.codex-cli.command "$SELF_IMPROVE_CODEX_BIN"
run_cli config set agents.defaults.cliBackends.codex-dev.command "$SELF_IMPROVE_CODEX_BIN"
run_cli config set agents.defaults.cliBackends.codex-dev.args '["exec","--json","--color","never","--sandbox","workspace-write","--skip-git-repo-check"]' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.resumeArgs '["exec","resume","{sessionId}","--color","never","--sandbox","workspace-write","--skip-git-repo-check"]' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.output '"jsonl"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.resumeOutput '"text"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.input '"arg"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.modelArg '"--model"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.sessionIdFields '["thread_id"]' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.sessionMode '"existing"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.imageArg '"--image"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.imageMode '"repeat"' --strict-json
run_cli config set agents.defaults.cliBackends.codex-dev.serialize true

run_cli config set env.vars.SELF_IMPROVE_CODEX_BIN "$SELF_IMPROVE_CODEX_BIN"
run_cli config set env.vars.SELF_IMPROVE_CODEX_MODEL "$SELF_IMPROVE_CODEX_MODEL"
run_cli config set env.vars.SELF_IMPROVE_CODEX_HOME "$SELF_IMPROVE_CODEX_HOME"
run_cli config set env.vars.SELF_IMPROVE_CODEX_HOME_HOST "$SELF_IMPROVE_CODEX_HOME_HOST"

mkdir -p "$CONFIG_DIR"
chown 1000:1000 "$CONFIG_DIR" 2>/dev/null || true
chmod 700 "$CONFIG_DIR" 2>/dev/null || true
rm -f "$APPROVALS_FILE"
repair_codex_home_permissions

echo "Restarting gateway ..."
compose restart openclaw-gateway

cat <<EOF
Hands-free profile applied.

Behavior:
- Only owner can run /bash and elevated tools.
- Exec host policy is full + ask off.
- Approval forwarding is disabled.
- exec-approvals.json was deleted so gateway regenerates a clean file.

Quick verify:
  cd $COMPOSE_DIR
  docker compose ${compose_files[*]} run --rm -T openclaw-cli config get commands.allowFrom.whatsapp
  docker compose ${compose_files[*]} run --rm -T openclaw-cli config get tools.exec.security
  docker compose ${compose_files[*]} run --rm -T openclaw-cli config get tools.exec.ask
EOF
