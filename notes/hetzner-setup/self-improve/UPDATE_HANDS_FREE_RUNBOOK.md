# OpenClaw Hetzner: Update + Hands-Free Runbook

This runbook keeps Codex CLI + self-improve working after pulls/rebuilds.

One-command alternative:

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/deploy-self-improve-update.sh +346XXXXXXXX
```

## Goal

After each update, preserve:

- Host Codex auth (`/mnt/openclaw/host-tools/codex-home`).
- Host runner + run logs (`/mnt/openclaw/host-tools/ops`, `/mnt/openclaw/host-tools/runs`).
- Compose mounts for host tools + repo mount.
- Owner-only command control from WhatsApp.
- Hands-free exec profile (`security=full`, `ask=off`, no approval prompts).

## 1) Pre-update backup

```bash
cd /opt/openclaw
ts="$(date -u +%Y%m%dT%H%M%SZ)"
cp /mnt/openclaw/.openclaw/.env "/mnt/openclaw/backups/.env.$ts.bak"
cp /mnt/openclaw/.openclaw/openclaw.json "/mnt/openclaw/backups/openclaw.json.$ts.bak"
```

## 2) Pull and rebuild image (with gh/git inside container)

```bash
cd /opt/openclaw

git fetch --all --prune
git pull --rebase origin main

cp notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml \
  ./docker-compose.self-improve.override.yml

export OPENCLAW_DOCKER_APT_PACKAGES="git gh jq"

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  build \
  --build-arg OPENCLAW_DOCKER_APT_PACKAGES="$OPENCLAW_DOCKER_APT_PACKAGES"

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  up -d --force-recreate
```

## 3) Re-apply hands-free owner profile

```bash
cd /opt/openclaw
chmod +x notes/hetzner-setup/self-improve/apply-owner-handsfree.sh
bash notes/hetzner-setup/self-improve/apply-owner-handsfree.sh +346XXXXXXXX
```

## 4) Post-update smoke checks

```bash
cd /opt/openclaw

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  exec -T openclaw-gateway \
  sh -lc '/opt/host-tools/npm-global/bin/codex --version && gh --version'

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  run --rm -T openclaw-cli \
  config get tools.exec.security

docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  run --rm -T openclaw-cli \
  config get tools.exec.ask
```

Expected:

- `codex --version` works in container.
- `gh --version` works in container.
- `tools.exec.security` is `full`.
- `tools.exec.ask` is `off`.

## 5) WhatsApp validation

From owner number:

```text
/bash /opt/host-tools/ops/self-improve status <runId>
```

Expected:

- Runs directly without `/approve`.
- Returns status JSON from runner.

## 6) Keep Todoist CLI update-safe (no Dockerfile edits)

Install `todoist-ts-cli` on the host-tools prefix (persistent across image rebuilds):

```bash
cd /opt/openclaw
npm install -g --prefix /mnt/openclaw/host-tools/npm-global "todoist-ts-cli@^0.2.0"
```

Ensure the gateway/container `PATH` includes host-tools bin. It is already defined in:

- `notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml`

Copy that file to compose root before recreate:

```bash
cd /opt/openclaw
cp notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml \
  ./docker-compose.self-improve.override.yml
```

Expected `PATH` entries in that override:

```yaml
services:
  openclaw-gateway:
    environment:
      PATH: /opt/host-tools/npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  openclaw-cli:
    environment:
      PATH: /opt/host-tools/npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

Then recreate using the same compose stack you normally use.

Quick verify after any update:

```bash
cd /opt/openclaw
docker compose \
  -f docker-compose.yml \
  -f docker-compose.self-improve.override.yml \
  exec -T openclaw-gateway \
  sh -lc 'which todoist && todoist --version'
```

If this passes, Todoist skill dependencies survived the update.

## 7) If exec gets stuck again

Run:

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/apply-owner-handsfree.sh +346XXXXXXXX
```

If still broken, inspect:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  -f docker-compose.self-improve.override.yml \
  logs --tail=200 openclaw-gateway | rg -i "approval|exec-approvals|EACCES|permission|denied"
```
