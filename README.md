# 🏭 Multi-Team Support

A Factorio 2.0 mod for cooperative and competitive multiplayer where each team races on their own copy of the world. Research independently, compare progress, watch your rivals and form alliances, all from one server.

> **Inspired by OARC.** Multi-Team Support carries the same many-players-one-server spirit as the OARC separated-spawns mods, reimagined for Factorio 2.0 with a full per-team copy of the world.

> **Note on tooling:** This mod is developed with AI coding assistants alongside human review and in-game testing. Bug reports, feature requests, and contributions are welcome from everyone. If AI-assisted development isn't your thing, that's fine. This mod's threads are for bugs and features.

## 💬 Community

Join the Discord: https://discord.gg/tWz4FT74pH

## ✨ Features

### Teams
- 🧑‍🚀 **Numbered team pool.** Forces are pre-created as `team-1` through `team-N` (configurable via startup setting, default 20 with Space Age, 60 without). Team names are display-only and can be renamed via `/mts-rename` or the Teams panel.
- 👥 **Multi-player teams.** Buddy join lets multiple players share a team. The leader can kick and accept join requests, and any member can leave.
- 🎨 **Force colors** are always derived from the current team leader's player color.
- 🤝 **Friendship** works by two-sided request between teams. Mutual friendship shares chart and grants friend-view spectation.
- 📡 **Passive radars.** Radars keep the area around them visible but no longer run the rotating scan that permanently charts the wider map; the standard radar also draws less power (50 kW instead of 300 kW, modded radars keep their own cost). On a multi-team server, 20 teams each carpeting their territory with map-charting radars is a major save-size and UPS sink; this bounds that growth while keeping the local visibility players place radars for. **On by default**; disable via startup setting *Passive radars (no map scanning)*. It only stops new charting. Anything already charted stays charted, and purpose-built scanner buildings from other mods are left untouched.

### 🌌 Space Age Integration *(auto-detected)*
- 🪐 **Per-team planet variants.** When Space Age is active, each team gets their own full solar system. The vanilla 5 (Nauvis, Vulcanus, Gleba, Fulgora, Aquilo) plus any modded planets registered via `data:extend` or planet libraries like PlanetsLib (Maraxsis, Lignumis, Muluna, etc.) all get per-team variants automatically. No collisions on shared planets.
- 🛸 **Per-team space connections.** Whatever topology exists in the loaded mod stack is mirrored per team, so rocket launches and space platforms work per-team across vanilla and modded planets alike.
- 🔒 **Base planets locked.** Team forces only see/reach their own variants. Discovery techs unlock the team's variant, not the base. Detection scans for `unlock-space-location` effects on every loaded technology, so modded discovery techs route correctly regardless of naming convention.
- 📦 Falls back to surface-cloning when Space Age isn't installed. Same experience, just no orbits.

