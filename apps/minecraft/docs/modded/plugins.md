# Modded World — NeoForge 1.21.11 Mods

Enhanced survival with performance mods and terrain overhaul. Hard difficulty.
Disabled by default (`FLEET_MODDED=false`); requires VM scaling to 52Gi.

## Installed Mods

All mods installed automatically via `MODRINTH_PROJECTS` with
`MODRINTH_PROJECTS_DEFAULT_VERSION_TYPE=alpha` (C2ME publishes alpha-only
builds for 1.21.11).

### Performance (server-side, no client install)

| Mod | Purpose |
|-----|---------|
| Lithium | Tick optimization — physics, AI, block ticks |
| Spark | Performance profiler |
| FerriteCore | Memory optimization |
| ModernFix-mVUS | Startup time and memory optimization |
| C2ME | Parallel chunk generation across threads |
| Alternate Current | Redstone engine replacement (95% less CPU) |
| Chunky | World pre-generation |

### Infrastructure (server-side, no client install)

| Mod | Purpose |
|-----|---------|
| NeoVelocity | Velocity modern forwarding for NeoForge |
| BlueMap | 3D web map |

### Content (server-side datapack, no client install)

| Mod | Purpose |
|-----|---------|
| Terralith | Worldgen overhaul, 95+ biomes via vanilla block textures |

## Performance Patches

Applied via `PATCH_DEFINITIONS=/config/modded/patches`:

| Patch | Target | Settings |
|-------|--------|----------|
| neovelocity.json | neovelocity-common.toml | Forwarding secret injection |

## Resource Allocation

| Setting | Value |
|---------|-------|
| Container memory | 12g |
| JVM heap | 7G |
| memory.high | 10800M |
| View distance | 8 chunks |
| Simulation distance | 6 chunks |

5g container overhead accommodates NeoForge mixin/class loading bootstrap
peak and AlwaysPreTouch heap page allocation at JVM start.

## Player Requirements

NeoForge 1.21.11 on the client. All mods listed above are server-side —
the client needs only a matching NeoForge version with no additional mods.
