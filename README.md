# 🏭 Multi-Team Support

> **Same start. Different finish.**

A Factorio 2.0 mod for cooperative and competitive multiplayer where each team races on their own copy of the world. Research independently, compare progress, watch your rivals, form alliances — all from one server.

> **Note on tooling:** This mod is developed with AI coding assistants alongside human review and in-game testing. Bug reports, feature requests, and contributions are welcome from everyone. If AI-assisted development isn't your thing, that's fine — but please keep the hate off this mod's threads. And a gentle request: please don't be rude or disrespectful to the author on other platforms either. There's a human on the other side, don't be anti-human by being rude to them.

## 💬 Community

Join the Discord: **https://discord.gg/tWz4FT74pH**

## ✨ Features

### Teams
- 🧑‍🚀 **Numbered team pool** — Forces pre-created as `team-1` through `team-N` (configurable via startup setting, default 20). Team names are display-only and can be renamed via `/mts-rename` or the Teams panel.
- 👥 **Multi-player teams** — Buddy join lets multiple players share a team. Leader can kick and accept join requests; any member can leave.
- 🎨 **Force colors** — Always derived from the current team leader's player color.
- 🤝 **Friendship** — Two-sided requests between teams; mutual friendship shares chart and grants friend-view spectation.

### 🌌 Space Age Integration *(auto-detected)*
- 🪐 **Per-team planet variants** — When Space Age is active, each team gets their own full solar system. The vanilla 5 (Nauvis, Vulcanus, Gleba, Fulgora, Aquilo) plus any modded planets registered via `data:extend` or planet libraries like PlanetsLib (Maraxsis, Lignumis, Muluna, etc.) all get per-team variants automatically. No collisions on shared planets.
- 🛸 **Per-team space connections** — Whatever topology exists in the loaded mod stack is mirrored per team, so rocket launches and space platforms work per-team across vanilla and modded planets alike.
- 🔒 **Base planets locked** — Team forces only see/reach their own variants. Discovery techs unlock the team's variant, not the base. Detection scans for `unlock-space-location` effects on every loaded technology, so modded discovery techs route correctly regardless of naming convention.
- 📦 Falls back to surface-cloning when Space Age isn't installed — same experience, just no orbits.

### 🏆 Records & Announcements
- 🥇 **Tech records** — First team to research any tech gets an announcement. Subsequent faster researches (measured from each team's clock) broadcast new speed records.
- 📈 **Milestone engine** — Configurable production thresholds per category (science packs, landfill, space platform tiles). Edit `milestones/config.lua` to add more. Dynamic item discovery handles any mod combo.
- ⏱️ **Team clock** — Starts when the first member spawns; never resets. Makes speed comparisons fair regardless of when a team joined.
- 📢 **Server announcements** — New players receive a welcome with the Discord invite link; returning players get a welcome-back that includes their team name. A server-wide Discord reminder broadcasts every 6 hours. The URL is configured via Settings → Map → Discord URL (defaults to the community Discord; leave blank to disable).

### 🖥️ GUI Panels *(top-left toolbar)*
- 🗂️ **Teams** — Card per team with members (★ leader, online/offline, 🤝 friendship, 📡 Follow Cam per player) and surfaces (👁 Spectate).
- 📡 **Follow Cam** — Grid of live mini-cameras tracking individual players across planets. Click the 🔍 on any cell to expand into full spectator view; Esc returns with the grid intact.
- 🔬 **Research** — Tech icon grid ordered by research time. Click any team for a 1-on-1 diff.
- 📊 **Production Stats** — Per-team item production comparison.
- 🛠️ **Admin Panel** — Runtime feature flags, starter items editor, and team size limit. Toolbar button is admin-only.
- 👋 **Welcome / Discord** — Mod intro + Discord invite with scannable QR code.

### 🛬 Landing Pen
- New players wait in a shared pre-game lobby until ready to spawn.
- **"Start a new team"** or **"Request to join"** an existing team — other actions disable while a join request is pending.
- Request flow and join/leave events announce to all connected players (only the leader can accept).
- Withdraw a request at any time with the Cancel button.

### ⚡ Commands
- `/mts-teams` — List all teams with leader and member counts, colored by team color.
- `/mts-players` — List all players and their surfaces with GPS pings.
- `/mts-leave` — Leave your team (confirmation dialog explains consequences).
- `/mts-kick <player>` — Kick a player from your team (leader only, with confirmation).
- `/mts-rename <name>` — Rename your team (leader only, 32 char limit, no duplicates).

## ⚙️ Compatibility

- Requires **Factorio 2.0** (`base >= 2.0`)
- **Space Age** — optional; auto-detected and enables per-team planets + space connections when present
- Compatible with [Platformer](https://mods.factorio.com/mod/platformer)
- **Generic terrain mirror** — any third-party mod that decorates Nauvis via `on_chunk_generated` (and filters by hardcoded surface name) is automatically mirrored onto every team surface. The mod's handler runs once on the real Nauvis; MTS clones the resulting tiles, entities, and decoratives to each team's nauvis variant. Verified working with [dangOreus](https://mods.factorio.com/mod/dangOreus), [VoidBlock](https://mods.factorio.com/mod/VoidBlock), [Alien Biomes](https://mods.factorio.com/mod/alien-biomes), and content mods like [Periodic Madness](https://mods.factorio.com/mod/periodic-madness). Trade-off: every team gets the same map (per-team randomization is sacrificed for zero-cooperation compat). See [`docs/COMPAT.md`](docs/COMPAT.md) for details.
- **dangOreus** — beyond the terrain mirror, MTS also reproduces dangOreus's runtime gameplay rules (block non-miners on ore tiles, spill containers on death, floor-is-lava damage) on team surfaces.
- Factorio supports up to 64 forces (20 teams + built-ins leaves plenty of headroom)

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

The interface name is versioned (`mts-v1`); breaking changes will ship as a parallel `mts-v2` rather than mutating v1. See [`scripts/remote_api.lua`](scripts/remote_api.lua) for the full contract and payload shapes, and [`docs/COMPAT.md`](docs/COMPAT.md) for the broader compatibility strategy (zero-cooperation event replay, the `surface.planet.name` upstream pitch, and when each layer is the right tool). If you maintain a chunk-gen or surface-modifying mod and need an extension point, open an issue.

## 📄 License

[MIT](LICENSE)
