# Spike: tying a script-made surface to a planet (Factorio 2.1.25 and 2.1.23)

Question: `scripts/team_surfaces.lua` ties a team's surface to a planet with
`LuaPlanet.associate_surface`. Does the surface then get the planet's
properties, do machines on a tied Aquilo surface freeze, and what happens
when the planet already holds a surface?

Measured 2026-11-18 with Space Age on, with the probe mod in this folder
(`scenarios/probe/control.lua`, one case per run).

- 2.1.25 (build 88022): all five cases, in the game's test mode. The lines
  are in `recorded-2.1.25.txt`.
- 2.1.23 (build 87750): the cases `aquilo`, `built-first` and `two-surfaces`,
  with the same Lua run as a mod's `control.lua` under `--create` and
  `--benchmark` (test mode starts with 2.1.24). Every line was the same as on
  2.1.25. `vulcanus` and `planet-has-surface` were not run on 2.1.23.

| Case | What the log shows |
|---|---|
| A new surface tied to Aquilo | The call succeeds. `planet.surface` is the surface and `surface.planet` is aquilo. In the same tick the properties go from day-night-cycle=300 gravity=10 magnetic-field=90 pressure=1000 robot-energy-usage=1 solar-power=100 (what a plain `game.create_surface` surface has) to day-night-cycle=72000 gravity=15 magnetic-field=10 pressure=300 robot-energy-usage=5 solar-power=1. |
| Entities built on that surface | assembling-machine-2, inserter and pipe read `frozen = true` at ticks 6, 100, 300 and 500. wooden-chest and small-electric-pole read false. The same five entities on a surface that was never tied all read false. |
| A new surface tied to Vulcanus (`entities_require_heating = false`) | The call succeeds: day-night-cycle=5400 gravity=40 magnetic-field=25 pressure=4000 robot-energy-usage=1 solar-power=400. Nothing is frozen. |
| Entities built before the surface is tied to Aquilo | `frozen` is false before the call and true for the machine, inserter and pipe in the same tick right after it. |
| Aquilo already has its own surface (`planet.create_surface()`) | The call throws `Planet must not already be associated with a surface.` The planet keeps its own surface. The script surface keeps `planet = nil` and the plain properties, and nothing on it freezes. Entities on the planet's own surface do freeze. |
| A second script surface for the same planet | The first call succeeds, the second throws the same message. `planet.surface` stays the first surface. |
| The holder is deleted with `game.delete_surface` and the call is retried in the same tick | It still throws. In that tick the deleted surface is still valid and still `planet.surface`. |
| The surface that was refused, tied to another planet | The call succeeds (Vulcanus). |

So a team surface tied to Aquilo on a fresh game is a real Aquilo surface:
planet properties and freezing apply at once, also to what is already built.
A planet takes one surface at a time. A second surface cannot be tied until
the holder is gone, and the tie has to be made in a later tick, because the
deletion is not done in the tick that asks for it. Until then MTS has the
waiting surface stand in for the planet by copying its surface properties and
pollutant (`scripts/team_surfaces.lua`, section "Planet association"); what
follows such a copy and what only the tie brings is measured in
`dev/spikes/surface-props/`. `dev/mods/mts-test` checks the MTS side
of this in the Space Age set: the planet, pressure and gravity of a tied
surface, a frozen machine, and the waiting second surface that is tied once
the holder is deleted.

Not measured: thawing. The first run also put a heating tower six tiles away
from a second group of machines, with no heat pipes between them. That group
stayed frozen, which shows nothing either way, so the tower is left out of
this copy of the probe and of the recorded lines.

## Rerun

```
dev/spikes/heated-planet/run.sh
```

Headless, about two seconds a case. It prints every case's `HP` lines and
compares them with `recorded-2.1.25.txt`: exit 0 when they match, 2 when the
probe finished but the lines differ (the engine behaves differently), 1 when
a case did not finish. `FACTORIO=<path>` picks another binary. Rerun after
the move into this repo on 2.1.25: same lines.
