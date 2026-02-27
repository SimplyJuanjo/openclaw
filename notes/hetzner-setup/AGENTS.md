# Hetzner + OpenClaw Tracking

## Purpose

Living summary of what we have done for the `myclaw-gate` deployment and what remains.
Update this file after each relevant session.

## Session Snapshot (2026-02-25)

- Created Hetzner server: `myclaw-gate` (`CX23`).
- Enabled backups in Hetzner.
- Applied firewall baseline:
- `TCP 22` inbound (SSH)
- `UDP 41641` inbound (Tailscale)
- Attached extra volume (`+10 GB`) and mounted it to `/mnt/openclaw`.
- Added persistent mount in `/etc/fstab` using volume UUID.
- Installed Docker and Docker Compose on the VPS.
- Installed and authenticated Tailscale on the VPS.
- Cloned `openclaw` repo to `/opt/openclaw`.
- Built local image `openclaw:local` (fixed pull error from `openclaw:latest`).
- Set OpenClaw gateway config via CLI:
- `gateway.mode=local`
- `gateway.bind=loopback`
- `gateway.port=18789`
- `gateway.auth.mode=token`
- `gateway.auth.token=<from .env>`
- Recreated gateway container with `--allow-unconfigured` in compose override to avoid startup loop.
- Switched gateway bind to `lan` for direct Tailnet access (`ws://100.71.241.111:18789`).
- Installed OpenClaw CLI on local Windows (`openclaw 2026.2.13`, Node `v24.13.1`).
- Approved local Windows pairing request from the VPS.
- Verified local remote connectivity: `openclaw gateway health` -> `OK (0ms)`.
- Installed useful host binaries on VPS: `jq`, `ffmpeg`, `ffprobe`, `socat`.
- Verified optional binary ecosystem status:
- `gog` and `goplaces` installed on host (`/usr/local/bin`).
- `wacli` not installable on Linux from latest release assets (current upstream gap).
- Verified container path gap:
- `docker compose exec openclaw-gateway sh -lc 'which gog goplaces wacli || true'` returns empty.
- Confirmed this means binaries are host-only for now, not inside `openclaw-gateway` container.
- WhatsApp channel linked and running on VPS gateway.
- TTS switched to OpenAI with voice `marin` (preferred feminine voice).
- Voice output is working.
- Gateway upgraded to `2026.2.22-2`.
- Auto update configured:
- `update.channel=stable`
- `update.auto.enabled=true`
- Daily backup + periodic healthcheck cron jobs are active:
- `17 3 * * * /usr/local/bin/openclaw-backup.sh`
- `*/10 * * * * /usr/local/bin/openclaw-healthcheck.sh`
- Backup artifact verified at `/mnt/openclaw/backups/openclaw-YYYY-MM-DD-HHMMSS.tar.gz`.
- Tavily skill is installed and working.
- Cala skill is installed; key is present in runtime env. Current instability is timeout/quality, not missing key.
- WhatsApp pairing and multi-user access flow is working (owner + approved contacts).
- Group usage is verified (bot receives and replies in group conversations).

## Change Log

### 2026-02-14

- Provisioned Hetzner server `myclaw-gate` (`CX23`).
- Enabled backups and applied firewall baseline (`TCP 22`, `UDP 41641`).
- Mounted and persisted the extra `10 GB` volume at `/mnt/openclaw`.
- Installed Docker + Docker Compose + Tailscale and authenticated the host.
- Cloned repo to `/opt/openclaw` and built `openclaw:local`.
- Fixed startup blockers:
- image pull failure for `openclaw:latest`
- missing `gateway.mode=local`
- Configured gateway auth + bind settings and recreated service container.
- Switched from SSH-tunnel plan to Tailnet-direct plan.
- Set local remote config on Windows:
- `gateway.mode=remote`
- `gateway.remote.url=ws://100.71.241.111:18789`
- `gateway.remote.token=<vps token>`
- Resolved `pairing required` by approving pending device from gateway container.
- Final outcome: remote health check succeeds from local Windows over Tailscale.

### 2026-02-14 (follow-up: VPS binaries)

- Fixed host tooling script and installed missing system tools on VPS (`jq`, `ffmpeg`, `socat`).
- Confirmed `ffprobe` available after `ffmpeg` install.
- Installed `gog` from `steipete/gogcli` latest Linux release.
- Installed `goplaces` from latest Linux release.
- Verified `wacli` cannot be installed on Linux from latest release (no Linux artifact published).
- Verified `gog`/`goplaces` are currently host-only and not visible inside `openclaw-gateway` container.
- Decision pending: bind-mount host binaries into container vs baking them into custom image.

### 2026-02-15 (voice updates)

- Confirmed WhatsApp outbound voice replies are working.
- Selected OpenAI TTS voice: `marin`.
- Kept OpenAI as TTS provider for higher quality than Edge TTS.
- Voice input (audio transcription) remains pending final auth/env wiring verification on gateway runtime.

### 2026-02-23 (ops + hardening baseline)

- Upgraded gateway/runtime to `2026.2.22-2`.
- Enabled update settings:
- `update.channel=stable`
- `update.auto.enabled=true`
- Added and validated backup + healthcheck scripts with cron.
- Verified WhatsApp traffic in logs (inbound, auto-reply, reconnect behavior).
- Verified public reachability from local network test:
- `116.203.20.220:18789` and `:18790` are not reachable from outside (tests timed out).
- Confirmed expected internet SSH scan noise in `journalctl` (credential brute-force attempts on port 22).

