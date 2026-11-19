# Spike: a planet's properties copied onto a surface (Factorio 2.1.25 and 2.1.23)

Question: a team surface made for a planet that is still held by another
surface cannot be tied to it yet (`dev/spikes/heated-planet/`). If a script
copies the planet's surface properties and pollutant onto the waiting
surface, what then behaves as on the planet, what does not, and what does a
later `associate_surface` do to the values the script wrote?

Measured 2026-11-19 with Space Age on, with the probe mod in this folder,
one case per save (the setup runs while the save is created, the rest after
it is loaded).

- 2.1.25 (build 88022): all nine cases, in the game's test mode. The lines
  are in `recorded-2.1.25.txt`.
- 2.1.23 (build 87750): the cases `props`, `tie`, `misc` and `day` under
  `--benchmark`. Every line was the same as on 2.1.25. The effect cases and
  `robots` were not run on 2.1.23.
- The first `fx-vulcanus` run stopped after 70 ticks. Its day length, solar
  and end-of-run lines come from the rerun out of this folder on 2.1.25.

## The copy

The game has six surface properties: day-night-cycle, gravity,
magnetic-field, pressure, robot-energy-usage and solar-power. A planet's
prototype lists the ones it sets (`planet.prototype.surface_properties`);
the rest keep the property's default. Writing each of the six with
`surface.set_property` (the planet's value where it has one, the default
otherwise) gave a surface whose properties read the same as the planet's own
surface, for Vulcanus, Gleba, Fulgora and Aquilo, also after a save and
load. Writing day-night-cycle also sets `ticks_per_day`.

What the copy does not change: `surface.planet` stays nil, and
`pollutant_type` stays `pollution`, where the planet's own surface reads nil
(Vulcanus, Fulgora, Aquilo) or `spores` (Gleba). The pollutant is set apart:

| `surface.override_pollution_type =` | `pollutant_type` reads | `pollute` then `get_pollution` |
|---|---|---|
| never written, or `nil` | pollution | 100 |
| `{}` | nil | 0 |
| `{pollutant = "spores"}`, or Gleba's prototype value | spores | 100 |
| `{pollutant = nil}` (what Vulcanus' prototype gives) | nil | 0 |

Other things seen: an unknown property name is an error
(`Unknown surface-property name: no-such-property`). A pressure of -5 is
accepted. A property cannot be unset: `set_property("pressure", nil)` is an
error. The planet prototype's `lightning_properties`,
`surface_render_parameters` and `persistent_ambient_sounds` cannot be read
at runtime.

## What follows the copy

Three surfaces side by side: a plain new one, a copy, and the planet's own.

| Check | Plain surface | Copy | Planet's own surface |
|---|---|---|---|
| A recipe with a surface condition (foundry, biochamber, lightning-rod, cryogenic-plant) pasted by a player with `copy_settings` | Not set | Set | Set |
| The same recipe in a blueprint the player places | Ghost and machine have no recipe | Recipe kept | Recipe kept |
| A biolab (Nauvis pressure only): `can_place_entity` as a manual build, `can_build_from_cursor`, `build_from_cursor` | Allowed, built | Refused | Refused |
| Day length, from how far `daytime` moved in 100 ticks | 25200 ticks | The planet's (5400, 36000, 10800, 72000) | The same as the copy |
| One solar panel at noon | 60 kW | Vulcanus 240, Gleba 30, Fulgora 12, Aquilo 0.6 kW | The same as the copy |
| A construction robot's 681 tick flight with Aquilo's values | 228771 J | 1143857 J | 1144107 J in 682 ticks |
| Aquilo: assembling machine, pipe, inserter | Not frozen, the machine works | Not frozen, the machine works | Frozen, the machine's status is `frozen` |
| Fulgora: lightning over 1130 night ticks | None | None | 6665 lightning entity-ticks |
| Fulgora: `surface.execute_lightning` | Error | Error `Used surface sp-copy (index 4) does not have a lightning generator.` | Works |

`set_recipe` from a script is not checked against surface conditions: it
was accepted on all three surfaces, and the machine on the plain surface
crafted the recipe.

So building and recipe conditions, the day length, solar power and robot
energy go by the properties, and a copy has them. Freezing and lightning
belong to the planet's own surface and start only with the tie.

## What a tie does to written values

| Before the tie | After `associate_surface` |
|---|---|
| Nothing written (`dev/spikes/heated-planet/`) | Every property takes the planet's value |
| Only pressure written (1234), tied to Fulgora | Pressure stays 1234. The other five take Fulgora's values. |
| All six written to the planet's values, robot-energy-usage to 7 | All six stay as written, the 7 too |
| All six written to 3 | All six stay 3 |
| `ticks_per_day` written to 7777 | Stays 7777. The day-night-cycle property reads the planet's. |
| `solar_power_multiplier` written to 3 | Stays 3 |
| A pollutant override | Stays. Once it is set to `nil` the surface reads the planet's pollutant (spores on Gleba). |
| No pollutant override | `pollutant_type` reads the planet's (nil on Vulcanus and Aquilo) |
| Machines built on an Aquilo copy | Not frozen before the tie, frozen at the next check four ticks after it |

A tie fills in only what no script has written. Values copied from the
planet are therefore still right after the tie, and a pollutant override has
to be taken off again at the tie. A write on a tied surface sticks as well
(pressure 555 was still there six ticks later).

`ticks_per_day` and the day-night-cycle property are two values: writing the
property sets `ticks_per_day`, writing `ticks_per_day` leaves the property
alone, and the day runs by `ticks_per_day` (a new surface reads 25200 ticks
with a property of 300). `solar_power_multiplier` and the solar-power
property do not touch each other.

When the holder is deleted: in the tick of `game.delete_surface` the surface
is still valid and still `planet.surface`. In `on_pre_surface_deleted` the
planet still holds it. In `on_surface_deleted` the planet is free, and
`associate_surface` called from that handler succeeded for all three
planets.

`scripts/team_surfaces.lua` (section "Planet association") uses this: a
surface that waits for a held planet gets the planet's properties and
pollutant, and is tied once a deletion frees the planet.

Not measured: the effect cases on 2.1.23, thawing, what a planet does to the
player (Gleba's and Aquilo's prototypes list a player effect), the look and
sound of a surface, spores and enemies on a copy of Gleba.

## Rerun

```
dev/spikes/surface-props/run.sh [case ...]
```

Headless, under a minute for all nine cases (props, tie, misc, day, robots,
fx-vulcanus, fx-gleba, fx-fulgora, fx-aquilo). It prints every case's `SP`
lines and compares them with `recorded-2.1.25.txt`: exit 0 when they match,
2 when the probe finished but the lines differ (the engine behaves
differently), 1 when a case did not finish. What lightning does on Fulgora's
own surface is left out of the comparison. In the printed lines a surface's
day shape and flags are shortened while they read as on a new surface.
`FACTORIO=<path>` picks another binary; before 2.1.24 the cases run under
`--benchmark` without a player, so the player checks of the fx cases are
skipped there. Rerun after the move into this repo on 2.1.25: same lines.
