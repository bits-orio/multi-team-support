# Production Stats — Fluids & Quality — Implementation Plan

**Date:** 2026-08-18
**Status:** Draft — every open API question resolved empirically, ready for implementation

## Problem Statement

Two player requests against the Production Stats panel:

1. **Fluids cannot be added to a column.** Every column is a `choose-elem-button` with
   `elem_type = "item"`, so crude oil, petroleum gas and sulfuric acid are unreachable.
2. **The panel shows no quality information.** Vanilla's own production GUI has had a
   quality merge/separate selector since 2.0; MTS has nothing.

They are the same request: a column is a bare item-name string, and neither a fluid nor a
quality can be expressed in one.

Investigation turned up a third, unreported problem that outranks both.

### The panel under-reports production (confirmed)

`M.get_count` reads statistics with a bare item-name string. Per the API docs,
`FlowStatisticsID` resolves for item statistics to `ItemWithQualityID`, whose `string`
option is documented as *"The prototype name. **Normal quality will be used.**"*

Measured in-game on `team-9-nauvis` (seeded normal=7, uncommon=100, plus live production):

| read | value |
| --- | --- |
| `input_counts["iron-plate"]` | **208** |
| `get_input_count("iron-plate")` | **108** |
| `get_input_count{name=…, quality="normal"}` | 108 |
| `get_input_count{name=…, quality="uncommon"}` | 100 |

`108 + 100 = 208`. The two "flat" reads **disagree**: the `input_counts` dictionary merges
across qualities, while `get_input_count` with a bare string returns normal only. MTS uses
the latter, so a team producing quality reads low — on a race-your-friends mod, a team
going hard on quality currently looks *behind* when it is ahead.

This is a correctness fix, not a feature.

---

## Verified Facts

Everything below was measured in-game, not inferred. These are the constraints the design
is built on. Probe sources and raw output: `docs/PRODUCTION_STATS_PROBES.md` (archived
there because `factorio-current.log` is overwritten on every game launch).

**Statistics reads**

- `input_counts` is a `dictionary<string, uint64|double>` that **merges all qualities**.
  One attribute read per statistics object — no per-column or per-quality cost.
- `get_input_count(name)` and `get_flow_count{name = name}` are **normal-quality only**.
- Timed precision buffers **are quality-partitioned**: `B2norm = 108` vs `B3unc = 100` at
  `one_minute`. Per-quality numbers are available on *every* time period, not just All-time.
  (The base was producing normal plates during the test, so the *magnitudes* are
  contaminated — but the conclusion rests only on `B2 ~= B3`. Were quality ignored on timed
  reads, all three B readings would be identical; instead each matched its own all-time
  per-quality figure exactly.)
- There is **no merged shortcut for timed reads**. Merged mode on a timed period must sum
  the chain; only All-time gets the free `input_counts` read.
- `get_flow_count` normalises to per-minute unless `count = true`. MTS already passes
  `count = true`, so its numbers are counts. Keep it.
- Two distinct call shapes, easy to confuse:
  `get_input_count{name = n, quality = q}` — the pair *is* the argument.
  `get_flow_count{name = {name = n, quality = q}, category = …}` — the pair *nests*.

**Fluids**

- `force.get_fluid_production_statistics(surface)` mirrors the item call.
- Fluid IDs take **bare strings** — the shape this design uses, and the only one proven
  against every call site. `{name = "water", amount = 1}` also works: the `Fluid` variant is
  accepted and `amount` is ignored for lookup. `{name = "water", quality = "uncommon"}`
  *fails*, but only with *"value for required field 'amount' is missing"* — `amount` is
  non-optional on `Fluid`, so the call never got far enough to say whether a surplus
  `quality` key is tolerated. That question is untested and deliberately avoided.
  The design consequence stands regardless: item IDs are `{name, quality}` and fluid IDs are
  bare strings, so a shared "build an ID table" helper would break the fluid path.
- Fluid counts are **fractional doubles** (`956.31867647171`). Formatting must tolerate it.
- Fluids have no quality dimension at any depth of `FluidID`.

**Quality**

