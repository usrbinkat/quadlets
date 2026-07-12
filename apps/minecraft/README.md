# Minecraft Quadlet Fleet

Multi-world Minecraft Java Edition server fleet deployed as rootless Podman
containers via systemd Quadlet units. Players connect to a single address
and switch between worlds through the Velocity proxy.

## Architecture

```
Internet
  |
  | TCP :25565
  v
+----------------------------------------------------------------------+
| VM: Fedora 44, rootless Podman, systemd user session (linger)        |
|                                                                      |
|  enp1s0 :25565                                                       |
|    |                                                                 |
|    v rootlessport (userspace TCP proxy)                              |
|    |                                                                 |
|    v minecraft bridge (10.89.100.0/24, aardvark-dns)                 |
|    |                                                                 |
|    +-- minecraft-proxy ---------- Velocity JVM                       |
|    |     online-mode=true         Mojang auth, HmacSHA256 forwarding |
|    |     :25565 (only published port)                                |
|    |       |                                                         |
|    |       +-- minecraft-survival --- Paper 26.x, survival, normal   |
|    |       +-- minecraft-creative --- Paper 26.x, creative, peaceful |
|    |       +-- minecraft-modded ----- NeoForge 1.21.11, hard         |
|    |       +-- minecraft-insane ----- NeoForge 1.21.11, peaceful     |
|    |           (backends: online-mode=false, no published ports)      |
|    |                                                                 |
|    +-- DNS: container names resolve via aardvark-dns on bridge       |
+----------------------------------------------------------------------+
```

## Worlds

| World | Type | Mode | Difficulty | Default | Connect Via |
|-------|------|------|------------|---------|-------------|
| survival | Paper 26.x | survival | normal | enabled | `survival.play.braincraft.io` |
| creative | Paper 26.x | creative | peaceful | enabled | `creative.play.braincraft.io` |
| modded | NeoForge 1.21.11 | survival | hard | disabled | `modded.play.braincraft.io` |
| insane | NeoForge 1.21.11 | creative | peaceful | disabled | `insane.play.braincraft.io` |

Enabled/disabled state is controlled by `FLEET_*` variables in `.env.example`
(defaults) and `.env` (user overrides). Disabled worlds are not started, not
routed by the proxy, and not auto-started on boot.

All worlds share the same whitelist, operator list, and player authentication.
Player UUID, skin, and cape are preserved across worlds via Velocity modern
forwarding.

## Resource Allocation

| Instance | Container | Heap | memory.high | View | Sim |
|----------|-----------|------|-------------|------|-----|
| proxy | 2g | 512m | 1800M | - | - |
| survival | 12g | 10G | 10800M | 12 | 8 |
| creative | 12g | 10G | 10800M | 16 | 8 |
| modded | 12g | 7G | 10800M | 8 | 6 |
| insane | 12g | 7G | 10800M | 12 | 8 |

Paper worlds allocate 2g container overhead for metaspace, netty, and plugins.
NeoForge worlds allocate 5g container overhead to accommodate mixin/class
loading bootstrap peak and AlwaysPreTouch heap page allocation at JVM start.

All containers enforce `memory.swap.max=0` (no swap) and `memory.oom.group=1`
(atomic cgroup kill on OOM).

**VM sizing:**

| Configuration | VM RAM |
|---------------|--------|
| proxy + survival + creative | 28Gi |
| proxy + all 4 worlds | 52Gi |

## Quick Start

```bash
git clone https://github.com/usrbinkat/quadlets ~/quadlets
cd ~/quadlets/apps/minecraft

# Optional: customize fleet settings
cp .env.example .env
# edit .env to change FLEET_* flags, memory, timeouts

./scripts/deploy.sh --generate-secret
./scripts/enable.sh all
```

## Fleet Configuration

`.env.example` provides defaults. Copy to `.env` to override:

