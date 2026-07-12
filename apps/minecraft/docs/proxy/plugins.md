# Velocity Proxy Plugins

All proxy-level plugins apply to every world. Players interact with these
transparently — no client configuration required.

## Plugins

| Plugin | Purpose | Source | Version |
|--------|---------|--------|---------|
| ViaVersion | Newer MC clients connect to older backends | [GitHub](https://github.com/ViaVersion/ViaVersion) | latest |
| ViaBackwards | Older MC clients connect to newer backends | [GitHub](https://github.com/ViaVersion/ViaBackwards) | latest |
| Geyser | Bedrock Edition clients connect through the proxy | [GitHub](https://github.com/GeyserMC/Geyser) | latest |
| Floodgate | Bedrock auth without requiring a Java account | [GitHub](https://github.com/GeyserMC/Floodgate) | latest |
| LuckPerms | Unified permissions across all worlds | [GitHub](https://github.com/LuckPerms/LuckPerms) | latest |
| Maintenance | Per-server or fleet-wide maintenance mode | [GitHub](https://github.com/kennytv/Maintenance) | latest |

## Player Requirements

None. All proxy plugins are server-side only.

## Notes

- LuckPerms runs on both Velocity and each Paper backend for per-world
  permission groups.
- Geyser resource packs for Bedrock players are placed in
  `config/Geyser-Velocity/packs/` as `.mcpack` or `.zip` files.
- LibertyBans on Velocity requires SignedVelocity for mute enforcement
  with 1.19+ chat signing. Evaluate whether to install LibertyBans on
  Velocity or on each Paper backend independently.