- `prototypes.quality` must be walked as a **chain** via `.next` from `normal`.
  Both obvious alternatives are wrong, demonstrably so on our own test save:
  - **Level-sort fails.** Levels are `0,1,2,3,5,6,7,8,10` — gaps at 4 and 9 — and
    `quality-unknown` also reports level 0, tying with `normal`.
  - **Hidden-filter fails.** Base sets `normal.hidden = true`; the `quality` mod flips it
    back. On a base-only install, filtering on `hidden` drops `normal` entirely.
- `.next` is declared `optional:false` in the docs but is genuinely nil-terminated.
  Write `while q do … q = q.next end`, never `while q.next do`.
- The chain walk excludes the unreachable `quality-unknown` placeholder for free.
- `script.feature_flags.quality` gates the whole axis.
- `force.is_quality_unlocked(name)` **works and returns a boolean**, despite the docs
  declaring no return values. Our test force has 4 of 9 unlocked. Useful for the selector
  row, but **not load-bearing for summation** — "locked implies zero production" is a
  gameplay norm, not an invariant. Scripted `on_flow` carries no unlock check (our probes
  wrote statistics directly), and cheat mode or a companion mod can do the same at any
  quality. The fan-out gate therefore derives the summation set from production data.
- The chain is **not** five long. Our test save runs Quality-Plus-Plus with **nine**:
  `normal > uncommon > rare > epic > legendary > mythical > masterwork > wondrous > artifactual`.

**Prototypes and rendering**

- `parameter` is a boolean on item, fluid, recipe and entity prototypes, and it is
  **not covered by `hidden` or `hidden_in_factoriopedia`**. On our test save 10 of 18
  "visible" fluids are `parameter-0 … parameter-9` blueprint placeholders. Any prototype
  scan must exclude them.
- Rich text `[item=NAME,quality=QUALITY]`, `[fluid=NAME]`, `[quality=NAME]` and
  `[img=quality/NAME]` all render. `helpers.is_valid_sprite_path` confirms `fluid/…` and
  `quality/…` sprite paths are valid.
- `hidden_from_flow_stats` recipes: **0** on our test save — a real measurement.
  `main_product == ""` is **untested**: the probe branch that counted it is unreachable,
  because runtime `Product.name` is non-optional and always names a real prototype, so the
  reported zero is a tautology rather than evidence. The `""` state is documented at the
  data stage only. Keep a cheap `main_name == ""` guard; do not claim it never happens.
- 7 recipes are mixed item+fluid with no `main_product`; all are barrel-emptying recipes.
  None feed the Ores/Plates/Science tabs, so fixing the primary-producer heuristic
  **cannot reorder existing tabs**.
- Every API this touches is byte-identical between 2.0.77 and 2.1.11. One implementation
  serves both branches. 2.1 additionally offers `input_quality_counts`, feature-detectable.

---

## Design Principles

1. **Correctness first.** Merged-across-quality is the default. A team's number must mean
   "everything you produced", the way players already read it.
2. **Discover, never assume.** Quality count, fluid set, and unlock state all come from
   runtime prototype scans. No vanilla name, count or ordering is baked into logic.
   Seed lists are defaults only, and every entry is guarded by an existence check.
3. **The data model is general; the UI is conservative.** A column record can name a fluid
   in any category from day one. Only the picker is restricted, so widening later needs
   no migration.
4. **Quality is a view, not a column.** One selector governs the whole table. Per-column
   quality pinning is deliberately out of scope — it collides with the global selector and
   doubles the header's complexity for a narrow gain.
5. **Pay for what is shown.** Quality fan-out happens only for the cells that can possibly
   have non-normal production, and only for qualities that cell was actually produced at.

---

## Data Model

### Column record

A column becomes a record instead of a name string:

```lua
{ kind = "item", name = "iron-plate" }
{ kind = "fluid", name = "crude-oil" }
```

`kind` drives which statistics object is consulted and whether the quality axis applies at
all. No `quality` field — quality is a view-level concern (principle 4). The field exists
in the shape's vocabulary should pinning ever be wanted; nothing today writes it.

Item columns keep `elem_type = "item"` — deliberately not `"item-with-quality"`. With
quality as a view, a per-column quality chosen in the picker would be discarded, and an
affordance that lies is worse than none.

