# Hetzner OpenClaw Notes

## Current Status

- Gateway deployed on Hetzner VPS and running 24/7 via Docker (`openclaw-gateway`).
- Remote access working through Tailscale.
- WhatsApp channel linked and operational.
- Tavily integration configured and working.
- Cala integration configured and working.
- Self-improve supervised runner kit prepared in repo at `notes/hetzner-setup/self-improve/` (pending VPS rollout).
- Hardening status:
  - Public test to VPS IPv4 for ports `18789/18790`: blocked.
  - SSH (`22`) remains public (expected for remote admin).
  - Docker is still listening on `0.0.0.0` for gateway ports, so firewall remains critical.

## Phase Status

- `1) Hardening`: Ready (current firewall posture is acceptable).
- `2) Skills`: Ready (`Tavily` + `Cala` done).
- `3) Operations`: Ready (validated on 2026-02-23):
  - Backup file present under `/mnt/openclaw/backups`.
  - Cron jobs configured for backup + healthcheck.
  - Healthcheck works with container-local probe.
  - Alert path present (`logger -t openclaw-health "FAILED"`).
  - Update policy confirmed (`update.channel=stable`, `update.auto.enabled=true`).
- `4) Self-Improve Automation`: Planned (implementation artifacts ready; deployment pending).

## Operations Readiness Checklist (Phase 3)

- Backups:
  - Daily backup exists for `/mnt/openclaw/.openclaw`.
  - Rotation/retention policy exists.
  - Restore test completed at least once.
- Health checks:
  - Scheduled check exists (gateway health + channel status).
  - Alert path exists (log or notification on failure).
- Update policy:
  - Stable channel configured.
  - Auto-update behavior explicitly chosen (on/off).
  - Rollback procedure documented and tested.

## Quick Verification Commands

```bash
# A) Runtime
cd /opt/openclaw
docker compose ps
docker compose logs --tail=80 openclaw-gateway

# B) Gateway + channel health
docker compose exec -T openclaw-gateway node dist/index.js gateway health
docker compose run --rm -T openclaw-cli channels status --probe

# C) Update posture
docker compose run --rm -T openclaw-cli --version
docker compose run --rm -T openclaw-cli config get update.channel
docker compose run --rm -T openclaw-cli config get update.auto.enabled

# D) Backup evidence (adjust path if you use another destination)
ls -lah /mnt/openclaw
find /mnt/openclaw -maxdepth 2 -type f | rg -i 'backup|snapshot|tar|gz|zst' || true
```
