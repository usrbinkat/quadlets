# Survival World — Paper 26.x Plugins

Near-vanilla survival with quality-of-life plugins. Normal difficulty,
PvP enabled, grief protection via land claims. Default world for
`play.braincraft.io`.

## Installed Plugins

Modrinth plugins (installed automatically via `MODRINTH_PROJECTS`):

| Plugin | Purpose |
|--------|---------|
| EssentialsX | Homes, warps, /tpa, spawn, kits |
| CoreProtect | Block logging, rollback, anti-grief forensics |
| GriefPrevention | Player land claims with golden shovel |
| LibertyBans | Ban/mute/kick management |
| Chunky | World pre-generation |
| GSit | Sit on stairs, slabs, carpets |
| FancyHolograms | Display entity holograms for signage |
| BlueMap | 3D web map |
| ToolStats | Tracks blocks mined, kills, ownership on tools |
| WorldEdit | Region select, copy, paste, fill |
| SleepSkipUltra | Smooth night skip with sunrise transition |

Hangar plugins (installed by `scripts/hangar-download.sh` during deploy):

| Plugin | Purpose |
|--------|---------|
| ChestSort | Shift-click to sort containers |

## Performance Patches

Applied via `PATCH_DEFINITIONS=/config/survival/patches`:

| Patch | Target | Settings |
|-------|--------|----------|
| paper-velocity.json | paper-global.yml | Velocity modern forwarding enabled |
| paper-antixray.json | paper-world-defaults.yml | Anti-xray engine mode 1, max height 64 |
| paper-performance.json | paper-world-defaults.yml | ALTERNATE_CURRENT redstone, chunk unload delay 30s, prevent moving into unloaded chunks, autosave 12 chunks/tick, optimize explosions, disable pathfinding on block update, fix items merging through walls, disable world ticking when empty |
| spigot-performance.json | spigot.yml | Entity activation range animals 24, merge radius exp 3.0, merge radius item 2.5 |

## Resource Allocation

| Setting | Value |
|---------|-------|
| Container memory | 12g |
| JVM heap | 10G |
| memory.high | 10800M |
| View distance | 12 chunks |
| Simulation distance | 8 chunks |

## Player Requirements

None. All plugins are server-side. Join with vanilla Minecraft Java Edition.
ViaVersion on the proxy handles version compatibility.
