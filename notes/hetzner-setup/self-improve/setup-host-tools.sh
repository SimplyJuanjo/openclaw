#!/usr/bin/env bash
set -euo pipefail

HOST_TOOLS_ROOT="${HOST_TOOLS_ROOT:-/mnt/openclaw/host-tools}"
OPENCLAW_REPO_DIR="${OPENCLAW_REPO_DIR:-/opt/openclaw}"
NPM_GLOBAL_DIR="${HOST_TOOLS_ROOT}/npm-global"
CODEX_HOME_DIR="${HOST_TOOLS_ROOT}/codex-home"
OPS_DIR="${HOST_TOOLS_ROOT}/ops"
RUNS_DIR="${HOST_TOOLS_ROOT}/runs"
RUNNER_SOURCE="${RUNNER_SOURCE:-${OPENCLAW_REPO_DIR}/notes/hetzner-setup/self-improve/self-improve}"
RUNNER_TARGET="${OPS_DIR}/self-improve"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"
}

require_cmd mkdir
require_cmd npm
require_cmd install

[[ -f "$RUNNER_SOURCE" ]] || fail "Runner script not found: $RUNNER_SOURCE"

mkdir -p "$NPM_GLOBAL_DIR" "$CODEX_HOME_DIR" "$OPS_DIR" "$RUNS_DIR"
install -m 0755 "$RUNNER_SOURCE" "$RUNNER_TARGET"

echo "Installing Codex CLI in $NPM_GLOBAL_DIR ..."
npm install -g --prefix "$NPM_GLOBAL_DIR" @openai/codex@latest

if [[ ! -f "${HOST_TOOLS_ROOT}/config.env.example" ]]; then
  cat >"${HOST_TOOLS_ROOT}/config.env.example" <<'EOF'
# Copy relevant values into your compose env runtime.
GH_TOKEN=ghp_replace_me
SELF_IMPROVE_CODEX_MODEL=gpt-5-codex
EOF
fi

cat <<EOF
Host tools prepared.

Paths:
- npm global: $NPM_GLOBAL_DIR
- Codex home: $CODEX_HOME_DIR
- ops: $OPS_DIR
- runs: $RUNS_DIR
- runner: $RUNNER_TARGET

Next steps:
1. Authenticate Codex on host:
   CODEX_HOME=$CODEX_HOME_DIR $NPM_GLOBAL_DIR/bin/codex
2. Verify auth file:
   ls -lah $CODEX_HOME_DIR/auth.json
3. Add compose mounts from:
   $OPENCLAW_REPO_DIR/notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml
4. Recreate containers:
   cd /opt/openclaw && docker compose down && docker compose up -d --build
EOF