```bash
cp .env.example .env
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `FLEET_SURVIVAL` | `true` | Enable survival world |
| `FLEET_CREATIVE` | `true` | Enable creative world |
| `FLEET_MODDED` | `false` | Enable modded world |
| `FLEET_INSANE` | `false` | Enable insane world |
| `FLEET_*_MEMORY` | `12g`/`2g` | Container memory limit per world |
| `FLEET_STARTUP_TIMEOUT` | `180` | Seconds to wait for health check |
| `FLEET_POLL_INTERVAL` | `5` | Seconds between health polls |

Scripts source `.env.example` first (defaults), then `.env` (overrides).
No dependency on direnv — cloud-init and interactive use both work.

## Player Guide

Add to Minecraft server list:

```
play.braincraft.io              (connects to survival by default)
survival.play.braincraft.io
creative.play.braincraft.io
modded.play.braincraft.io       (NeoForge 1.21.11 client required)
insane.play.braincraft.io       (NeoForge 1.21.11 client required)
```

Port 25565 (default). Switch worlds in-game:

```
/server survival
/server creative
/server modded
/server insane
```

Only enabled worlds are routable. ViaVersion on the proxy handles
Java Edition version compatibility. Geyser handles Bedrock Edition.

## How It Works

### Velocity Proxy

Single entry point for all player connections. Handles Mojang authentication
(`online-mode=true`), forwards authenticated player data to backends using
modern forwarding — HmacSHA256-signed payload on the `velocity:player_info`
login plugin channel.

`deploy.sh` generates `velocity.toml` from `config/velocity.toml.template`,
including only `FLEET_*`-enabled worlds in `[servers]` and `[forced-hosts]`.
The itzg/mc-proxy image expands `${CFG_*}` placeholders from environment
variables at container startup.

### Backend Servers

**Paper (survival, creative):** Near-vanilla. Paper provides async chunk
loading, entity optimization, and native Velocity forwarding. Per-world
`PATCH_DEFINITIONS` configure velocity integration, anti-xray (survival only),
and performance tuning (ALTERNATE_CURRENT redstone, chunk unload delay,
autosave throttling, explosion optimization).

**NeoForge (modded, insane):** NeoVelocity mod implements the
`velocity:player_info` login plugin channel. Installed via
`MODRINTH_PROJECTS=neovelocity`, configured via `PATCH_DEFINITIONS`.

All backends: `ONLINE_MODE=false` (trust proxy forwarding),
`ENFORCE_SECURE_PROFILE=false` (connection from proxy, not player).

**Version management:** Paper worlds use `VERSION=LATEST`. NeoForge worlds
pin `VERSION=1.21.11` — the specific Minecraft version where all listed mods
have compatible NeoForge builds.

**Idle pause:** `PAUSE_WHEN_EMPTY_SECONDS=300` pauses the tick loop natively
(Minecraft 1.21.2+) when no players are connected for 5 minutes.

### Systemd Integration

Quadlet generates systemd service units from `.container`/`.network`/`.image`
files at daemon-reload time. `.target` is not a supported Quadlet extension —
`minecraft.target` lives in `~/.config/systemd/user/` separately.

Boot auto-start chain: `default.target` → `minecraft.target` →
`minecraft-proxy.service` → backends (via `BindsTo=` + `After=`).
Enabled worlds get `WantedBy=minecraft.target` via deploy.sh-generated
`20-fleet.conf` drop-ins. Disabled worlds have no `[Install]` drop-in and
are not pulled into the boot transaction.

Backend dependency on proxy: `BindsTo=minecraft-proxy.service` stops
backends when the proxy crashes (not just on explicit stop — `PartOf=`
only propagates explicit stop/restart, not unexpected deactivation).
`After=minecraft-proxy.service` ensures backends wait for proxy `READY=1`
before starting.

Anti-stampede: staggered `RestartSec=` per instance (30/35/40/45s) via
`30-restart.conf` drop-ins. `RestartRandomizedDelaySec=` requires
systemd v262; the VM runs v259.

Paper worlds use the `minecraft@.container` template (systemd `%i` specifier).
NeoForge worlds use explicit container files to reference the java21 image
(Paper 26.x requires Java 25; NeoForge requires Java 21 for `jdk.crypto.ec`).

### Health and Lifecycle

Two-phase health check: startup phase (`pgrep -f java`) prevents premature
kill during JVM bootstrap. Ongoing phase (`mc-health` RCON ping) validates
the server accepts player connections. `Notify=healthy` sends `READY=1` only
after `mc-health` passes.

Graceful stop: SIGTERM to conmon → forwarded to container PID 1 (itzg
entrypoint) → RCON `stop` → world save → JVM exits. Quadlet generates
`ExecStop=podman rm -v -f -i` (not `podman stop`); `podman rm -f` on a
running container calls `ctr.stop(StopTimeout)` internally.
`TimeoutStopSec=` covers the full chain including `ExecStopPost=`.

Restart backoff: `RestartSec=30` → `RestartMaxDelaySec=300` over 4 steps
(30→53→95→169→300s). After 5 failures in 5 minutes (`StartLimitBurst=5`
in `StartLimitIntervalSec=300`), the service stops permanently until
`systemctl --user reset-failed`.

OOM handling: `OOMPolicy=kill` instructs the kernel to kill all processes
in the cgroup atomically via `memory.oom.group=1`. This overrides the
`Delegate=yes` implicit default of `OOM_CONTINUE`. Both `stop` and `kill`
result in `oom-kill` failed state and trigger `Restart=on-failure`.
`ManagedOOMMemoryPressure=kill` enables proactive `systemd-oomd`
intervention before the kernel OOM killer fires.

Swap: `memory.swap.max=0` is set at both cgroup layers — `MemorySwapMax=0`
in `[Service]` (service cgroup) and `--cgroup-conf=memory.swap.max=0` via
`PodmanArgs=` (container sub-cgroup). cgroup v2 `memory.swap.max` is not
inherited by sub-cgroups; without the `PodmanArgs=` layer, Podman's
`LimitToSwap()` sets implicit swap equal to `Memory=`.

## File Reference

| File | Purpose |
|------|---------|
| `.env.example` | Fleet configuration defaults (FLEET_* flags, memory, timeouts) |
| `.envrc` | direnv integration — sources .env.example then .env |
| `config/velocity.toml.template` | Velocity config template (${CFG_*} placeholders) |
| `config/velocity.toml` | Generated by deploy.sh from template + FLEET_* flags |
| `config/patches/` | Shared patch files (symlink targets) |
| `config/survival/patches/` | Survival-specific patches (velocity, antixray, performance, spigot) |
| `config/creative/patches/` | Creative-specific patches (velocity, performance; no antixray) |
| `config/modded/patches/` | Modded patches (neovelocity) |
| `config/insane/patches/` | Insane patches (neovelocity) |
| `quadlet/minecraft@.container` | Paper backend template (java25) |
| `quadlet/minecraft-modded.container` | NeoForge modded (java21) |
| `quadlet/minecraft-insane.container` | NeoForge insane (java21) |
| `quadlet/minecraft-proxy.container` | Velocity proxy (only published port) |
| `quadlet/minecraft.network` | Podman bridge network (10.89.100.0/24) |
| `env/minecraft-*.env` | Per-world environment configuration |
| `env/minecraft-secrets.env.example` | Forwarding secret template |
| `systemd/minecraft.target` | Fleet grouping unit (installed to ~/.config/systemd/user/) |
| `scripts/deploy.sh` | Install units, generate drop-ins/velocity.toml, download plugins |
| `scripts/enable.sh` | Start/stop fleet services with health verification |
| `scripts/generate-secret.sh` | Generate HmacSHA256 forwarding secret |
| `scripts/hangar-download.sh` | Download Hangar plugins for Paper worlds |

## Configuration Reference

### Secrets

`minecraft-secrets.env` is deployed with `0600` permissions and contains
three variables that must all hold the same value:

| Variable | Consumer | Mechanism |
|----------|----------|-----------|
| `MINECRAFT_FORWARDING_SECRET` | Documentation/rotation reference | — |
| `VELOCITY_FORWARDING_SECRET` | Velocity JVM reads via `System.getenv()` | Direct |
| `CFG_VELOCITY_SECRET` | PATCH_DEFINITIONS `${CFG_VELOCITY_SECRET}` expansion | File patching |

Three variables exist because `EnvironmentFile=` does not perform shell
variable expansion. Each consumer reads a differently-named variable through
a different mechanism. All three must be identical.

### Systemd Generator

Quadlet injects into each generated service unit:

- `Type=notify` + `NotifyAccess=all` (sd-notify integration)
- `KillMode=mixed` (SIGTERM to main process, SIGKILL to cgroup on timeout)
- `Delegate=yes` (cgroup delegation for container sub-cgroups)
- `--cgroups=split` (conmon and container in separate cgroups)
- `--replace --rm` (idempotent restarts, no stale containers)
- `ExecStop=podman rm -v -f -i <name>` (force-remove, not `podman stop`)
- `ExecStopPost=-podman rm -v -f -i <name>` (cleanup if conmon killed)
- Dependency injection from `Volume=`, `Network=`, `Image=` references

## Operations

### Enabling/Disabling Worlds

```bash
# Edit .env to change FLEET_* flags
vim .env