### 2026-02-25 (skills + env sanity)

- Installed `self-improving` skill via ClawHub and validated it is visible from workspace metadata.
- Confirmed hooks path from that skill is not present (no `hooks/openclaw` directory in the package).
- Validated Tavily and Cala keys are present in runtime env (`LEN > 0` checks).
- Observed intermittent Cala timeout responses; treated as provider/API reliability issue, not env loss.
- Clarified reasoning behavior:
- `reasoningLevel` is session-scoped; no stable global `reasoningDefault` key yet in current release.
- Reasoning/verbose output control should remain explicit via directives + trusted command allowlists.

### 2026-02-27 (self-improve supervised runner kit)

- Added implementation kit under `notes/hetzner-setup/self-improve/`:
- `self-improve` deterministic runner (`start`, `status`, `logs`) with lock + run metadata + Draft PR flow.
- `setup-host-tools.sh` to provision host Codex runtime and install runner into `/mnt/openclaw/host-tools/ops`.
- `docker-compose.self-improve.override.yml` with host-tool mounts for `openclaw-gateway` and `openclaw-cli`.
- `apply-owner-guardrails.sh` to enforce owner-only operational control and approval forwarding.
- `README.md` runbook with preflight, deployment, WhatsApp commands, and acceptance checks.

### Entry Template

- `YYYY-MM-DD`
- Changes made:
- Outcome:
- Next action:

## Current Status

- VPS gateway is up and reachable via Tailscale.
- Local Windows CLI is connected to the remote gateway and healthy.
- Gateway runtime version: `2026.2.22-2`.
- Update policy: `stable` channel with `auto.enabled=true`.
- Host-level utility baseline is ready (`jq`, `ffmpeg`, `ffprobe`, `socat`, `tailscale`).
- Optional CLIs currently available on host: `gog`, `goplaces`.
- Optional CLIs not available on host: `wacli` (no Linux release asset).
- Container currently does not expose `gog`/`goplaces`/`wacli` in PATH.
- TTS target voice is `marin` (OpenAI).
- Voice output path is operational.
- Tavily skill is operational from workspace.
- Cala skill is installed; env key is loaded, but provider responses are currently inconsistent/time out in some runs.
- Backups and healthcheck cron jobs are active and producing expected outputs.
- Public port scans on SSH are present (expected for internet-exposed SSH); gateway ports are not reachable from local public test.
- Self-improve supervised automation kit is prepared in repo and pending deployment on VPS.

## Next Steps

1. Rotate gateway token (it was exposed in terminal/chat logs).
2. Re-apply local `gateway.remote.token` with the new value.
3. Lock command execution scope (`commands.allowFrom` and `tools.elevated.allowFrom`) to owner-only where needed.
4. Decide container strategy for optional CLIs: bind-mount host binaries or bake into image.
5. Continue Cala troubleshooting as reliability/API timeout issue (not env loss).
6. Optional hardening: move from `bind=lan` to `bind=tailnet` or `loopback + tailscale serve`.
7. Deploy and validate `notes/hetzner-setup/self-improve/` on VPS (`start/status/logs` + Draft PR E2E).

## Notes

- Warnings for `CLAUDE_*` env vars are non-blocking for this setup.
- Current live exposure model is Tailnet direct (`bind=lan`, access via Tailscale IP).
- Upstream reference for `wacli` Linux gap: `https://github.com/steipete/wacli/issues/12`.
- Source-of-truth for persistent runtime env is `~/.openclaw/.env` on the VPS mount (`/mnt/openclaw/.openclaw/.env`).
- If an assistant reports "missing key" while runtime shows non-zero env length, treat it as model/tool inference error first and validate with direct script execution.

## Linux/Mac Binary Snapshot (2026-02-25)

This section tracks the current status of Pete ecosystem binaries for Linux VPS usage.

### Linux status by binary

- Linux-ready now:
- `gogcli` (`gog`): Google Workspace CLI (Gmail, Calendar, Drive, Contacts, Sheets, Docs).
- `goplaces`: Google Places API CLI (search, details, reviews).
- `sag`: ElevenLabs TTS CLI.
- `ordercli`: order tracking/food delivery CLI.
- `camsnap`: RTSP/ONVIF camera snapshots/clips.
- `blucli`: BluOS speaker control CLI.
- `sonoscli`: Sonos control CLI.
- Not Linux-ready in latest releases:
- `wacli`: latest release currently ships macOS-only artifacts.
- `summarize`: latest release currently ships macOS arm64 binary (plus browser extensions), no Linux binary artifact in latest release.

### Upstream tracking

- `wacli` Linux release request (open): `https://github.com/steipete/wacli/issues/12`
- `summarize` Linux support PR (open): `https://github.com/steipete/summarize/pull/104`
- OpenClaw docs PR updating Hetzner binary examples (open): `https://github.com/openclaw/openclaw/pull/20090`
- Historical OpenClaw discussion about macOS-first skills (closed): `https://github.com/openclaw/openclaw/issues/3281`

### Operational implication for this Hetzner setup

- For Linux VPS-first deployments, prioritize skills backed by Linux-ready binaries (`gog`, `goplaces`, etc.).
- Treat `wacli` and `summarize` as temporarily blocked on pure Linux until upstream Linux artifacts are published (or use alternative skills/tools that run on Linux).
