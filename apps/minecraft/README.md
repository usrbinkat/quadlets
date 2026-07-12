# Minecraft Quadlet Fleet

A multi-world Minecraft Java Edition server fleet deployed as rootless Podman
containers managed by systemd via Quadlet unit files. Players connect to a
single address and switch between worlds using the Velocity proxy.

## Overview

This repository deploys a complete Minecraft network on a single Linux host:
a Velocity reverse proxy authenticating players via Mojang, routing them to one
of four backend worlds — two near-vanilla (Paper) and two heavily modded
(NeoForge). All containers share a private bridge network, and the proxy is the
only service exposed to the internet. Configuration is environment-driven,
secrets are injected at deploy time, and the entire fleet is managed through
standard systemd commands.

## Architecture

```
Internet
  │
  │ TCP :25565
  ▼
┌──────────────────────────────────────────────────────────────────────┐
│ VM: Fedora 44, rootless Podman, systemd user session (linger)        │
│                                                                      │
│  enp1s0 :25565                                                       │
│    │                                                                 │
│    ▼ rootlessport (userspace TCP proxy)                              │
│    │                                                                 │
│    ▼ minecraft bridge (10.89.100.0/24, aardvark-dns)                 │
│    │                                                                 │
│    ├── minecraft-proxy ──────── Velocity JVM                         │
│    │     online-mode=true       Mojang auth, HmacSHA256 forwarding   │
│    │     :25565 (only published port)                                │
│    │       │                                                         │
│    │       ├── minecraft-survival ─── Paper, survival, normal        │
│    │       ├── minecraft-creative ─── Paper, creative, peaceful      │
│    │       ├── minecraft-modded-survival ── NeoForge, hard           │
│    │       └── minecraft-modded-creative ── NeoForge, peaceful       │
│    │           (backends: online-mode=false, no published ports)      │
│    │                                                                 │
│    └── DNS: container names resolve via aardvark-dns on bridge       │
└──────────────────────────────────────────────────────────────────────┘
```

## Worlds

| World | Server Type | Game Mode | Difficulty | Mods | Connect Via |
|-------|-------------|-----------|------------|------|-------------|
| survival | Paper | survival | normal | none | `survival.play.braincraft.io` |
| creative | Paper | creative | peaceful | none | `creative.play.braincraft.io` |
| modded | NeoForge | survival | hard | NeoVelocity, Lithium, Spark, Chunky | `modded.play.braincraft.io` |
| insane | NeoForge | creative | peaceful | NeoVelocity, Lithium, Spark, Chunky | `insane.play.braincraft.io` |

All worlds share the same whitelist, operator list, and player authentication.
A player's UUID, skin, and cape are preserved across all worlds via Velocity
modern forwarding.

## Player Guide

Add any of the following addresses to your Minecraft Java Edition server list:

```
survival.play.braincraft.io
creative.play.braincraft.io
modded.play.braincraft.io
insane.play.braincraft.io
play.braincraft.io              (connects to survival by default)
```

All addresses use port `25565` (the default — no port number needed in the
client). Once connected, switch worlds at any time with:

```
/server survival
/server creative
/server modded
/server insane
```

Modded worlds require the matching NeoForge modpack installed on your client.

## Quick Start

Prerequisites (one-time, handled by VM provisioning):

```bash
loginctl enable-linger $(whoami)
podman pull docker.io/itzg/minecraft-server:java25
podman pull docker.io/itzg/minecraft-server:java21
podman pull docker.io/itzg/mc-proxy:java25
```

Deploy:

```bash
git clone https://github.com/usrbinkat/quadlets /tmp/quadlets
cd /tmp/quadlets/apps/minecraft
./scripts/deploy.sh --generate-secret
```

Start the fleet:

```bash
systemctl --user start minecraft-proxy.service
systemctl --user start minecraft@survival.service
systemctl --user start minecraft@creative.service
systemctl --user start minecraft-modded-survival.service
systemctl --user start minecraft-modded-creative.service
```

Verify:

```bash
systemctl --user status minecraft-proxy.service
podman healthcheck run minecraft-proxy
journalctl --user -t minecraft-proxy -f
```