# Redeploy (regenerates velocity.toml, enables/disables systemd units)
./scripts/deploy.sh

# Restart fleet
./scripts/enable.sh all
```

### Starting a Single World

```bash
./scripts/enable.sh survival
./scripts/enable.sh insane    # ignores FLEET_* flag, starts unconditionally
```

### Rotating the Forwarding Secret

```bash
./scripts/generate-secret.sh > ~/.config/containers/systemd/minecraft-secrets.env
chmod 0600 ~/.config/containers/systemd/minecraft-secrets.env
./scripts/enable.sh all
```

### Adding a New World

1. Create `env/minecraft-<name>.env` based on an existing env file.
2. Create `config/<name>/patches/` with symlinks to shared patches and any
   world-specific patches.
3. For Paper worlds, the `minecraft@.container` template handles it. For
   NeoForge worlds requiring java21, create an explicit
   `quadlet/minecraft-<name>.container` referencing `minecraft-server-java21.image`
   with `BindsTo=minecraft-proxy.service`, `After=minecraft-proxy.service`,
   `Wants=minecraft-proxy.service` in `[Unit]`.
4. Add `FLEET_<NAME>=false` and `FLEET_<NAME>_MEMORY=12g` to `.env.example`.
5. Add `CFG_SERVER_<NAME>` and `CFG_HOST_<NAME>` to `minecraft-proxy.env`.
6. Add the server and forced-host entries to `config/velocity.toml.template`.
7. Add the world to `DROPIN_MAP` and `RESTART_SEC` in `deploy.sh`.
8. Run `./scripts/deploy.sh` to install.

### Updating Images

```bash
podman auto-update
```

Checks registry digests for all containers with `AutoUpdate=registry`. Pulls
new images, restarts units, waits for health check. Rolls back automatically
on health check failure.

Manual update:

```bash
podman pull docker.io/itzg/minecraft-server:java25
systemctl --user restart minecraft@survival.service
```

### Logs and Debugging

```bash
# Per-instance logs
journalctl --user -t minecraft-survival -f
journalctl --user -t minecraft-proxy -f

# Health check
podman healthcheck run minecraft-proxy
podman healthcheck run minecraft-survival

# Inspect generated systemd unit
QUADLET_UNIT_DIRS=~/.config/containers/systemd \
  /usr/lib/systemd/system-generators/podman-system-generator --user --dryrun

# Validate generated service
systemd-analyze --user --generators=true verify minecraft@survival.service

# Confirm parsed resource values
systemctl --user show minecraft@survival.service \
  -P MemoryHigh -P MemoryMax -P MemorySwapMax -P OOMPolicy -P CPUWeight
```

## Requirements

- **OS:** Fedora 44+ (kernel >= 6.5)
- **Container runtime:** Podman 5.x+
- **Init:** systemd 259+ (RestartSteps=, OOMPolicy=kill, ManagedOOMMemoryPressure=)
- **Session:** `loginctl enable-linger` enabled
- **RAM:** 28Gi for proxy + 2 Paper worlds; 52Gi for all 4 worlds
- **CPU:** 4+ cores
- **Storage:** 64Gi+ root disk

Built on [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server),
[itzg/docker-bungeecord](https://github.com/itzg/docker-bungeecord) (mc-proxy),
and [PaperMC/Velocity](https://github.com/PaperMC/Velocity).
