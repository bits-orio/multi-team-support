# Multi-Team Support

> One server. One seed. A private world for every team.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/multi-team-support)

One server, many teams, and every team gets its own private copy of the same map. Same seed, same resource layout, no competition for tiles. Bring a friend onto your team and build together, or give them a team of their own and race them from an identical start. Both work, and you choose per player.

It carries the spirit of the OARC separated-spawns mods, rebuilt from scratch for Factorio 2.0 around a full per-team copy of the world rather than a carved-out region of one shared map.

## Status

Two release lines while Factorio 2.1 is experimental: 0.6.x for Factorio 2.0 (stable), 0.7.x for Factorio 2.1.

In active use on public servers. Team cap is 20 with Space Age, where each team gets a whole solar system, and 60 without. Every team plays the same terrain by design: one world generation, mirrored to every team surface. That is what lets terrain mods decorate all of them without cooperating with MTS, and what puts every team on an identical map when they race. Localized per player into English, Spanish, Russian and German, so mixed-language servers just work.

## Quick start

1. Install on the server and start a new save.
2. Set the team count in Settings → Startup (defaults to 20 with Space Age, 60 without).
3. Players arrive in a shared landing pen instead of spawning immediately.
4. Each picks "Start a new team" or "Request to join" an existing one.
5. Surfaces, research and team clocks are created automatically from there.

## Features

### Teams and players

- Several players per team, with buddy-join, leader-approved join requests, kick and rename.
- Two-sided friendships between teams share map chart and unlock friend spectating.
- A landing-pen lobby so new arrivals pick a team before they spawn, not after.

### Racing and spectating

- Follow Cam, a grid of live mini-cameras tracking individual players across planets.
- First-to-research announcements, plus speed records measured on each team's own clock.
- Per-team production stats and a one-on-one research diff between any two teams.

### Worlds

- With Space Age, each team gets its own solar system, including modded planets registered through PlanetsLib.
- Terrain mods decorate every team surface with no configuration: [dangOreus](https://mods.factorio.com/mod/dangOreus), [VoidBlock](https://mods.factorio.com/mod/VoidBlock) and [Alien Biomes](https://mods.factorio.com/mod/alien-biomes) work out of the box.

## Compatibility

Requires Factorio 2.0 (releases 0.6.x) or Factorio 2.1 (releases 0.7.x); the in-game mod browser shows the one that matches your game. Space Age is optional and auto-detected. Verified against dangOreus, VoidBlock, Alien Biomes, [Periodic Madness](https://mods.factorio.com/mod/periodic-madness), [Krastorio 2](https://mods.factorio.com/mod/Krastorio2) and [Platformer](https://mods.factorio.com/mod/platformer).

Mod authors: Multi-Team Support exposes a versioned `mts-v1` remote interface and custom events, so you can integrate without a per-mod compatibility shim. See the [remote API contract](https://github.com/bits-orio/multi-team-support/blob/master/scripts/remote_api.lua) and the [compatibility strategy notes](https://github.com/bits-orio/multi-team-support/blob/master/docs/COMPAT.md). The [full command reference](https://github.com/bits-orio/multi-team-support/blob/master/README.md) lives in the repo.

## Works with

- [Diggy](https://mods.factorio.com/mod/diggy): dig a factory out of solid rock. Each team gets its own cave system.
- [Brave New MTS](https://mods.factorio.com/mod/brave-new-mts) adds remote-only, character-free play on top of MTS.
- [MTS Dimension Warp](https://mods.factorio.com/mod/mts-dimension-warp) warps every team's base through its own sequence of dimensions.
- [Land Title Registry](https://mods.factorio.com/mod/land-title-registry) makes each team earn its buildable land cell by cell.
- [Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge) relays team events and chat to Discord.
- [AI Agent Bridge](https://mods.factorio.com/mod/ai-agent-bridge) answers questions in chat from the live game. On an MTS server team-only chat gets team-only answers, teams are called by their names, and teams are compared on their own clocks.

## Links

- [Source on GitHub](https://github.com/bits-orio/multi-team-support)
- [Community Discord](https://discord.gg/tWz4FT74pH)

## Development

Developed with AI coding assistants alongside human review and in-game testing. Issues and pull requests are welcome on [GitHub](https://github.com/bits-orio/multi-team-support).

License: MIT