### Storage and migration

`storage.stats_category_items[player_index][cat][col]` holds these records. Existing saves
hold bare strings. **No migration script is needed** — the reader coerces:

```lua
local function as_column(v)
    if type(v) == "string" then return {kind = "item", name = v} end
    return v
end
```

This is the whole compatibility story. `get_category_item_names` is re-exported from
`gui/stats.lua` for require-path stability, but nothing outside the module calls it and it
is not on the `mts-v1` remote interface, so the shape change has no external blast radius.

The validity check at `stats_data.lua:297` (`prototypes.item[name]`) must become
kind-aware, or it will silently drop every fluid column on load.

---

## Architecture

`gui/stats_data.lua` is already 412 lines and `gui/stats.lua` 368 — both past the ~300
ceiling in the house Lua style. This work adds a quality axis, a fluid axis and a batched
count pipeline, so it splits rather than grows:

```
gui/stats/quality.lua     chain walk, feature gate, per-force unlocked set
gui/stats/discovery.lua   prototype scans + unlock depth (items and fluids)
gui/stats/columns.lua     column records, categories, defaults, storage resolution
gui/stats/counts.lua      the batched read pipeline
gui/stats/panel.lua       frame chrome: titlebar, selector rows, scroll
gui/stats/grid.lua        the stats table: header, sort row, data rows
gui/stats/handlers.lua    click / elem-changed routing
gui/stats.lua             thin facade: public API + nav wiring
```

Each module returns one table; everything else is `local`. `gui/stats.lua` keeps its
current public surface — `build_stats_gui`, `toggle`, `on_gui_click`, `on_gui_elem_changed`,
`on_player_created`, `invalidate_categories`, `get_category_item_names` — so all three
callers (`control.lua`, `gui/nav.lua`, `events/gui_state.lua`) are untouched.

---

## The Count Pipeline

### Today's cost

`M.get_count(force, item, precision)` calls `surface_utils.owned_surfaces_by_force` on
**every invocation**, from a nested `teams × cols` loop. That helper is O(all surfaces) and
each surface runs `get_owner`, whose platform branch is O(forces × platforms). On a
10-team Space Age server on the Science tab that is ~70 full surface scans per rebuild —
and the panel rebuilds on every click, including sort toggles.

The statistics reads were never the bottleneck. This is.

### The restructure

Replace `get_count` with a batched `counts.collect(forces, columns, precision, quality_view)`:

1. **Resolve ownership once.** One pass over `game.surfaces` builds `surface → owner`, then
   group by force. Collapses `teams × cols × surfaces` down to a single scan.
2. **Fetch statistics once per (force, surface).** One `get_item_production_statistics` and
   one `get_fluid_production_statistics`, hoisted out of the column loop.
3. **Drop the closure-allocating pcalls.** `pcall(function() return f(x) end)` becomes
   `pcall(f, x)`, or a single pcall around the per-surface block. The docs declare no
   raised errors for an invalid `FlowStatisticsID`, so these are defensive, not required.

### The quality fan-out gate

The measured split between `input_counts` and `get_input_count` yields a cheap test for
whether an item has *ever* been produced at a non-normal quality by this force:

```lua
local merged_all = flat[name] or 0          -- input_counts: merged
local normal_all = istats.get_input_count(name)   -- bare string: normal only
local multi_quality = merged_all ~= normal_all
```

If they are equal the item is normal-only for that force, so **every** quality read can be
skipped for that cell in every view. Most items in most bases are normal-only, so this
collapses the fan-out to the handful of cells that actually need it, at a cost of one extra
all-time read per (force, column, surface).

For a cell that fails the gate, expand it once on the all-time axis: read per-quality
all-time across the chain, keep the qualities with nonzero totals, and sum timed reads over
that set only. This is sound because the counters are cumulative and non-negative — any
timed window is bounded by all-time, so all-time zero implies window zero. Gating on
`is_quality_unlocked` instead would silently drop scripted or cheated production at a
locked quality — quietly reintroducing the under-reporting this plan exists to fix.

Resulting cost per rebuild:

