# OpenClaw Self-Improve Kit (Hetzner + Docker)

This folder implements the supervised self-improvement workflow:

- Codex CLI runs from host-mounted tooling.
- OpenClaw triggers runs via `/bash`.
- Operation mode can be supervised (`/approve`) or hands-free owner-only.
- Output target is a Draft PR in your fork.

## Files

- `setup-host-tools.sh`: prepares `/mnt/openclaw/host-tools/*`, installs Codex CLI, deploys runner.
- `docker-compose.self-improve.override.yml`: required mounts/env for `openclaw-gateway` and `openclaw-cli`.
- `apply-owner-guardrails.sh`: enforces owner-only operational control + approval defaults.
- `apply-owner-handsfree.sh`: enforces owner-only operational control + hands-free exec defaults.
- `deploy-self-improve-update.sh`: one-shot update (backup + pull + build + recreate + hands-free reapply + smoke checks).
- `self-improve`: deterministic runner (`start`, `status`, `logs`).
- `exec-approvals.defaults.json`: optional reference defaults file.
- `UPDATE_HANDS_FREE_RUNBOOK.md`: update checklist to keep hands-free mode stable after pulls/rebuilds.

## 1) Preflight and backups

```bash
cd /opt/openclaw
docker compose ps
docker compose logs --tail=80 openclaw-gateway

ts="$(date -u +%Y%m%dT%H%M%SZ)"
cp /mnt/openclaw/.openclaw/.env "/mnt/openclaw/backups/.env.$ts.bak"
cp /mnt/openclaw/.openclaw/openclaw.json "/mnt/openclaw/backups/openclaw.json.$ts.bak"
```

## 2) Install host tools (outside Docker)

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/setup-host-tools.sh
```

Authenticate Codex on host (interactive):

```bash
CODEX_HOME=/mnt/openclaw/host-tools/codex-home \
  /mnt/openclaw/host-tools/npm-global/bin/codex
```

## 3) Wire Docker mounts

Copy the override into your compose stack and recreate:

```bash
cd /opt/openclaw
cp notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml ./docker-compose.self-improve.override.yml
docker compose -f docker-compose.yml -f docker-compose.self-improve.override.yml up -d --build
```

Container validation:

```bash
cd /opt/openclaw
docker compose -f docker-compose.yml -f docker-compose.self-improve.override.yml exec -T openclaw-gateway \
  /opt/host-tools/npm-global/bin/codex --version
docker compose -f docker-compose.yml -f docker-compose.self-improve.override.yml exec -T openclaw-gateway \
  sh -lc 'test -w /opt/openclaw-host && echo rw-ok'
```

## 4) GitHub PAT + remotes

Requirements:

- Fine-grained PAT in `GH_TOKEN` with fork access (`contents:rw`, `pull_requests:rw`, `metadata:r`).
- `/opt/openclaw` remotes:
  - `upstream=https://github.com/openclaw/openclaw.git`
  - `origin=https://github.com/<your-user>/openclaw.git`

Quick checks:

```bash
cd /opt/openclaw
git remote -v
GH_TOKEN=... gh auth status
```

Make sure `GH_TOKEN` is available to container runtime (`.env` used by compose).

## 5) Enforce operation profile

Choose one mode depending on how you want to operate.

### 5A) Supervised (approval prompts enabled)

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/apply-owner-guardrails.sh +346XXXXXXXX
```

This applies:

- `commands.bash=true`
- `tools.elevated.enabled=true`
- `commands.allowFrom.whatsapp=[owner]`
- `tools.elevated.allowFrom.whatsapp=[owner]`
- `tools.exec.ask=always`
- `approvals.exec.enabled=true`
- `approvals.exec.targets=[{channel:"whatsapp",to:owner}]`
- `askFallback=deny` in `exec-approvals.json`

### 5B) Hands-free (no approval prompts)

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/apply-owner-handsfree.sh +346XXXXXXXX
```

This applies:

- `commands.bash=true`
- `tools.elevated.enabled=true`
- `commands.allowFrom.whatsapp=[owner]`
- `tools.elevated.allowFrom.whatsapp=[owner]`
- `tools.exec.security=full`
- `tools.exec.ask=off`
- `approvals.exec.enabled=false`
- Regenerates `exec-approvals.json` cleanly (remove stale/locked file cases)

## 6) Runner usage from WhatsApp

Start:

```text
/bash /opt/host-tools/ops/self-improve start "objetivo concreto"
```

Approve execution:

```text
/approve <id> allow-once
```

Track:

```text
/bash /opt/host-tools/ops/self-improve status <runId>
/bash /opt/host-tools/ops/self-improve logs <runId>
```

## 7) Keep it stable across updates

Follow:

- `notes/hetzner-setup/self-improve/UPDATE_HANDS_FREE_RUNBOOK.md`

Or run it in one shot:

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/deploy-self-improve-update.sh +346XXXXXXXX
```

That runbook includes:

- Rebuild with `OPENCLAW_DOCKER_APT_PACKAGES="git gh jq"` so `gh` stays available.
- Compose file set for recreate.
- Hands-free reapply command after every update.
- Post-update smoke checks.

## Status contract

The `status` command returns JSON with:

- `runId`
- `state`
- `branch`
- `headSha`
- `checkStatus`
- `buildStatus`
- `prUrl`
- `summary`
- `error`

## Acceptance checks

1. `start` returns a `runId` and leaves a run file in `/opt/host-tools/runs/<runId>.json`.
2. Non-owner cannot execute `/bash` operations.
3. Sensitive exec remains blocked until `/approve`.
4. `status` and `logs` expose deterministic run state.
5. Branch starts from `upstream/main` and produces Draft PR (no auto-merge).
6. Failed checks mark the run as `failed` with `error` populated.
