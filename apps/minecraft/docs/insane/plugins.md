# Insane World — NeoForge 1.21.11 Mods

Creative mode with NeoForge performance mods. Peaceful difficulty, flight,
command blocks, max build height 1024. Disabled by default
(`FLEET_INSANE=false`); requires VM scaling to 52Gi.

## Installed Mods

All mods installed automatically via `MODRINTH_PROJECTS` with
`MODRINTH_PROJECTS_DEFAULT_VERSION_TYPE=alpha`.

### Performance (server-side, no client install)

| Mod | Purpose |
|-----|---------|
| Lithium | Tick optimization |
| Spark | Performance profiler |
| FerriteCore | Memory optimization |
| ModernFix-mVUS | Startup time and memory optimization |
| C2ME | Parallel chunk generation |
| Alternate Current | Redstone engine replacement |
| Chunky | World pre-generation |

### Infrastructure (server-side, no client install)

| Mod | Purpose |
|-----|---------|
| NeoVelocity | Velocity modern forwarding for NeoForge |
| BlueMap | 3D web map |

Terralith is not included — creative mode builds from scratch, worldgen
overhaul adds no value.

## Performance Patches

Applied via `PATCH_DEFINITIONS=/config/insane/patches`:

| Patch | Target | Settings |
|-------|--------|----------|
| neovelocity.json | neovelocity-common.toml | Forwarding secret injection |

## Resource Allocation

| Setting | Value |
|---------|-------|
| Container memory | 12g |
| JVM heap | 7G |
| memory.high | 10800M |
| View distance | 12 chunks |
| Simulation distance | 8 chunks |

## Player Requirements

NeoForge 1.21.11 on the client. All mods listed above are server-side —
the client needs only a matching NeoForge version with no additional mods.