## How It Works

### Velocity Proxy

The Velocity proxy is the single entry point for all player connections. It
handles Mojang authentication (`online-mode=true`), then forwards authenticated
player data to the appropriate backend using modern forwarding — an HmacSHA256-
signed payload on the `velocity:player_info` login plugin channel.

Players are routed to backends by the hostname they connect with (`[forced-hosts]`
in `velocity.toml`). If no forced host matches, the player joins the first server
in the `try` list (survival by default).

Configuration injection uses the itzg/mc-proxy image's `REPLACE_ENV_VARIABLES=TRUE`
mechanism. The `config/velocity.toml` template contains `${CFG_*}` placeholders
that are expanded from environment variables at container startup. The processed
config is written to `/server/velocity.toml` inside the container's persistent
volume.

The forwarding secret is read by Velocity directly from the `VELOCITY_FORWARDING_SECRET`
environment variable (checked before the `forwarding-secret-file`). All backends
must share the same secret.

### Backend Servers

**Paper (survival, creative):** Near-vanilla gameplay. Paper is API-compatible
with vanilla Minecraft — same world format, same gameplay — with async chunk
loading, entity optimization, and native Velocity forwarding support. Velocity
integration is configured via `PATCH_DEFINITIONS`, which patches
`paper-global.yml` at `$.proxies.velocity.*` with the shared forwarding secret.

**NeoForge (modded-survival, modded-creative):** Full mod ecosystem. The
NeoVelocity mod implements the `velocity:player_info` login plugin channel for
NeoForge, enabling modern forwarding. It is installed automatically via
`MODRINTH_PROJECTS=neovelocity` and configured via `PATCH_DEFINITIONS`.

All backends run with `ONLINE_MODE=false` — they trust the proxy's forwarding
data rather than authenticating players directly. `ENFORCE_SECURE_PROFILE=false`
is required because the TCP connection arrives from the proxy, not the player.

**Version management:** Vanilla worlds use `VERSION=LATEST` (auto-upgrades on
restart). Modded worlds use `VERSION_FROM_MODRINTH_PROJECTS=true` — the image
automatically selects the latest Minecraft version that all listed mods support,
preventing mod incompatibility after a Minecraft update.

**Idle pause:** All worlds use `PAUSE_WHEN_EMPTY_SECONDS=300`. When no players
are connected for 5 minutes, the JVM tick loop pauses natively (Minecraft 1.21.2+
feature). No capabilities, daemons, or kernel packet interception required. The
tick loop resumes automatically when a player connects (~1 second delay).

### Systemd Integration

Quadlet is a systemd generator that converts INI-style `.container`, `.volume`,
`.network`, and `.image` files into full systemd service units at daemon-reload
time. The generator injects:

- `Type=notify` + `NotifyAccess=all` (sd-notify integration)
- `KillMode=mixed` (SIGTERM to main process, SIGKILL to cgroup on timeout)
- `Delegate=yes` (cgroup delegation for container sub-cgroups)
- `--cgroups=split` (conmon and container in separate cgroups)
- `--replace --rm` (idempotent restarts, no stale containers)
- `ExecStop` / `ExecStopPost` (force-remove container on stop)
- Dependency injection from `Volume=`, `Network=`, `Image=` references

The backend template `minecraft@.container` is instantiated per world. Systemd
specifier `%i` expands to the instance name (survival, creative, etc.) in
container names, hostnames, log tags, volume names, and environment file paths.

Modded instances use dedicated `.container` files (`minecraft-modded-survival.container`,
`minecraft-modded-creative.container`) with `Image=minecraft-server-java21.image`.
Paper 26.x requires Java 25; NeoForge requires Java 21 (`jdk.crypto.ec` module).
Separate container files allow each server type to reference the correct image
independently.

### Health and Lifecycle

**Two-phase health check:** Phase 1 (startup) checks that the JVM process exists
(`pgrep -f java`). This prevents the ongoing health check from killing the
container during the 30-120 second JVM startup window. After one successful
startup check, Phase 2 (ongoing) uses `mc-health` — an RCON-based server list
ping that validates the server is accepting player connections.

