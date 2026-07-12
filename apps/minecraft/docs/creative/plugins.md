# Creative World — Paper 26.x Plugins

Sandbox building environment. Peaceful difficulty, flight enabled, command
blocks enabled, max build height 1024. FAWE for large-scale construction.

## Installed Plugins

Modrinth plugins (installed automatically via `MODRINTH_PROJECTS`):

| Plugin | Purpose |
|--------|---------|
| EssentialsX | Homes, warps, /tpa, spawn |
| CoreProtect | Block logging, undo for accidents |
| LibertyBans | Ban/mute/kick management |
| Chunky | World pre-generation |
| GSit | Sit on stairs, slabs, carpets |
| FancyHolograms | Display entity holograms for signage |
| BlueMap | 3D web map of builds |
| FastAsyncWorldEdit | Async WorldEdit — non-blocking large operations |
| SleepSkipUltra | Smooth night skip |

Hangar plugins (installed by `scripts/hangar-download.sh` during deploy):

| Plugin | Purpose |
|--------|---------|
| ChestSort | Shift-click to sort containers |

## Performance Patches

Applied via `PATCH_DEFINITIONS=/config/creative/patches`:

| Patch | Target | Settings |
|-------|--------|----------|
| paper-velocity.json | paper-global.yml | Velocity modern forwarding enabled |
| paper-performance.json | paper-world-defaults.yml | ALTERNATE_CURRENT redstone, chunk unload delay 30s, prevent moving into unloaded chunks, autosave 12 chunks/tick, optimize explosions, disable pathfinding on block update, fix items merging through walls, disable world ticking when empty |

Anti-xray is not applied — creative mode has no ore scarcity.
Spigot entity tuning is not applied — peaceful mode spawns no hostile mobs.

## Resource Allocation

| Setting | Value |
|---------|-------|
| Container memory | 12g |
| JVM heap | 10G |
| memory.high | 10800M |
| View distance | 16 chunks |
| Simulation distance | 8 chunks |

View distance is set to 16 (vs 12 for survival) so builders can see
their constructions from a distance. Peaceful mode with no hostile mobs
reduces tick pressure, allowing the higher view distance without TPS impact.

## Player Requirements

None. All plugins are server-side. Join with vanilla Minecraft Java Edition.
ViaVersion on the proxy handles version compatibility.
