# Hetzner OpenClaw Notes

## Last Validation

- Date: `2026-03-01`
- Repo/branch: `simplyJuanjo/openclaw` on `main`
- Relevant fix commit already pushed: `4a3751948` (`Build: drop tsgo from check script`)

## Current Status

- Gateway is running on Hetzner VPS via Docker (`openclaw-gateway`) and reachable by Tailscale.
- WhatsApp channel is linked and operating.
- Tavily and Cala integrations are configured.
- Self-improve runtime (host-tools mounts + hands-free profile) is active on this VPS.
- Backup + healthcheck cron jobs are active.
- Public checks to IPv4 `:18789/:18790` remain blocked; SSH `22` is public (expected).
- Todoist wiring is active:
  - `todoist-ts-cli` installed in `/mnt/openclaw/host-tools/npm-global`.
  - Compose override exposes that binary path for gateway/cli containers.
  - Skill uses workspace `todoist` with `primaryEnv=TODOIST_API_TOKEN`.

## Incident Log

### 2026-03-01 - `tsgo` OOM on VPS

- Symptom: VPS memory spike (~3 GB RSS) and OOM pressure when running `pnpm check`.
- Cause: `check` script executed `pnpm tsgo`, which is too heavy for this VPS profile.
- Fix: removed `pnpm tsgo` from `package.json` `check` script and pushed commit `4a3751948`.
- Result: normal `check` no longer triggers the TypeScript memory spike.

### 2026-03-01 - Todoist auth/runtime mismatch

- Symptom: `todoist today` from gateway shell returned `Not authenticated`.
- Causes:
  - Shell command did not automatically use OpenClaw config env injection.
  - `openclaw-cli config get env.vars.TODOIST_API_TOKEN` returns `__OPENCLAW_REDACTED__` by design (cannot be reused as token).
  - Workspace skill metadata needed `metadata.openclaw` + `primaryEnv`.
- Fixes applied:
  - Cleaned stale/bad Todoist config values.
  - Re-set valid token in runtime config.
  - Updated workspace skill metadata to OpenClaw schema and kept requirements (`bins: todoist`, `env: TODOIST_API_TOKEN`).
- Result: direct auth probe with real persisted token returns `TODOIST_AUTH_OK`.

## Quick Verification

Use this compose stack alias:

```bash
CF="-f docker-compose.yml -f docker-compose.self-improve.override.yml"
```

Gateway + channels:

```bash
cd /opt/openclaw
docker compose $CF ps
docker compose $CF logs --tail=80 openclaw-gateway
docker compose $CF run --rm -T openclaw-cli channels status --probe
```

Todoist skill gating:

```bash
cd /opt/openclaw
docker compose $CF run --rm -T openclaw-cli skills info todoist --json | \
  jq '{name, primaryEnv, eligible, requirements, missing}'
```

Todoist token presence without printing secret:

```bash
tok="$(jq -r '.env.vars.TODOIST_API_TOKEN // empty' /mnt/openclaw/.openclaw/openclaw.json)"
echo "TODOIST_API_TOKEN length: ${#tok}"
```

Todoist auth probe using persisted token (expected: `TODOIST_AUTH_OK`):

```bash
cd /opt/openclaw
tok="$(jq -r '.env.vars.TODOIST_API_TOKEN // empty' /mnt/openclaw/.openclaw/openclaw.json)"
docker compose $CF exec -T -e TODOIST_API_TOKEN="$tok" openclaw-gateway \
  sh -c 'todoist today >/dev/null && echo TODOIST_AUTH_OK'
```

## Persistence Notes

- Runtime config persists at `/mnt/openclaw/.openclaw/openclaw.json`.
- Workspace skills persist at `/mnt/openclaw/.openclaw/workspace/skills/`.
- These changes survive restart/recreate/reboot.
- They are lost only if you restore an older backup or overwrite the workspace skill/config.

## Update-Safe Todoist + Hands-Free Checklist

```bash
cd /opt/openclaw
cp notes/hetzner-setup/self-improve/docker-compose.self-improve.override.yml \
  ./docker-compose.self-improve.override.yml
docker compose -f docker-compose.yml -f docker-compose.self-improve.override.yml up -d --build
bash notes/hetzner-setup/self-improve/apply-owner-handsfree.sh +346XXXXXXXX
```

One-shot updater:

```bash
cd /opt/openclaw
bash notes/hetzner-setup/self-improve/deploy-self-improve-update.sh +346XXXXXXXX
```
