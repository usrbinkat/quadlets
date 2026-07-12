# Velocity Proxy Plugins

Proxy-level plugins apply to all worlds. The proxy is the single entry point
for all player connections — it handles Mojang authentication and routes
players to backend worlds.

## Installed Plugins

Modrinth plugins (installed automatically via `MODRINTH_PROJECTS`):

| Plugin | Purpose |
|--------|---------|
| ViaVersion | Newer MC clients connect to older backends |
| ViaBackwards | Older MC clients connect to newer backends |
| LuckPerms | Unified permission groups across all worlds |
| Maintenance | Per-server or fleet-wide maintenance mode |

Direct download plugins (installed via `PLUGINS` env var):

| Plugin | Purpose | Source |
|--------|---------|--------|
| Geyser 2.11.0 | Bedrock Edition clients connect through the proxy | GeyserMC download API |
| Floodgate | Bedrock auth without requiring a Java account | GeyserMC download API |

Geyser and Floodgate are downloaded from the GeyserMC API, not Modrinth.
Modrinth only has beta builds for the Velocity platform, and those builds
target older Velocity API versions incompatible with Velocity 4.0.0-SNAPSHOT.

## Resource Allocation

| Setting | Value |
|---------|-------|
| Container memory | 2g |
| JVM heap | 512m |
| memory.high | 1800M |

## Player Requirements

None. All proxy plugins are server-side.