| view | cost |
| --- | --- |
| All-time, merged | one dict read per force×surface — **cheaper than today** |
| All-time, single quality | one call per cell |
| Timed, single quality | one call per cell — same as today |
| Timed, merged, normal-only cell | one call per cell |
| Timed, merged, multi-quality cell | one call per quality with nonzero all-time production |

`Q` is bounded by the qualities a cell was actually produced at, not the chain length —
typically 1–2 even on a quality-heavy save. (The gate detection itself costs chain-length
all-time reads, but only for cells already known to be multi-quality.) On the 2.1 branch `input_quality_counts` collapses the timed merged path further;
feature-detect it (`if istats.input_quality_counts then`) and keep the chain-sum fallback.

---

## Quality Selector

A fourth button row, between the time-period row and the show-offline checkbox, rendered
**only** when `script.feature_flags.quality` is set and the chain has more than one entry.
Base-only installs see no change at all.

- **Merged** (default, and the current behaviour once fixed) plus one button per quality.
- Buttons use `quality/<name>` sprites — verified valid — with the quality's
  `localised_name` in the tooltip. No hand-built rich text needed.
- The row shows the union, across rendered teams, of **unlocked qualities plus any quality
  the gate found production at** — not just the viewing player's set. On a competitive mod
  you must be able to select legendary to see who is ahead on it before your own force has
  researched it, and a quality with real production must be selectable even if no force has
  formally unlocked it.
- Summation is **data-gated per force** (the fan-out gate), never unlock-gated.
  `is_quality_unlocked` is a UI affordance only, where a miss costs a button, not a number.

Selection lives in `storage.stats_gui_state[player_index].quality`, alongside `category`
and `precision`, with `"merged"` as the sentinel default. The read is tolerant, like the
column reader: a stored name that no longer resolves in `prototypes.quality` (quality mod
removed mid-save) coerces back to `"merged"`.

### Cell tooltips

In merged mode, a cell whose column passed the `multi_quality` gate gets a per-quality
breakdown tooltip built from the same numbers the sum already computed — free. Lines use
`[item=NAME,quality=Q]`, confirmed to render a quality-badged icon. Normal-only cells get
no tooltip, which is also the honest signal that there is nothing to break down.

---

## Fluids Tab

A sixth category, curated rather than auto-filled, seeded with guarded defaults:

```lua
local DEFAULT_FLUIDS = {
    "crude-oil", "petroleum-gas", "sulfuric-acid",
    "light-oil", "heavy-oil", "lubricant", "water", "steam",
}
```

Every entry is dropped unless the prototype exists and is visible, so a modpack lacking any
of them silently shows fewer. On our test save all eight exist and are exactly the pack's
complete real fluid set, leaving 8 of 16 slots free for players.

- **Picker:** `elem_type = "fluid"` with `elem_filters = {{filter = "hidden", invert = true}}`.
  Fluid prototypes support filters; signal buttons do not, which is why the tab is typed
  rather than using a universal signal picker. Note the filter does **not** exclude
  `parameter` fluids — they are not hidden (probe 2A), and `FluidPrototypeFilter` has no
  `parameter` variant in 2.0.77. The shipped item picker runs filterless without surfacing
  parameter items, so the engine most likely excludes them from pickers natively — verify
  at playtest. Defence in depth regardless: `on_gui_elem_changed` re-validates every pick
  against the visibility check below, so a junk pick can never reach storage.
- **Visibility** needs three flags, not the two `is_visible_item` uses:
  `not hidden and not hidden_in_factoriopedia and not parameter`.
  Without the third, 10 of 18 fluids on our test save are blueprint placeholders.
- **Fallback:** if *zero* seed entries survive (a total conversion with none of these),
  fall back to discovered fluids sorted by unlock depth, so the tab is never empty.
- **Ordering** reuses `sort_by_unlock_depth`. Fluids with no producing recipe (water) fall
  through to depth 0, which is correct — no boiler/fusion/tile scanning is required for a
  curated tab. That machinery is only needed if the tab ever goes fully auto-discovered.

Other tabs stay item-only. The column record already supports `kind = "fluid"` anywhere, so
allowing fluids in Custom later is a picker change with no migration.

