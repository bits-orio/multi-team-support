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

**Record**:
First or fastest to research a technology or reach a production milestone, one per key. A milestone a mod registers with a first threshold has only a first at that threshold, never a fastest. Timed on the team's own clock, which starts at the claim, or at Start Playing under Staged Start, never game time. A record names a team, never a person, and releasing a slot strips that team from every record, so first means first among the teams still here.
_Avoid_: achievement (the engine's word for something else)

**Restart**:
A player's claim of a team after their first. MTS counts every claim after a player's first counted claim, and the first counted claim too when the player was already on a team when counting began, since it cannot see how they got onto that team. Joining someone else's team is never a restart. Counted from the tick counting began, and never cleared when a slot is released.
_Avoid_: reset (what MTS does to a force when a slot is recycled)

**Incarnation**:
One team's time in a slot, from its claim to its release. MTS reuses slots, so two teams can share the force name `team-4`; the tick each one claimed the slot tells them apart. A team claimed before MTS recorded claim ticks is its slot's `legacy` incarnation. The AI assistant's chat scope (`chat_scope_v1`) keys private chat by incarnation, so the next team in a slot never reads it.
