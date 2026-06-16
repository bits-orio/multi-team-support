# Multi-Team Support

Each player or group gets their own MTS team — an independent force with its own research and its own copy of the map — so people share one server and one start but race to different finishes. Exposes the `mts-v1` remote interface so companion mods can extend the multi-team experience.

> This glossary is seeded from the MTS Dimension Warp design session and covers only the terms that came up there. Grow it as other areas are documented.

## Language

**Team**:
A force named `team-N` with independent research, relations, and surfaces. The unit of isolation — one member leads, others may join or buddy up.
_Avoid_: clan, group (in code)

**Team surface**:
A surface owned by a team — its home-planet variant, an outer planet, or a space platform. Ownership is tracked by MTS, not inferred from the surface name alone.

**Home surface**:
The team surface a player spawns onto, and is bounced back to if they stray onto a surface they don't own.

**Landing pen**:
A shared lobby surface where new players stage — on the spectator force, not yet on a team — until they claim or join one.
_Avoid_: lobby, waiting room

**Spectator**:
A player temporarily moved to the spectator force to watch teams, and restored to their real team on exit.

**Pause**:
Freezing a team so it makes no progress: power generation is disabled across all of the team's surfaces (the airtight freeze), and pole wires are recorded and cut for the Space-Age visual thaw. A consumer-driven capability (e.g. MTS Dimension Warp's docking bay) — MTS does not offer it on its own, because a paused base has no powered defenses and is only safe somewhere a consumer has already made safe.