---

## Bugs Fixed Along The Way

| bug | where | note |
| --- | --- | --- |
| Normal-quality-only under-reporting | `stats_data.lua:343,347` | the headline fix |
| `parameter` prototypes not excluded | `is_visible_item`, `stats_data.lua:74` | free insurance for items; mandatory for fluids |
| Primary-producer heuristic breaks on mixed recipes | `stats_data.lua:161` | `#item_products == 1` also true for one item + one fluid; measured safe to fix |
| `main_product` can be `""` | `stats_data.lua:155` | treat as nil; 0 occurrences today |
| `hidden_from_flow_stats` producers read zero forever | new guard | 0 occurrences today; cheap guard |
| Redundant surface resolution per cell | `stats_data.lua:337` | the real perf bug |
| Dead guards (`proto.group and`, `tech.effects or {}`, `recipe.products or {}`) | various | non-optional per docs; `mineable_properties.products or {}` is genuinely needed |

---

## Non-Goals

- **Per-column quality pinning.** Principle 4. The record shape leaves room for it.
- **Buildings / Kills tabs.** `get_entity_build_count_statistics` and
  `get_kill_count_statistics` are the same shape and become nearly free once columns are
  typed records — but they are not in scope here.
- **Fluids in non-Fluids tabs.** Data model supports it; picker does not yet.
- **Consumption (`output`) figures.** The panel reads `input` (production) only, unchanged.

---

## Implementation Order

Each step is independently shippable and playtestable.

1. **Extract modules.** Pure move, no behaviour change. Establishes the file split so the
   later diffs stay readable.
2. **Batch the count pipeline.** `collect` replaces `get_count`; ownership resolved once.
   No user-visible change except speed. Verify numbers are unchanged first.
3. **Column records + tolerant reader.** Still item-only, still one picker. Saves keep working.
4. **Fix the under-reporting.** All-time switches to `input_counts`; timed sums the chain.
   This alone closes the correctness bug, before any new UI exists.
5. **Quality selector + cell tooltips.** The fan-out gate lands here.
6. **Fluids tab.** Seeds, `parameter` filter, fluid picker, fluid statistics path.
7. **Prototype-scan cleanups.** Primary-producer heuristic, `main_product`, dead guards.

Steps 1–2 and 4 are worth doing even if the fluid and quality features were dropped
entirely.

---

## Playtest Checklist

House rule: commit locally per step; push only after in-game confirmation.

1. **Step 2:** counts identical to pre-restructure across teams × categories × periods —
   the equivalence check that keeps step 4's semantic change bisectable.
2. **Step 4:** a quality-producing team's All-time total visibly rises (the 108 → 208
   class of change); a normal-only team's numbers do not move at all.
3. **Step 5:** selector row appears only on quality-enabled saves; a base-only install
   shows zero UI change. Cell tooltips render quality-badged icons —
   `[item=NAME,quality=Q]` is verified in **chat**, not yet inside a tooltip.
4. **Step 6:** open the fluid picker and confirm `parameter-0 … parameter-9` are absent;
   fractional fluid counts format sanely at every magnitude.
5. **Multiplayer smoke:** two players on different teams with the panel open — clicks,
   sorts and column edits stay in sync, no desync.

---

## Risks

- **Step 2 must be numerically verified before step 4** changes what the numbers mean.
  Restructure and semantic change in one commit would make a regression un-bisectable.
- **The 2.1 branch** shares one implementation, but `input_quality_counts` must stay behind
  a feature-detect and never a version check.
- **Quality chain length is unbounded.** Nine today. If the selector row ever overflows on
  some pack, it degrades to a dropdown — decide when we see it, not preemptively.
- **A quality not linked into the chain would be invisible.** The walk follows `.next` from
  `normal`, so a mod adding a quality nothing points at would never be summed or offered.
  On our test save the only unreachable prototype is the `quality-unknown` placeholder,
  which is exactly what we want dropped — but the failure mode is silent. If a pack ever
  reports `#chain + 1 ~= table_size(prototypes.quality)` for a *non-hidden* prototype,
  revisit.
