# BrainCraft Minecraft — Player Guide

Welcome to BrainCraft. This guide covers everything a player needs to
connect, set up their client, and use the server features.

## Server Addresses

Add any of these to your Minecraft Java Edition server list. All use
port 25565 (default — no port needed).

| Address | World |
|---------|-------|
| `play.braincraft.io` | Survival (default) |
| `survival.play.braincraft.io` | Survival |
| `creative.play.braincraft.io` | Creative |

Once connected, switch worlds at any time:

```
/server survival
/server creative
```

Your inventory, location, and progress are separate per world. Your
identity (skin, cape, UUID) follows you everywhere.

## Worlds

### Survival

Faithful vanilla Minecraft with quality-of-life improvements. Normal
difficulty, PvP enabled. The main world — stakes matter here.

- Land claims protect your builds from grief
- Block logging tracks who placed or broke every block
- Homes, warps, and teleports for navigation
- Right-click harvest for crops
- Auto-sort for chests
- Tool tracking shows blocks mined, mobs killed, and who crafted each tool
- 3D web map of the world (BlueMap)

### Creative

Sandbox building environment. Peaceful difficulty, flight enabled,
command blocks enabled, max build height 1024. The art studio.

- FastAsyncWorldEdit for large-scale construction (`//wand`, `//set`, `//copy`)
- No land claims — open canvas
- No hostile mobs
- View distance 16 chunks — see your builds from far away
- 3D web map (BlueMap)

## Client Setup

The server runs Paper 26.1.2 (vanilla). No mod loader is required on
the client — you can join with the stock Minecraft launcher. However,
client-side mods dramatically improve performance and visuals.

### Recommended: Prism Launcher with Fabric

Prism Launcher is a free, open-source Minecraft launcher that supports
mod management. Download it from https://prismlauncher.org.

#### Step 1: Add Your Account

1. Open Prism Launcher
2. Top-right → Accounts → Add Microsoft
3. Log in with the Microsoft/Xbox account that owns Minecraft
4. Close the browser tab after authentication succeeds

#### Step 2: Create an Instance

1. Click **Add Instance**
2. Name: `BrainCraft`
3. Select **Vanilla** on the left, choose version **26.1.2**
4. Click **Fabric** on the left — it auto-selects the latest Fabric loader
5. Click **OK**

#### Step 3: Java Settings

1. Right-click the instance → **Edit** → **Settings** → **Java**
2. Check **Java installation** and point it to Java 21
3. Set **Minimum memory** and **Maximum memory** to `8192 MB`
4. In **JVM arguments**, add: `-XX:+UseZGC -XX:+ZGenerational`

ZGC eliminates garbage collection stutter on modern hardware.

#### Step 4: Install Mods

1. Right-click the instance → **Edit** → **Mods** → **Download Mods**
2. Select **Modrinth** as the source
3. Search and select each mod below, then click **Review and Confirm**

Prism auto-downloads dependencies (Fabric API, Cloth Config, etc.).

**Performance:**

| Mod | What it does |
|-----|-------------|
| Sodium | Rendering engine rewrite, 3-5x FPS improvement |
| Lithium | Game logic optimization (physics, AI, ticks) |
| FerriteCore | Reduces RAM usage |
| ModernFix | Faster startup, lower memory |
| C2ME | Multithreaded chunk loading |
| Nvidium | Nvidia GPU-specific rendering (if you have an Nvidia card) |
| ImmediatelyFast | Faster HUD, entity, and text rendering |
| EntityCulling | Skips rendering entities you can't see |

**Visuals:**

| Mod | What it does |
|-----|-------------|
| Iris | Shader support (works alongside Sodium) |
| LambDynamicLights | Held torches and dropped items emit light |
| Continuity | Connected glass and bookshelf textures |
| Zoomify | Hold a key to zoom in (like binoculars) |
| Bobby | Caches chunks beyond the server's view distance on your machine |

**HUD and Information:**

| Mod | What it does |
|-----|-------------|
| Xaero's Minimap | Corner minimap showing terrain and players |
| Xaero's World Map | Full-screen world map (press M) |
| Jade | Shows what block or entity you're looking at |
| Mod Menu | In-game settings screen for all installed mods |
| AppleSkin | Shows saturation and exhaustion values on the hunger bar |
| ShulkerBoxTooltip | Hover over a shulker box to see its contents |

**Required Libraries** (install these if not auto-resolved):

| Mod | Needed by |
|-----|-----------|
| Fabric API | Almost everything |
| Indium | Rendering compatibility for Sodium |
| Cloth Config | Config screens for many mods |

#### Step 5: Optional — Shaders

After Iris is installed, download a shader pack:

1. Go to https://modrinth.com/shaders
2. Download **Complementary Reimagined** or **Complementary Unbound**
3. In Prism: Edit → Shader Packs → drag the zip file in
4. In-game: Options → Video Settings → Shader Packs → select it

#### Step 6: Video Settings

After first launch, adjust these in Options → Video Settings:

| Setting | Value |
|---------|-------|
| Render Distance | 32 chunks (Bobby caches beyond server's limit) |
| VSync | Off (use Sodium's frame limiter instead) |
| Graphics | Fancy or Fabulous |
| Entity Distance | 500% |

#### Step 7: Add Servers

1. In-game: Multiplayer → Add Server
2. Server Address: `survival.play.braincraft.io`
3. Repeat for `creative.play.braincraft.io`

One instance works for both worlds — same version, same client mods.

### Alternative: Stock Launcher

If you prefer not to use mods, the stock Minecraft launcher works.
Create a 26.1.2 installation and connect directly. All server
features work without client mods.

### Bedrock Edition

Bedrock Edition players (Xbox, PlayStation, Switch, mobile, Windows 10)
can connect through Geyser:

- Address: `play.braincraft.io`
- Port: `19132`

No Java account required — Floodgate handles Bedrock authentication.
Some visual differences exist between Java and Bedrock rendering.

## Server Commands

### Navigation (EssentialsX)

| Command | What it does |
|---------|-------------|
| `/sethome <name>` | Save your current location as a home |
| `/home <name>` | Teleport to a saved home |
| `/delhome <name>` | Delete a saved home |
| `/homes` | List all your homes |
| `/tpa <player>` | Request to teleport to a player |
| `/tpaccept` | Accept a teleport request |
| `/tpdeny` | Deny a teleport request |
| `/spawn` | Teleport to world spawn |
| `/back` | Return to your last location (after death or teleport) |
| `/msg <player> <message>` | Private message a player |
| `/r <message>` | Reply to the last private message |

### World Switching

| Command | What it does |
|---------|-------------|
| `/server survival` | Switch to the survival world |
| `/server creative` | Switch to the creative world |
| `/server` | Show available worlds |

### Land Claims (Survival — GriefPrevention)

Protect your builds from other players. Claims use a golden shovel.

| Action | How |
|--------|-----|
| Create a claim | Hold a golden shovel, right-click two opposite corners |
| Expand a claim | Right-click a corner with the golden shovel, right-click the new corner |
| Remove a claim | Stand inside it, `/abandonclaim` |
| Trust a player | `/trust <player>` (full build access) |
| Container trust | `/containertrust <player>` (open chests only) |
| Access trust | `/accesstrust <player>` (use buttons, doors) |
| Remove trust | `/untrust <player>` |
| See claim borders | Right-click the ground with a stick |
| Check claim blocks | `/claimslist` |

New players start with 100 claim blocks. You earn more by playing.

### Block Logging (CoreProtect)

Every block placement, removal, and container access is logged.

| Command | What it does |
|---------|-------------|
| `/co i` | Toggle inspector mode — click any block to see its history |
| `/co l` | Lookup block changes near you |
| `/co rollback r:5 t:1h` | Undo all changes within 5 blocks in the last hour |
| `/co restore r:5 t:1h` | Redo rolled-back changes |

Inspector mode (`/co i`) is the most useful — click any block to see
who placed or broke it and when.

### Building Tools

**WorldEdit (Survival):**

| Command | What it does |
|---------|-------------|
| `//wand` | Get the selection wand (wooden axe) |
| `//pos1` | Set position 1 at your location |
| `//pos2` | Set position 2 at your location |
| `//set <block>` | Fill selection with a block |
| `//replace <from> <to>` | Replace blocks in selection |
| `//copy` | Copy selection to clipboard |
| `//paste` | Paste clipboard at your location |
| `//undo` | Undo last operation |

**FastAsyncWorldEdit (Creative):**

Same commands as WorldEdit but operations run asynchronously — the
server doesn't lag during large edits. Additional FAWE commands:

| Command | What it does |
|---------|-------------|
| `//br sphere <block> <radius>` | Brush tool for painting blocks |
| `//br smooth` | Smooth terrain brush |
| `//schematic save <name>` | Save selection as a schematic file |
| `//schematic load <name>` | Load a schematic |

### Utility

| Command | What it does |
|---------|-------------|
| `/sit` | Sit on the block you're standing on (GSit) |
| `/co i` | Toggle block inspector (CoreProtect) |
| `/bluemap` | BlueMap status |
| `/chunky start` | Start chunk pre-generation (operator only) |
| `/spark tps` | Show server TPS (ticks per second) |
| `/spark profiler` | Start performance profiler (operator only) |

### Moderation

| Command | What it does |
|---------|-------------|
| `/ban <player> <reason>` | Ban a player (LibertyBans) |
| `/unban <player>` | Unban a player |
| `/mute <player> <duration>` | Mute a player |
| `/kick <player> <reason>` | Kick a player |

## Whitelisted Players

The server is whitelisted. Current players:

- usrbinkat
- gardengnomegal8
- Sgt_Ramirez / SgtRemeriz / Sgt_Remeriz
- microbeast
- H0WZ0R

To add a player, contact the server operator (usrbinkat).

## Performance Tips

### Client FPS

- Install Sodium — single biggest FPS improvement
- Lower render distance if FPS is still low (16 is a good balance)
- Disable shaders if FPS drops below 60
- Bobby caches chunks locally — first visit is slower, revisits are instant

### Reducing Lag

- The server uses ALTERNATE_CURRENT redstone — redstone builds run
  95% more efficiently than vanilla
- Chunk pre-generation (Chunky) eliminates lag when exploring new terrain
- The server pauses when no players are online (saves resources)
- If you experience rubber-banding, check your internet connection —
  the server prevents walking into unloaded chunks

## Troubleshooting

### "Not logged into your Minecraft account"

Your Minecraft session expired. Close and reopen the game completely.
If using Prism Launcher, remove and re-add your Microsoft account.

### "Unable to connect you to survival"

The backend server is still starting. Wait 30-60 seconds and reconnect.
The proxy is up but the game server behind it hasn't finished loading.

### "Connection refused"

The server may be restarting or down for maintenance. Try again in a
few minutes. Check with the server operator if it persists.

### Client crash on startup

If the game crashes with client mods installed:

1. Open Prism Launcher
2. Right-click the instance → **Edit** → **Mods**
3. Disable all mods (uncheck them)
4. Launch to verify vanilla works
5. Re-enable mods one at a time to find the conflict

### Bedrock players can't connect

Geyser runs on UDP port 19132. If your network blocks UDP, you cannot
connect from Bedrock Edition. Try from a different network.