**Notify=healthy:** systemd's `READY=1` signal is sent only after `mc-health`
passes. The service is not considered "active" until the server is actually
serving players. This is required for reliable auto-update rollback detection.

**Graceful stop:** SIGTERM triggers the itzg wrapper to send an RCON `stop`
command. The JVM saves the world and exits cleanly. `StopTimeout` is set to
`STOP_DURATION + STOP_SERVER_ANNOUNCE_DELAY + 5s buffer` to ensure the full
save completes before SIGKILL.

**Auto-update:** `podman auto-update` checks the registry for new image digests.
If a new image is available, it pulls, restarts the unit, and waits for
`READY=1`. If the health check never passes (bad image), it rolls back to the
previous image and restarts again.

**Restart backoff:** On failure, restarts use exponential backoff
(`RestartSec=30` → `RestartMaxDelaySec=300` over 4 steps). After 5 failures in
5 minutes (`StartLimitBurst=5`), the service stops restarting permanently until
manual intervention.

**OOM handling:** `memory.high` throttles the JVM into GC pressure before the
hard limit. If `memory.max` is breached, the kernel OOM-kills the container.
`OOMPolicy=stop` ensures systemd immediately marks the service failed and
triggers `Restart=on-failure`. `memory.oom.group=1` (on backends) ensures atomic
cgroup kill — no partially-dead JVM state.

## File Reference

| File | Purpose |
|------|---------|
| `quadlet/minecraft.network` | Podman bridge network (10.89.100.0/24, DNS enabled) |
| `quadlet/minecraft-server.image` | Vanilla backend image pre-pull (itzg/minecraft-server:java25) |
| `quadlet/minecraft-server-java21.image` | Modded backend image pre-pull (itzg/minecraft-server:java21) |
| `quadlet/minecraft-proxy.image` | Proxy image pre-pull (itzg/mc-proxy:java25) |
| `quadlet/minecraft-proxy.container` | Velocity proxy unit (only published port) |
| `quadlet/minecraft@.container` | Vanilla backend server template (Paper, java25) |
| `quadlet/minecraft-modded-survival.container` | Modded survival (NeoForge, java21, explicit) |
| `quadlet/minecraft-modded-creative.container` | Modded creative (NeoForge, java21, explicit) |
| `env/minecraft-secrets.env.example` | Forwarding secret template (deploy generates real file) |
| `env/minecraft-proxy.env` | Proxy configuration (TYPE, CFG_* vars for velocity.toml) |
| `env/minecraft-survival.env` | Survival world configuration |
| `env/minecraft-creative.env` | Creative world configuration |
| `env/minecraft-modded-survival.env` | Modded survival configuration |
| `env/minecraft-modded-creative.env` | Modded creative configuration |
| `config/velocity.toml` | Velocity config template (${CFG_*} placeholders) |
| `config/patches/paper-velocity.json` | PATCH_DEFINITIONS for Paper velocity support |
| `config/patches/neovelocity.json` | PATCH_DEFINITIONS for NeoForge forwarding (NeoVelocity) |
| `scripts/deploy.sh` | Deployment automation (install + secret generation) |
| `scripts/start.sh` | Fleet start/stop/restart orchestration |
| `scripts/generate-secret.sh` | Forwarding secret generator |

## Configuration Reference

### Secrets

The file `minecraft-secrets.env` is deployed with `0600` permissions and contains
three variables that must all hold the same value:

| Variable | Consumer | Mechanism |
|----------|----------|-----------|
| `MINECRAFT_FORWARDING_SECRET` | Documentation/rotation reference | — |
| `VELOCITY_FORWARDING_SECRET` | Velocity JVM reads via `System.getenv()` | Direct |
| `CFG_VELOCITY_SECRET` | PATCH_DEFINITIONS `${CFG_VELOCITY_SECRET}` expansion | File patching |

Three variables exist because `EnvironmentFile=` does not perform shell variable
expansion. Each consumer reads a differently-named variable through a different
mechanism. All three must be identical. Rotate by editing the file and restarting
all services.

### Resource Limits