### 🏆 Records & Announcements
- 🥇 **Tech records.** The first team to research any tech gets an announcement. Subsequent faster researches (measured from each team's clock) broadcast new speed records.
- 📈 **Milestone engine.** Configurable production thresholds per category (science packs, landfill, space platform tiles). Edit `milestones/config.lua` to add more. Dynamic item discovery handles any mod combo.
- ⏱️ **Team clock** starts when the first member spawns and never resets, so speed comparisons stay fair no matter when a team joined.
- 📢 **Server announcements.** New players receive a welcome with the Discord invite link; returning players get a welcome-back that includes their team name. A server-wide Discord reminder broadcasts every 6 hours. The URL is configured via Settings → Map → Discord URL (defaults to the community Discord; leave blank to disable).

### 🖥️ GUI Panels *(top-left toolbar)*
- 🗂️ **Teams.** A card per team shows the active research queue (up to 7 icons with live progress bars), a colour-coded last-active indicator with per-player playtime on hover, members (★ leader, online/offline, 🤝 friendship, 📡 Follow Cam per player) and surfaces (👁 Spectate).
- 📡 **Follow Cam.** A grid of live mini-cameras tracks individual players across planets. Click the 🔍 on any cell to expand into full spectator view; Esc returns with the grid intact.
- 🔬 **Research.** A tech icon grid ordered by research time. Click any team for a 1-on-1 diff.
- 📊 **Production Stats.** Per-team item production comparison, with per-player item tracking and sortable columns.
- 🛠️ **Admin Panel.** Runtime feature flags, starter items editor, and team size limit. The toolbar button is admin-only.
- 👋 **Welcome / Discord.** Mod intro plus a Discord invite with a scannable QR code.

### 🛬 Landing Pen
- New players wait in a shared pre-game lobby until ready to spawn.
- **"Start a new team"** or **"Request to join"** an existing team. Other actions disable while a join request is pending.
- Request flow and join/leave events announce to all connected players (only the leader can accept).
- Withdraw a request at any time with the Cancel button.

### ⚡ Commands
- `/t <message>` sends a private message to your team only. Other teams see nothing.
- `/mts-teams` lists every team with its leader and member count, colored by team color.
- `/mts-players` lists all players and their surfaces with GPS pings.
- `/mts-leave` leaves your team, after a confirmation dialog that spells out the consequences.
- `/mts-kick <player>` kicks a player from your team (leader only, with confirmation).
- `/mts-rename <name>` renames your team (leader only, 32 char limit, no duplicates).

## 🌍 Languages

English, Spanish, Russian, German. Localization is per player: everyone on a server sees the mod in their own game language, so mixed-language servers just work. (Two cosmetic limits: the TEAM/GLOBAL chat badge next to player names is engine plain-text and stays English, and team names players type are shown as typed.) Want another language? Open an issue.

## ⚙️ Compatibility

- Requires **Factorio 2.0** (`base >= 2.0`, releases 0.6.x) or **Factorio 2.1** (`base >= 2.1`, releases 0.7.x)
- **Space Age** is optional. When it is present, MTS detects it automatically and enables per-team planets plus space connections
- Compatible with [Platformer](https://mods.factorio.com/mod/platformer)
- **Companion modes** *(optional; built on the `mts-v1` API, so each plays out independently per team)*:
  - [**Diggy**](https://mods.factorio.com/mod/diggy): the world is solid rock, so dig out your factory, brace the ceilings, and survive cave-ins. MTS integration is first class, and every team races an identically-seeded dig world.
  - **MTS Expanse** brings tiny-island Expanse gameplay: feed hungry chests, unlock land, race teams, and survive invasions.
  - **Brave New MTS** is a remote-only, character-free layer. Your character never leaves its cell, and you build entirely through a construction-robot network seeded at each team's spawn.
- **open-discord-bridge (ODB)** is optional. It relays per-team announcements, milestones, and chat to a Discord channel.
- **[ai-agent-bridge (AAB)](https://mods.factorio.com/mod/ai-agent-bridge)** is optional. Ask the AI a question in chat and read the answer in chat; MTS tells it who may hear an answer (team-only chat stays team-only), what each team is called, and each team's own clock, so "how am I doing compared to Team Ace" compares fairly.
- **Generic terrain mirror.** Any third-party mod that decorates Nauvis via `on_chunk_generated` (and filters by hardcoded surface name) is automatically mirrored onto every team surface. The mod's handler runs once on the real Nauvis; MTS clones the resulting tiles, entities, and decoratives to each team's nauvis variant. Verified working with [dangOreus](https://mods.factorio.com/mod/dangOreus), [VoidBlock](https://mods.factorio.com/mod/VoidBlock), [Alien Biomes](https://mods.factorio.com/mod/alien-biomes), and content mods like [Periodic Madness](https://mods.factorio.com/mod/periodic-madness). Every team gets the same map by design: one generation, mirrored everywhere. That is what buys zero-cooperation compat, and it is what puts every team on an identical map when they race. See [`docs/COMPAT.md`](docs/COMPAT.md) for details.
- **dangOreus.** Beyond the terrain mirror, MTS also reproduces dangOreus's runtime gameplay rules (block non-miners on ore tiles, spill containers on death, floor-is-lava damage) on team surfaces.
- **Krastorio 2 / Krastorio 2 Spaced Out.** Crash-site entities (vanilla wrecks + K2 spaceship pieces) on team Nauvis surfaces are normalised to `force=neutral` so teams can mine them. Team forces are kept at war with `kr-internal-turrets` so K2's planetary teleporter "standing on" detection and tesla coil targeting fire correctly on team characters.
- Factorio supports up to 64 forces. Without Space Age: up to 60 teams (64 minus 4 reserved built-in forces). With Space Age: capped at 20 due to per-team planet variant pre-creation.

## 🔌 For Mod Authors

Multi-Team Support exposes a public remote interface (`mts-v1`) and custom events so other mods can integrate cleanly without per-mod compatibility shims.

```lua
-- Subscribe to a custom event
if remote.interfaces["mts-v1"] then
    local id = remote.call("mts-v1", "get_event_id", "on_team_surface_created")
    script.on_event(id, function(event)
        -- event.surface_name, event.force_name
    end)
end

-- Query state
local owner = remote.call("mts-v1", "get_surface_owner", "team-3-nauvis")
-- → "team-3" or nil
```

**Events:** `on_team_created`, `on_team_released`, `on_player_joined_team`, `on_player_left_team`, `on_team_surface_created`.

**Queries:** `get_team_list`, `get_team_info`, `is_team_surface`, `get_surface_owner`, `list_team_surfaces`.

The interface name is versioned (`mts-v1`); breaking changes will ship as a parallel `mts-v2` rather than mutating v1. See [`scripts/remote_api.lua`](scripts/remote_api.lua) for the full contract and payload shapes, and [`docs/COMPAT.md`](docs/COMPAT.md) for the broader compatibility strategy (the `surface.planet.name` upstream pitch and when each layer is the right tool). If you maintain a chunk-gen or surface-modifying mod and need an extension point, open an issue.

## 📄 License

[MIT](LICENSE)
