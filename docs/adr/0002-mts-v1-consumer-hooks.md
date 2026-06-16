# mts-v1 gains surface-lifecycle, pause, and team-clock hooks for companion mods

To support warp-style companions — the first being MTS Dimension Warp — without them touching MTS internals, `mts-v1` is extended additively with three groups of hooks:

- **Surface lifecycle:** `create_team_surface(force, {planet, map_gen_settings, name})` and `retire_team_surface(force, name)`, so MTS stays the sole surface authority (creation, seed/ownership registration, planet association, visibility, deletion) while a consumer supplies generation details.
- **Pause control:** `pause_team(force)`, `unpause_team(force, {mode, duration})`, `is_team_paused(force)` — scoped per team across all its surfaces, with an instant default and a staggered (UPS-friendly, thaw-driving) reconnect mode (see ADR-0001).
- **Liveness:** an `on_team_clock_started` event, so a consumer can tie its own clock to MTS's team-liveness (staged starts) rather than raw ticks.

All additions are backward-compatible. This preserves the rule that MTS is the single writer of its own state (mirrored in MTS Dimension Warp's ADR-0003), and the hooks are reusable by any future consumer.