| Instance | Memory (container) | memory.high | PidsLimit | CPUWeight | StopTimeout |
|----------|-------------------|-------------|-----------|-----------|-------------|
| proxy | 1g | 900m | 512 | 150 | 30s |
| survival | 5g | 4500m | 4096 | 100 | 130s |
| creative | 5g | 4500m | 4096 | 100 | 130s |
| modded-survival | 7g | 6300m | 8192 | 200 | 190s |
| modded-creative | 7g | 6300m | 8192 | 200 | 190s |

All containers have `memory.swap.max=0` (no swap) and `memory.oom.group=1`
(atomic cgroup kill on OOM). The JVM heap (`MAX_MEMORY` in env files) must be
below the container memory limit to leave room for metaspace and native memory.

## Operations

### Adding a New World

1. Create `env/minecraft-<name>.env` based on an existing env file.
2. For vanilla worlds, the template handles it automatically.
   For modded worlds requiring a different Java version, create an explicit
   `quadlet/minecraft-<name>.container` file referencing the appropriate image.
3. Run `./scripts/deploy.sh` to reinstall.
4. Start: `systemctl --user start minecraft@<name>.service` (template) or
   `systemctl --user start minecraft-<name>.service` (explicit)
5. Add the server to `velocity.toml` template (`[servers]` and `[forced-hosts]`)
   and the corresponding `CFG_SERVER_*` / `CFG_HOST_*` vars to `minecraft-proxy.env`.
6. Restart the proxy: `systemctl --user restart minecraft-proxy.service`

### Updating Images

```bash
podman auto-update
```

This checks registry digests for all containers with `AutoUpdate=registry`. If
a new image is found, it pulls, restarts the service, and waits for the health
check to pass. On failure, it rolls back automatically.

For manual updates:

```bash
podman pull docker.io/itzg/minecraft-server:java25
systemctl --user restart minecraft@survival.service
```

### Rotating the Forwarding Secret

```bash
# Generate new secret
./scripts/generate-secret.sh > ~/.config/containers/systemd/minecraft-secrets.env
chmod 0600 ~/.config/containers/systemd/minecraft-secrets.env

# Restart everything (all services must share the same secret)
systemctl --user restart minecraft-proxy.service
systemctl --user restart minecraft@survival.service
systemctl --user restart minecraft@creative.service
systemctl --user restart minecraft-modded-survival.service
systemctl --user restart minecraft-modded-creative.service
```

### Logs and Debugging

```bash
# Per-instance logs via journal tag
journalctl --user -t minecraft-survival -f
journalctl --user -t minecraft-proxy -f

# Health check status
podman healthcheck run minecraft-proxy
podman healthcheck run minecraft-survival

# Inspect generated systemd unit (dry-run)
QUADLET_UNIT_DIRS=~/.config/containers/systemd \
  /usr/lib/systemd/system-generators/podman-system-generator --user --dryrun

# Validate generated service
systemd-analyze --user --generators=true verify minecraft@survival.service

# Confirm parsed values
systemctl --user show minecraft@survival.service \
  -P MemoryHigh -P MemoryMax -P MemorySwapMax -P OOMPolicy -P CPUWeight
```

## Requirements

- **OS:** Fedora 44+ (kernel ≥ 6.5 for sdnotify attribution via SO_PASSPIDFD)
- **Container runtime:** Podman 5.x+ (Quadlet generator, CgroupConf=, pasta networking)
- **Init:** systemd 254+ (RestartSteps=, Delegate=yes .control subcgroup, OOMPolicy=)
- **Session:** `loginctl enable-linger` enabled for the deploying user
- **RAM:** 16Gi minimum for proxy + 2 vanilla worlds; 32Gi recommended for all 4 worlds simultaneous
- **CPU:** 4+ cores (8 threads recommended for modded worlds under load)
- **Storage:** 64Gi+ root disk (container images, world data in ~/minecraft/)

Built on [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server),
[itzg/docker-bungeecord](https://github.com/itzg/docker-bungeecord) (mc-proxy),
and [PaperMC/Velocity](https://github.com/PaperMC/Velocity).
