# Solo Teams

A Factorio 2.0 mod that gives each player their own force (team) with independent research, production statistics, and diplomacy. Players compete solo while sharing the same game world.

## Origin

This mod was primarily built for the [Space Block](https://mods.factorio.com/mod/yunrus-space-block) scenario, where each player gets their own space platform and races independently. It may work with other scenarios and mods as well, though that hasn't been extensively tested.

## Features

- **Separate forces** — Each player who joins automatically gets their own force (`player-<name>`). All researched technologies, quality unlocks, and space platform access are copied from the default force.
- **Neutral diplomacy** — Players start in a cease-fire relationship (can't hurt each other, can't interact with each other's buildings). Friendship can be opted into per-player.
- **Platforms GUI** — A draggable, collapsible overlay showing all players and their platforms with live GPS locations. Clicking the GPS icon pings the location in chat.
- **Friend toggle** — A checkbox next to each player's name in the GUI lets you control friendship independently. Friending another player lets them access your entities.
- **Cross-force chat** — Normal chat messages are broadcast to all forces, so players don't need `/shout` to communicate.
- **/platforms command** — Lists all players and their platforms with colored names and clickable GPS pings.
- **/unstuck command** — Ejects the player from a vehicle (e.g. platform hub) and teleports to a safe position. Useful when accidentally entering the hub entity.
- **Spawn collision fix** — Automatically detects when a player is teleported onto a platform hub and repositions them to a non-colliding spot.

## Installation

1. Download or clone this repository into your Factorio mods folder as `solo-teams_0.1.0/`
2. Enable the mod in the Factorio mod manager
3. Start or load a game — solo forces are created automatically for each new player

## Compatibility

- Requires Factorio 2.0 (`base >= 2.0`)
- No dependencies on any other mod
- Designed to load before most mods alphabetically, so force creation happens before other mods process new players
- Factorio has a hard limit of 64 forces, supporting up to ~61 players (after subtracting built-in forces)

## License

[MIT](LICENSE)
