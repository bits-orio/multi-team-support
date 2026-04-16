# 🏭 Multi-Team Support

> **Same start. Different finish.**

A Factorio 2.0 mod for cooperative and competitive multiplayer where each team races on their own copy of the world. Research independently, compare progress, watch your rivals, form alliances — all from one server.

## 💬 Community

Join the Discord: **https://discord.gg/tWz4FT74pH**

## ✨ Features

### Teams
- 🧑‍🚀 **Numbered team pool** — Forces pre-created as `team-1` through `team-N` (configurable via startup setting, default 20). Team names are display-only and can be renamed via `/mts-rename` or the Teams panel.
- 👥 **Multi-player teams** — Buddy join lets multiple players share a team. Leader can kick and accept join requests; any member can leave.
- 🎨 **Force colors** — Always derived from the current team leader's player color.
- 🤝 **Friendship** — Two-sided requests between teams; mutual friendship shares chart and grants friend-view spectation.

### 🌌 Space Age Integration *(auto-detected)*
- 🪐 **Per-team planet variants** — When Space Age is active, each team gets their own full solar system (Nauvis/Vulcanus/Gleba/Fulgora/Aquilo variants). No more collisions on shared planets.
- 🛸 **Per-team space connections** — Vanilla topology mirrored for each team so rocket launches and space platforms work per-team.
- 🔒 **Base planets locked** — Team forces only see/reach their own variants. Discovery techs unlock the team's variant, not the base.
- 📦 Falls back to surface-cloning when Space Age isn't installed — same experience, just no orbits.

### 🏆 Records & Announcements
- 🥇 **Tech records** — First team to research any tech gets an announcement. Subsequent faster researches (measured from each team's clock) broadcast new speed records.
- 📈 **Milestone engine** — Configurable production thresholds per category (science packs, landfill, space platform tiles). Edit `milestones/config.lua` to add more. Dynamic item discovery handles any mod combo.
- ⏱️ **Team clock** — Starts when the first member spawns; never resets. Makes speed comparisons fair regardless of when a team joined.

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
- Request flow announces to all team members (only the leader can accept).
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
- Compatible with [Platformer](https://mods.factorio.com/mod/platformer) and [VoidBlock](https://mods.factorio.com/mod/VoidBlock)
- Factorio supports up to 64 forces (20 teams + built-ins leaves plenty of headroom)

## 📄 License

[MIT](LICENSE)
