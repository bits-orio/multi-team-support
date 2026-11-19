# Spike: camera zoom_limits and sprite opacity (Factorio 2.1.25)

Question: 2.1.25 adds `LuaGuiElement.zoom_limits` for camera elements and
`LuaGuiElement.opacity` for sprites and sprite buttons. What do they accept,
does a zoom limit hold back a zoom set from script, does the mouse wheel zoom
a camera element, what does a faded sprite look like, and how should a mod
that also runs on older games detect them?

Measured 2026-11-18 on 2.1.25 (build 88022) with the probe mod in this
folder. The API matrix ran headless in the game's test mode
(`recorded-2.1.25.txt`). The wheel and the look were checked in a graphical
client at 1920x1080 on a private display (`wheel-2.1.25.txt`,
`opacity-crop.png`). 2.1.23 (build 87750) was only used for the version
check at parse time.

## opacity

| Step | Result |
|---|---|
| Default on a sprite and a sprite button | 1 |
| Write 0.5, 0.25, 0 | Reads back the same |
| Write 2, write -1, `opacity = 3` in `gui.add` | Clamped without an error: 1, 0, 1 |
| Write the string `"0.3"` | Accepted, reads 0.30000001192093 |
| Write `nil` or `"x"` | Error `'opacity': real number expected got nil.` (or `got string.`) |
| `opacity` in `gui.add` for a sprite or a sprite button | Accepted, reads back 0.5 |
| Read, write or `gui.add` with opacity on a button, label, frame, camera, empty-widget, progressbar or flow | Error `Expected sprite or sprite-button.` in all three |

The look (`opacity-crop.png`, a 2x crop of the probe frame): the top row is a
sprite and a sprite button with a count of 7 at opacity 1, 0.5 and 0.25. Only
the icon fades. The count and the button's frame stay solid. The bottom row
is a `slot_button` and a `red_slot_button`, each at 1 and at 0.5.

## zoom_limits

| Step | Result |
|---|---|
| Default | A camera made without `zoom` reads zoom 0.75 and `zoom_limits` `{}` |
| Write `{closest={zoom=10}}`, `{furthest={zoom=0.5}}`, both | Reads back what was written |
| Write `{closest=...}`, then `{furthest=...}` | Only `furthest` is left: a write replaces the whole field |
| Write `{}` | Clears the limits |
| Write `nil` | Error `value for required parameter 1 (zoom_limits) is missing`. The limits stay as they were. |
| Write `5`, `{closest=5}`, `{closest={}}` | Errors: `'zoom_limits': table expected, got number`, `'closest': table expected, got number`, `Invalid ZoomSpecification. At least one mutually exclusive field must be defined.` |
| `zoom` and `distance` in one specification | Error `Invalid ZoomSpecification. Only one mutually exclusive field can be defined.` |
| Zoom -1 or 0 | Error `Zoom must be positive. -1 was given.` |
| Closest 0.2 with furthest 2 (the wrong way round) | Accepted, reads back as written |
| `{closest={distance=50}}` | Reads back `{closest={distance=50, max_distance=500}}` |
| `{furthest_game_view={zoom=0.3}}` | Accepted |
| `zoom_limits` in `gui.add` | No error, but the new camera reads `{}`. Set it after `add`. |
| Read or write on a sprite | Error `Only callable on camera.` |
| Limits 0.5 to 4, then `camera.zoom` set to 5, 10, 100, 0.4, 0.1 | Each reads back as set. The limits do not hold back a zoom set from script. |
| Zoom 3, then `closest={zoom=1}`. Zoom 1, then `furthest={zoom=2}`. | The zoom stays 3, and stays 1 |

## The mouse wheel over a camera element

Two cameras side by side, one with limits 0.5 to 2 and one without, pointer
over each in turn, in two sessions with the frame in different places.

| Step | Camera with limits | Camera without | Player's own zoom |
|---|---|---|---|
| Start | 1 | 1 | 1 |
| 5 notches in over either camera | 1 | 1 | 1.64 |
| 30 more notches in | 1 | 1 | 3 |
| 60 notches out | 1 | 1 | 0.3 |
| Camera with limits set to zoom 5 from script, then 3 notches out over it | 5 | 1 | 0.3 |

The wheel never changed a camera element's zoom, with or without limits. It
zoomed the player's own view behind the frame. A camera in a mod GUI is
zoomed from script (buttons), and the script keeps the zoom inside its own
range.

## Telling whether the game has these

- `helpers.compare_versions(script.active_mods.base, "2.1.25") >= 0`, logged
  while `control.lua` is parsed, gave `false` on 2.1.23 and `true` on 2.1.25.
- 100000 rounds each on 2.1.25: a read in `pcall` 9.9 ms, a write in `pcall`
  8.4 ms, the version comparison 156 ms, a boolean worked out once 0.35 ms.
  So compare once at parse time and keep the answer, as
  `scripts/engine_features.lua` does.
- What 2.1.23 does when the properties are read or written was looked at in
  a client during the first run, but the log of that session was overwritten
  and holds no probe lines. It is not part of this record.
  `remote.call("gzo", "matrix")` in a client on an old game measures it again.

Not measured: the wheel with a modifier key held, opacity on sprites other
than an item icon, rendering on a GPU, multiplayer.

## Rerun

```
dev/spikes/gui-zoom-opacity/run.sh          # headless: the API matrix and the timing
dev/spikes/gui-zoom-opacity/run.sh wheel    # a graphical client on a private display
```

The headless run compares the matrix with `recorded-2.1.25.txt`: exit 0 when
the lines match, 2 when they differ, 1 when the probe did not finish. Rerun
after the move into this repo on 2.1.25: same lines.

`run.sh wheel` starts one graphical client (about 2 GB of memory, one at a
time on a machine), turns the wheel over both cameras, prints the `STATE`
lines to hold against `wheel-2.1.25.txt` and saves a screenshot of the frame.
It was not rerun after the move: only its syntax was checked.
