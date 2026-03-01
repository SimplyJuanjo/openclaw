#!/usr/bin/env bash
set -euo pipefail

OWNER_E164="${1:-${OWNER_E164:-}}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/openclaw}"
BACKUP_DIR="${BACKUP_DIR:-/mnt/openclaw/backups}"
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/mnt/openclaw/.openclaw}"
APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-git gh jq iproute2 iputils-ping dnsutils net-tools curl}"
SKIP_PULL="${SKIP_PULL:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"

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
require_cmd git
require_cmd cp
require_cmd mkdir
require_cmd date
require_cmd bash
require_cmd install
require_cmd stat
require_cmd grep
require_cmd sed
require_cmd cut

SELF_IMPROVE_DIR="${COMPOSE_DIR}/notes/hetzner-setup/self-improve"
HANDS_FREE_SCRIPT="${SELF_IMPROVE_DIR}/apply-owner-handsfree.sh"
OVERRIDE_SOURCE="${SELF_IMPROVE_DIR}/docker-compose.self-improve.override.yml"
OVERRIDE_TARGET="${COMPOSE_DIR}/docker-compose.self-improve.override.yml"
RUNNER_SOURCE="${SELF_IMPROVE_DIR}/self-improve"
RUNNER_TARGET="/mnt/openclaw/host-tools/ops/self-improve"
ENV_FILE="${COMPOSE_DIR}/.env"
TARGET_IMAGE="${OPENCLAW_IMAGE:-openclaw:local}"
if [[ "$TARGET_IMAGE" == "openclaw:local" && -f "$ENV_FILE" ]]; then
  env_image="$(grep -m1 '^OPENCLAW_IMAGE=' "$ENV_FILE" | cut -d= -f2- || true)"
  [[ -n "$env_image" ]] && TARGET_IMAGE="$env_image"
fi

[[ -f "$HANDS_FREE_SCRIPT" ]] || fail "Missing script: $HANDS_FREE_SCRIPT"
[[ -f "$OVERRIDE_SOURCE" ]] || fail "Missing compose override source: $OVERRIDE_SOURCE"
[[ -f "$RUNNER_SOURCE" ]] || fail "Missing runner source: $RUNNER_SOURCE"

compose_files=(-f docker-compose.yml)
[[ -f "${COMPOSE_DIR}/docker-compose.override.yml" ]] &&
  compose_files+=(-f docker-compose.override.yml)
[[ -f "$OVERRIDE_TARGET" ]] &&
  compose_files+=(-f docker-compose.self-improve.override.yml)

compose() {
  (
    cd "$COMPOSE_DIR"
    docker compose "${compose_files[@]}" "$@"
  )
}

step() {
  echo
  echo "==> $*"
}

step "Preflight checks"
(
  cd "$COMPOSE_DIR"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not a git repository: $COMPOSE_DIR"
  if [[ -n "$(git status --porcelain)" && "$SKIP_PULL" != "1" ]]; then
    fail "Working tree is not clean. Commit/stash changes or set SKIP_PULL=1."
  fi
)

step "Backup config files"
mkdir -p "$BACKUP_DIR"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
cp "${CONFIG_DIR}/.env" "${BACKUP_DIR}/.env.${ts}.bak"
cp "${CONFIG_DIR}/openclaw.json" "${BACKUP_DIR}/openclaw.json.${ts}.bak"
echo "Backups written to $BACKUP_DIR"

step "Resolve docker socket group"
if [[ -z "${DOCKER_SOCK_GID:-}" && -S /var/run/docker.sock ]]; then
  DOCKER_SOCK_GID="$(stat -c %g /var/run/docker.sock)"
fi
if [[ -n "${DOCKER_SOCK_GID:-}" ]]; then
  export DOCKER_SOCK_GID
  if [[ -f "$ENV_FILE" ]]; then
    if grep -q '^DOCKER_SOCK_GID=' "$ENV_FILE"; then
      sed -i -E "s/^DOCKER_SOCK_GID=.*/DOCKER_SOCK_GID=${DOCKER_SOCK_GID}/" "$ENV_FILE"
    else
      printf '\nDOCKER_SOCK_GID=%s\n' "$DOCKER_SOCK_GID" >>"$ENV_FILE"
    fi
  fi
  echo "Using DOCKER_SOCK_GID=$DOCKER_SOCK_GID"
else
  echo "WARN: Could not resolve DOCKER_SOCK_GID; docker socket access in container may fail."
fi

if [[ "$SKIP_PULL" != "1" ]]; then
  step "Pull latest code"
  (
    cd "$COMPOSE_DIR"
    git fetch --all --prune
    git pull --rebase origin main
  )
else
  step "Skipping git pull (SKIP_PULL=1)"
fi

step "Sync self-improve compose override"
cp "$OVERRIDE_SOURCE" "$OVERRIDE_TARGET"
if [[ ! " ${compose_files[*]} " =~ " -f docker-compose.self-improve.override.yml " ]]; then
  compose_files+=(-f docker-compose.self-improve.override.yml)
fi

step "Sync self-improve runner"
mkdir -p "$(dirname "$RUNNER_TARGET")"
install -m 0755 "$RUNNER_SOURCE" "$RUNNER_TARGET"
chown 1000:1000 "$RUNNER_TARGET" 2>/dev/null || true

if [[ "$SKIP_BUILD" != "1" ]]; then
  step "Build image $TARGET_IMAGE with required apt packages: $APT_PACKAGES"
  (
    cd "$COMPOSE_DIR"
    OPENCLAW_DOCKER_APT_PACKAGES="$APT_PACKAGES" \
      docker build \
        --build-arg OPENCLAW_DOCKER_APT_PACKAGES="$APT_PACKAGES" \
        -t "$TARGET_IMAGE" \
        .
  )
else
  step "Skipping image build (SKIP_BUILD=1)"
fi

step "Recreate containers"
compose up -d --force-recreate

step "Re-apply owner hands-free profile"
bash "$HANDS_FREE_SCRIPT" "$OWNER_E164"

step "Smoke checks"
compose exec -T openclaw-gateway \
  sh -lc '/opt/host-tools/npm-global/bin/codex --version && gh --version && docker --version && ip -V'
compose exec -T openclaw-gateway \
  sh -lc 'test -S /var/run/docker.sock && echo docker-sock-ok; test -d /host && echo host-mount-ok'
compose exec -T openclaw-gateway \
  sh -lc 'docker ps --format "{{.Names}}" | head -n 5'
compose run --rm -T openclaw-cli config get tools.exec.security
compose run --rm -T openclaw-cli config get tools.exec.ask
compose run --rm -T openclaw-cli config get tools.exec.timeoutSec
compose run --rm -T openclaw-cli config get tools.exec.pathPrepend
compose run --rm -T openclaw-cli config get agents.defaults.cliBackends.codex-cli.command
compose run --rm -T openclaw-cli config get agents.defaults.cliBackends.codex-dev.args
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_CODEX_BIN
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_CODEX_MODEL
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_CODEX_TIMEOUT_SEC
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_INSTALL_TIMEOUT_SEC
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_CHECK_TIMEOUT_SEC
compose run --rm -T openclaw-cli config get env.vars.SELF_IMPROVE_BUILD_TIMEOUT_SEC

echo
echo "Done."
echo "Next test from WhatsApp:"
echo '  /bash /opt/host-tools/ops/self-improve status <runId>'
