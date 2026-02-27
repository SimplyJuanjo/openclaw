#!/usr/bin/env bash
set -euo pipefail

OWNER_E164="${1:-${OWNER_E164:-}}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/openclaw}"
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/mnt/openclaw/.openclaw}"
APPROVALS_FILE="${EXEC_APPROVALS_FILE:-${CONFIG_DIR}/exec-approvals.json}"

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
require_cmd node

compose() {
  (
    cd "$COMPOSE_DIR"
    docker compose "$@"
  )
}

run_cli() {
  compose run --rm -T openclaw-cli "$@"
}

owner_json="$(printf '["%s"]' "$OWNER_E164")"
targets_json="$(printf '[{"channel":"whatsapp","to":"%s"}]' "$OWNER_E164")"

echo "Applying command/elevated owner-only policy for $OWNER_E164 ..."
run_cli config set commands.bash true
run_cli config set tools.elevated.enabled true
run_cli config set commands.allowFrom.whatsapp "$owner_json" --strict-json
run_cli config set tools.elevated.allowFrom.whatsapp "$owner_json" --strict-json
run_cli config set tools.exec.security allowlist
run_cli config set tools.exec.ask always
run_cli config set approvals.exec.enabled true
run_cli config set approvals.exec.mode targets
run_cli config set approvals.exec.targets "$targets_json" --strict-json

mkdir -p "$(dirname "$APPROVALS_FILE")"
if [[ ! -f "$APPROVALS_FILE" ]]; then
  echo '{"version":1}' >"$APPROVALS_FILE"
fi

echo "Forcing askFallback=deny in $APPROVALS_FILE ..."
APPROVALS_FILE="$APPROVALS_FILE" node <<'NODE'
const fs = require("node:fs");
const filePath = process.env.APPROVALS_FILE;
let doc = { version: 1 };
try {
  doc = JSON.parse(fs.readFileSync(filePath, "utf8"));
} catch {
  doc = { version: 1 };
}
if (!doc || typeof doc !== "object") {
  doc = { version: 1 };
}
if (!doc.defaults || typeof doc.defaults !== "object") {
  doc.defaults = {};
}
doc.version = 1;
doc.defaults.security = "allowlist";
doc.defaults.ask = "always";
doc.defaults.askFallback = "deny";
if (typeof doc.defaults.autoAllowSkills !== "boolean") {
  doc.defaults.autoAllowSkills = false;
}
fs.writeFileSync(filePath, `${JSON.stringify(doc, null, 2)}\n`, "utf8");
NODE

cat <<EOF
Guardrails applied.

Quick verify:
  cd $COMPOSE_DIR
  docker compose run --rm -T openclaw-cli config get commands.bash
  docker compose run --rm -T openclaw-cli config get commands.allowFrom.whatsapp
  docker compose run --rm -T openclaw-cli config get tools.elevated.allowFrom.whatsapp
  docker compose run --rm -T openclaw-cli config get tools.exec.ask
  docker compose run --rm -T openclaw-cli config get approvals.exec.targets
  cat $APPROVALS_FILE
EOF
