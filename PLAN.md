# Multi Team Support - Force/Team Naming Refactor Plan

## Context

The mod currently names forces after the player who created them (`"force-bob"`). This breaks down when teams have multiple players and the leader leaves -- the team is still named after someone who's gone. Additionally, there are bugs with research not resetting on team leave, a dangling default Nauvis surface, and missing per-team planet creation/links.

This refactor changes force naming to a numbered pool (`"team-1"`, `"team-2"`, ...), fixes research handling, and optionally adds per-team planets when Space Age DLC is present.

---

## Coding Guidelines

- **Small functions, small files**: Prefer many focused functions over large monolithic ones. Break files up when they grow.
- **Organize with folders**: Group related files into directories (e.g. `shared/`, `prototypes/`, `gui/`).
- **Prefer Factorio events over tick-based polling**: Only use `on_tick`/`on_nth_tick` when absolutely necessary (Follow Cam position tracking, milestone polling). For everything else, use proper Factorio events (`on_research_finished`, `on_player_changed_force`, etc.).
- **Verify Factorio 2.0 API**: Before using any API call, consult BOTH https://lua-api.factorio.com/latest/ (API reference) AND https://github.com/wube/factorio-data (prototype source — shows how Wube's own base/space-age mods structure planets, connections, and other prototypes at data stage).
- **Comment generously**: Add comments explaining intent and logic so the codebase is easy for AI and humans to understand.
- **Be DRY (Don't Repeat Yourself)**: Extract shared logic into reusable functions/modules. Avoid duplicating code.

---

## Design Decisions

- **Team pool**: Pre-create a large fixed pool (e.g. 20 teams) at data stage. Assign dynamically at runtime. Feels dynamic to players.
- **Research on leave**: Reset to baseline (`game.forces.player`). Departing players lose team research.
- **Space Age**: Optional dependency. Per-team planets + connections when available; fall back to current surface cloning when not.
- **Force prefix**: `"team-"` (configurable later if needed). Internal names: `"team-1"` through `"team-N"`.
- **Display names**: Stored in `storage.team_names[force_name]`. Defaults to `"Team 01"`, can be customized later.

---

## Phase 1: Data Stage - Planet & Connection Prototypes (Space Age only)

**New files to create:**

1. **`settings.lua`** - Startup setting `mts_max_teams` (numeric, default 20, range 2-20). **Note**: This file must exist before Phase 2 since `on_init` reads this setting to know how many forces to pre-create.

2. **`shared/planets.lua`** - Planet variant name lists per base planet. Each team gets a nauvis variant. Borrow naming pattern from Team Starts (nuvira, novaris, etc.) but generate our own names. Structure:
   ```lua
   return { nauvis = {"nauvis-t1", "nauvis-t2", ...}, gleba = {...}, ... }
   ```

3. **`shared/connections.lua`** - Connection topology between planet variants. Each team's nauvis connects to their assigned expansion planets.

4. **`shared/connection_types.lua`** - Base connection type references.

5. **`prototypes/planets.lua`** - Deep-copy base planet prototypes for each variant (following Team Starts pattern at `/home/shobhitg/src/team-starts/prototypes/planets.lua`).

6. **`prototypes/connections.lua`** - Deep-copy base space-connection prototypes for variant connections.

7. **Update `data.lua`** - Conditionally require prototype files when Space Age is active.

---

## Phase 2: Force Naming Reform

**Files to modify:** `force_utils.lua`, `control.lua`, `helpers.lua`

1. **New storage tables** (in `on_init` in `control.lua`):
   - `storage.team_pool = {}` - tracks which team slots are available/occupied (`{1: nil, 2: "occupied", ...}`)
   - `storage.map_force_to_planet = {}` - maps `"team-1"` to home planet name (Space Age only)
   - `storage.map_planet_to_force = {}` - reverse mapping (Space Age only)
   - `storage.team_names = {}` - display names (`"team-1" -> "Team 01"`)
   - Keep existing `storage.team_leader`

2. **Pre-create forces** in `on_init`:
   ```lua
   for i = 1, max_teams do
     game.create_force("team-" .. i)
     -- set up diplomacy, cease-fire, spectator
   end
   ```

3. **Rewrite `force_utils.create_player_force(player)`** -> **`force_utils.claim_team_slot(player)`**:
   - Find first unoccupied slot in `storage.team_pool`
   - Reset the force's tech tree (un-research everything), then copy baseline from `game.forces.player`
   - Assign player to that force
   - Set `force.color = player.color`
   - Set `storage.team_leader[force_name] = player.index`
   - Set `storage.team_clock_start[force_name] = game.tick` (team birth, only if not already set)
   - Mark slot as occupied
   - **Called when**: player clicks "Spawn" from landing pen, NOT when they first enter the pen. Pen players stay on the spectator force (which already has restricted permissions for view/chat/GUI only). Flow: spectator force → claim_team_slot() → team-N force. This keeps `game.forces.player` as a clean, untouched research baseline template.

4. **Add `force_utils.release_team_slot(force_name)`**:
   - Mark slot as available in `storage.team_pool`
   - Clear `storage.team_leader[force_name]`
   - Reset force tech tree to prevent stale research leaking to next occupant

5. **Update `helpers.lua`**: `display_name()` should use `storage.team_names[force_name]` instead of parsing player name from force name.

---

## Phase 3: Update All Force Name Pattern Matches

**Files with `"force%-"` patterns to update to `"team%-"`:**

- `surface_utils.lua` (~lines 17, 28, 70) - surface ownership detection
- `gui/friendship.lua` (~lines 133, 135) - force filtering
- `gui/stats.lua` (~line 257) - force filtering
- `spectator.lua` (~line 177) - force filtering
- `force_utils.lua` (~line 253) - force filtering
- `compat/voidblock.lua` (~line 79) - surface naming
- `helpers.lua` (~line 32) - display name extraction

---

## Phase 4: Surface Management Reform

**Files to modify:** `surface_utils.lua`, `compat/vanilla.lua`, `compat/voidblock.lua`

**When Space Age is active:**
- Each team's home surface IS the planet variant's surface (lazy creation via `get_or_create_planet_surface()`)
- `surface_utils.get_owner()` uses `storage.map_planet_to_force` lookup instead of parsing surface names
- Lock `nauvis` space location, hide `nauvis` surface for all team forces
- Unlock each team's planet variant

**When Space Age is NOT active (fallback):**
- Keep current surface cloning approach but use new naming: `"team-1-nauvis"` instead of `"force-bob-nauvis"`
- `surface_utils.get_owner()` parses `"^(team%-%d+)%-"` pattern

**Update `compat/vanilla.lua`**: Surface creation uses planet variant or falls back to `"team-N-nauvis"`.

**Update `compat/voidblock.lua`**: Same pattern - use planet variant surface or fall back.

---

## Phase 5: Team Leader Simplification

**File to modify:** `force_utils.lua`

**Simplify `remove_from_team(player)`:**

The current logic has 3 branches (solo, owner-leaving, non-owner-leaving) with complex force-swapping for the owner case. With numbered forces, **the force swap is eliminated entirely**:

1. **Solo player leaving**: Release team slot back to pool. Player gets assigned a fresh slot (or goes to landing pen with no force).
2. **Leader leaving**: Elect new leader from remaining members, update `storage.team_leader`. Departing player gets a fresh team slot from pool.
3. **Non-leader leaving**: Same as leader leaving but skip election (leader stays).

In all cases: the team's force name stays the same. No swapping, no renaming.

**Leader privileges remain limited to**: kick (`/mts-kick`), accept buddy join requests, rename team (`/mts-rename <name>`).

### Team Rename Feature

- Add `/mts-rename <new name>` command in `commands.lua` (reference: Team Starts' `/rename` at `scripts/commands.lua:75-106`)
- Only the team leader can rename (check via `force_utils.is_team_leader(player)`)
- Updates `storage.team_names[force_name]` with the new display name
- Broadcast rename to all team members and optionally to the server
- Optionally also expose this as a GUI text field in the team/surfaces panel for the leader
- Validate: non-empty, reasonable length limit (e.g. 32 chars), no duplicate names

### Team Name Visibility

Since `helpers.display_name()` is used across all GUIs and chat to render force names, updating it to return `storage.team_names[force_name]` (e.g. `"The Pioneers"` or default `"Team 01"`) will automatically propagate team names everywhere (surfaces, stats, research, friendship, spectator, landing pen, chat).

Additionally, add a `/mts-teams` command in `commands.lua` that prints a full team-number-to-name mapping:
```
team-1: The Pioneers (leader: bob, 3 players)
team-2: Team 02 (leader: alice, 1 player)
team-3: (unclaimed)
```

The team number (`team-1`) stays visible as a subtle label/tooltip in GUIs so players always know the underlying team ID alongside the custom display name.

---

## Phase 6: Research Bug Fix

**File to modify:** `force_utils.lua`

In `remove_from_team()`, when the departing player gets a new force:
- Call `copy_force_state(game.forces.player, new_force)` (baseline reset)
- NOT `copy_force_state(old_team_force, new_force)` (which is the current bug)

This applies to both the old line ~172 (`copy_force_state(old_force, swap_force)`) and line ~198 (`copy_force_state(old_force, own_force)`).

---

## Phase 7: Default Nauvis Cleanup

**File to modify:** `control.lua`

In `on_init`, after creating all team forces:
```lua
for each team force do
  force.lock_space_location('nauvis')        -- Space Age only
  force.set_surface_hidden('nauvis', true)   -- Space Age only
  force.unlock_space_location(home_planet)   -- Space Age only
end
```

Add `on_technology_effects_reset` and `on_force_reset` handlers to re-lock nauvis and re-unlock team planet variants (following Team Starts pattern at `/home/shobhitg/src/team-starts/scripts/universe.lua` lines 89-127).

---

## Phase 8: Migration Support (for existing saves)

**New file:** `migrations/mts_0_3_0.lua` (or appropriate version)

Migration for existing saves must:
1. Create new `"team-N"` forces for each existing `"force-*"` force
2. Move players and entities from old forces to new ones (via `game.merge_forces()`)
3. Rebuild all storage tables with new force names
4. Handle surface renaming (rename `"force-bob-nauvis"` to `"team-1-nauvis"` or map to planet variant)

**Update `on_configuration_changed`** to handle the migration path.

> **Note**: This is the riskiest phase. `game.merge_forces()` transfers all entities but has side effects. Extensive testing needed with existing saves.

---

## Phase 9: GUI Redesign - Teams GUI

**Replace the current Surfaces/Players GUI with a unified "Teams GUI".**

**Files to modify:** `gui/surfaces.lua` (rewrite as `gui/teams.lua`), `gui/nav.lua`, `gui/friendship.lua`

### Layout: Team Cards

```
┌─ Teams ──────────────────────────────────────┐
│                                              │
│  ┌─ [Team 01: "The Pioneers"] ────────────┐  │
│  │ [Players] [Surfaces]         [👁 Watch] │  │
│  │                                        │  │
│  │  ★ bob (leader)  ● online  [🤝 Friend] │  │
│  │    alice          ● online              │  │
│  │    charlie        ○ offline             │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌─ [Team 02: "Solo Wolf"] ──────────────┐  │
│  │ [Players] [Surfaces]         [👁 Watch] │  │
│  │                                        │  │
│  │  ★ dave (leader)  ● online  [🤝 Friend] │  │
│  └────────────────────────────────────────┘  │
│                                              │
└──────────────────────────────────────────────┘
```

### Design Rules

- **Each team is a card**, colored with the team's force color
- **Force color = team leader's player color.** Set `force.color = leader.color` in `claim_team_slot()` and `pick_new_leader()`. When leader changes, force color updates.
- **All player names** across all GUIs (stats, research, teams, chat) rendered with their force color
- **Two tabs per card**: "Players" (member list, online status) and "Surfaces" (planets/platforms with spectate buttons)
- **Friendship button** appears next to the leader's name only, and only when the leader is online. If leader is offline, friendship control is unavailable. (Friendship is team-level but leader-controlled.) `gui/friendship.lua` kept as a module but called from `gui/teams.lua` rather than standalone.
- **Team rename**: Leader sees an editable text field for team name in the card header
- **"Watch" button** per card opens Follow Cam for that team (see Phase 10)
- **Own team card** visually distinct (highlighted border/background). Shows "Leave Team" button. Other teams' cards show buddy join request button (if enabled).
- **Milestone polling**: Use `on_nth_tick(300, ...)` for the milestone engine, not manual modulo check in `on_tick`

### What Stays Separate

- **Research GUI** (`gui/research.lua`) -- cross-team comparison, stays its own toggle
- **Stats GUI** (`gui/stats.lua`) -- cross-team leaderboard, stays its own toggle
- Both updated to use force colors and team display names

---

## Phase 10: Follow Cam GUI

**New file:** `gui/follow_cam.lua`

### Overview

A grid of live `camera` GUI widgets showing all players (or a selected team's players). Inspired by Viewports-by-CodeGreen which uses Factorio's `type = "camera"` element with per-tick position updates.

### Entry Point

- Launched from the "Watch" button on a team card in Teams GUI (Option C)
- Opens as a separate floating/draggable frame
- "Watch" on a specific team → shows only that team's players
- Could also have a nav button for "Watch All" (all teams)

### GUI Structure

```
┌─ Follow Cam: "The Pioneers" ──── [✕] ┐
│                                       │
│  ┌─ bob ─────┐  ┌─ alice ────┐       │
│  │            │  │            │       │
│  │  [camera]  │  │  [camera]  │       │
│  │            │  │            │       │
│  └────────────┘  └────────────┘       │
│                                       │
│  ┌─ charlie ─┐                        │
│  │            │                        │
│  │  [camera]  │                        │
│  │            │                        │
│  └────────────┘                        │
│                                       │
└───────────────────────────────────────┘
```

### Implementation Details (borrowing from Viewports-by-CodeGreen)

- Each cell: `type = "camera"` widget (position, surface_index, zoom) inside a styled frame
- **Update via `on_nth_tick(2)`** (~30 FPS): Loop through all active follow-cam cameras, update both `camera.position = target_player.position` AND `camera.surface_index = target_player.surface.index`. Using every-2-ticks instead of per-tick halves server cost with no visible difference for minimap-style cameras. The actual camera rendering is client-side (GPU), so the server cost is only the position/surface property assignments -- negligible even with 60 cameras.
- **Player label** above each camera, colored with force color
- **Surface handling**: Each camera widget tracks the target player's current surface, updated every tick so it follows them across planets seamlessly
- **Grid layout**: Use Factorio's `type = "table"` with column_count based on player count (2-3 columns)
- **Zoom**: Default 0.5, optionally adjustable per camera cell
- **Offline players**: Hide or grey out their camera cell
- **Performance**: Camera widgets are lightweight -- Factorio renders them natively. The only script cost is position updates per tick per camera. Even 20 cameras is negligible.

### Storage

```lua
storage.follow_cam = {}  -- {viewer_index: {cameras = {target_index: camera_element, ...}, team = force_name}}
```

---

## Phase 11: Tech Records & Announcements

**Files to modify:** `control.lua` (on_research_finished handler), `force_utils.lua` (team clock)

### Team Clock

- `storage.team_clock_start[force_name] = game.tick` -- set when the **first player** claims the team slot (in `claim_team_slot()`), never reset after that regardless of who joins/leaves
- This is the team's "birth tick" -- all research times are measured relative to this
- Teams pre-created at data stage have no clock until first player joins

### Storage for Tech Records

```lua
storage.tech_records = {
  ["automation"] = {
    first = { team = "team-1", tick = 54000, elapsed = 12000 },
    fastest = { team = "team-3", tick = 108000, elapsed = 9500 },
  },
  ["logistics"] = { ... },
  ...
}
```

- `first`: the team that researched this tech before anyone else (absolute tick + elapsed from their team clock)
- `fastest`: the team that researched it in the shortest elapsed time relative to their team clock start
- `elapsed = research_tick - storage.team_clock_start[force_name]`

### on_research_finished Logic

```
1. Compute elapsed = game.tick - storage.team_clock_start[force_name]
2. Record in storage.tech_research_ticks[force_name][tech_name] = { tick = game.tick, elapsed = elapsed }

3. If tech has no "first" record:
   → Set storage.tech_records[tech].first = { team, tick, elapsed }
   → Also set storage.tech_records[tech].fastest = same (they're the first, so also fastest by default)
   → Announce to ALL forces: "Team XYZ was the first to research [tech]!"
   → Do NOT also announce speed record (would be redundant with "first" announcement)

4. If tech already has a "first" record AND elapsed < current fastest record:
   → Store previous record for announcement
   → Set storage.tech_records[tech].fastest = { team, tick, elapsed }
   → Announce to ALL forces: "Team ABC is fastest to research [tech] so far
     by researching in X hours Y mins (previous record by Team XYZ: X hours Y mins)"

5. If elapsed >= current fastest record:
   → No announcement (silent)
```

### Time Formatting

- Convert elapsed ticks to human-readable: `ticks / 60 / 60` for minutes, format as "Xh Ym" or "Ym Zs" depending on magnitude
- Helper function in `helpers.lua`: `helpers.format_elapsed(ticks)` → `"2h 15m"` or `"45m 30s"`

### Science Production Milestones

Track per-team cumulative production of every science pack, with announcements at configurable milestones.

### Generic Milestone Tracker

Instead of a science-specific system, build a **generic milestone engine** that can track any measurable quantity. Science packs, landfill, space platforms, etc. are all just different "trackers" registered with their own thresholds and count functions.

**Config file:** `milestones.lua` (new file) -- single place to define all tracked categories:

```lua
local milestones = {}

milestones.trackers = {
  -- Each tracker defines: what to measure, thresholds, and how to read the count
  {
    category = "science",
    label = "science pack",           -- for announcements: "produced 100 [label]"
    announce_first = true,            -- announce "first to produce" (before any threshold)
    thresholds = { 100, 500, 1000, 5000, 20000 },
    -- items: discovered dynamically at runtime (all "tool" type prototypes)
    discover_items = function()
      local items = {}
      for name, proto in pairs(prototypes.item) do
        if proto.type == "tool" then items[name] = true end
      end
      return items
    end,
    -- how to read count for a given force + item
    get_count = function(force, item_name)
      return force.item_production_statistics.get_flow_count{
        name = item_name, input = true,
        precision_index = defines.flow_precision_index.one_thousand_hours,
        count = true
      }
    end,
  },
  {
    category = "landfill",
    label = "landfill",
    announce_first = false,           -- too trivial, skip "first to produce" announcement
    thresholds = { 100, 500, 2000, 10000 },
    discover_items = function() return { ["landfill"] = true } end,
    get_count = function(force, item_name)
      return force.item_production_statistics.get_flow_count{
        name = item_name, input = true,
        precision_index = defines.flow_precision_index.one_thousand_hours,
        count = true
      }
    end,
  },
  {
    category = "space_platform",
    label = "space platform tile",
    announce_first = false,           -- skip "first to produce" announcement
    thresholds = { 50, 200, 1000 },
    discover_items = function() return { ["space-platform-foundation"] = true } end,
    get_count = function(force, item_name)
      return force.item_production_statistics.get_flow_count{
        name = item_name, input = true,
        precision_index = defines.flow_precision_index.one_thousand_hours,
        count = true
      }
    end,
  },
  -- Add more trackers here as needed:
  -- {
  --   category = "rockets",
  --   label = "rocket launch",
  --   thresholds = { 1, 10, 50 },
  --   discover_items = function() return { ["rocket-part"] = true } end,
  --   get_count = function(force, item_name) ... end,
  -- },
}

return milestones
```

**To add a new tracked category**: just append to `milestones.trackers` with a category name, thresholds, item discovery function, and count reader. The engine handles everything else.

**Dynamic item discovery**: Each tracker's `discover_items()` runs at `on_init` and `on_configuration_changed`. Science packs auto-detect from any mod. Fixed items like landfill just return a hardcoded set.

**Unified storage**:

```lua
storage.milestone_records = {
  ["science:automation-science-pack"] = {  -- "category:item" key
    [0] = {                                -- "first to produce" (announce_first only)
      first = { team = "team-1", tick = 3600, elapsed = 3600 },
      fastest = { team = "team-1", tick = 3600, elapsed = 3600 },
    },
    [100] = { ... },                       -- threshold milestones
    [500] = { ... },
  },
  ["landfill:landfill"] = {
    [100] = { ... },                       -- no [0] entry since announce_first = false
  },
}

storage.milestone_reached = {
  -- tracks which milestones each team has already crossed
  ["team-1"] = {
    ["science:automation-science-pack"] = { [1] = true, [100] = true },
    ["landfill:landfill"] = { [1] = true },
  },
}

storage.milestone_items = {
  -- populated by discover_items() at init, keyed by category
  ["science"] = { ["automation-science-pack"] = true, ["logistic-science-pack"] = true, ... },
  ["landfill"] = { ["landfill"] = true },
}
```

**Periodic check logic** (every 300 ticks / 5 seconds, via `on_nth_tick(300)`):

```
For each tracker in milestones.trackers:
  For each item in storage.milestone_items[tracker.category]:
    For each occupied team:
      count = tracker.get_count(force, item)

      -- "First to produce" check (count >= 1, separate from thresholds)
      If tracker.announce_first AND count >= 1 AND not already reached for key+0:
        Mark key+0 as reached
        elapsed = game.tick - storage.team_clock_start[force_name]
        If no "first" record for key+0:
          → Set first record
          → Announce: "Team XYZ is the first to produce [item display name]!"
        If elapsed < fastest (or no fastest):
          → Set fastest, announce speed record

      -- Threshold checks (100, 500, 1000, etc.)
      For each threshold in tracker.thresholds:
        key = category .. ":" .. item
        If count >= threshold AND not already reached:
          Mark as reached
          elapsed = game.tick - storage.team_clock_start[force_name]

          If no "first" record for this key+threshold:
            → Set first record
            → Announce: "Team XYZ is the first to produce [threshold] [tracker.label]!"

          If elapsed < fastest record (or no fastest):
            → Set fastest record
            → Announce speed record with previous record info
```

**Performance**: With ~3 categories, ~10 items total, ~6 thresholds avg, ~20 teams = ~3600 checks every 5 seconds. Still negligible -- `get_flow_count` is a cheap API call.

---

### End-of-Game Rewards Data

All data needed for rewards is in storage:
- `storage.tech_records` -- first/fastest per technology
- `storage.milestone_records` -- first/fastest per science pack, landfill, platform, etc.
- `storage.tech_research_ticks` -- full research timeline per team

This data can be queried at game end to compute rewards (e.g., "Most First Discoveries", "Speed Demon", "Science Leader", etc.). The exact reward system is left for a future phase but the data foundation is in place.

---

## Implementation Order

1. `settings.lua` from Phase 1 (needed for `mts_max_teams`) - must exist before anything else
2. Phase 2 (force naming) + Phase 3 (pattern updates) - foundational change
3. Phase 5 (leader simplification) + Phase 6 (research fix) - depend on Phase 2
4. Phase 11 (tech records + milestone engine) - depends on Phase 2 for team clock
5. Phase 9 (Teams GUI) - depends on Phase 2 for team names/colors
6. Phase 10 (Follow Cam) - depends on Phase 9 for "Watch" button entry point
7. Rest of Phase 1 (planet/connection prototypes) + Phase 4 (surface reform) - Space Age specific
8. Phase 7 (nauvis cleanup) - depends on Phase 4
9. Phase 8 (migration) - last, after everything works for new games

---

## Verification Plan

1. **New game without Space Age**: Start a new game, verify teams are named `"team-1"`, etc. Verify surface cloning works with new naming. Test buddy join, leave, kick, research reset.
2. **New game with Space Age**: Verify per-team planet variants are created. Verify space connections work. Verify nauvis is hidden. Verify planet discovery tech unlocks correct variant.
3. **Buddy join flow**: Player A spawns (gets team-1). Player B requests to join team-1. Verify B joins A's force. A leaves. Verify B becomes leader, force stays "team-1". A gets "team-2".
4. **Research reset**: Join a team with advanced research. Leave. Verify new force has only baseline research.
5. **Teams GUI**: Verify card layout, force colors match leader color, friendship button only on online leader, tabs switch correctly.
6. **Follow Cam**: Open Watch from Teams GUI. Verify camera grid shows target players. Verify cameras track position in real-time. Verify offline players handled. Test with players on different surfaces.
7. **Force colors**: Change team leader (old leader leaves). Verify force color updates to new leader's color. Verify all GUIs reflect the new color.
8. **Tech records**: Research a tech on team-1 first, verify "first to research" announcement. Research same tech on team-2 faster (relative to team clock), verify speed record announcement. Research same tech slower on team-3, verify no announcement.
9. **Milestones**: Produce science packs, verify "first to produce" announcement at count=1, verify threshold announcements at 100/500/etc, verify speed records. Produce landfill, verify NO "first to produce" announcement (announce_first=false), verify threshold announcements only.
10. **Force recycling**: Player spawns (team-1), researches techs, leaves. New player claims team-1. Verify new player has baseline research only, not previous occupant's.
11. **Migration**: Load an existing save with "force-bob" style forces. Verify migration converts to numbered teams correctly.

---

## Key Files Summary

| File | Changes |
|------|---------|
| `force_utils.lua` | Force naming, claim/release pool, leader simplification, research fix, force color sync |
| `control.lua` | New storage tables, force pre-creation, nauvis hiding, event handlers, on_nth_tick for follow cam |
| `surface_utils.lua` | Ownership detection via map lookup or new pattern |
| `helpers.lua` | Display name from `storage.team_names`, force-colored player names, `format_elapsed()` |
| `compat/vanilla.lua` | Surface creation with planet variants or new naming |
| `compat/voidblock.lua` | Same as vanilla |
| `gui/teams.lua` | **New** - replaces `gui/surfaces.lua`, team cards with players/surfaces tabs |
| `gui/follow_cam.lua` | **New** - camera grid GUI with on_nth_tick(2) tracking |
| `gui/friendship.lua` | Kept as module, called from `gui/teams.lua`, leader-only when online |
| `gui/stats.lua` | Pattern update, force colors |
| `gui/research.lua` | Pattern update, force colors |
| `gui/nav.lua` | Update nav buttons (Teams replaces Surfaces/Players) |
| `spectator.lua` | Pattern update |
| `commands.lua` | Pattern update, `/mts-rename`, `/mts-teams` |
| `milestones.lua` | **New** - generic milestone tracker config (categories, thresholds, count functions) |
| `settings.lua` | **New** - max teams startup setting |
| `shared/planets.lua` | **New** - planet variant names (Space Age only) |
| `shared/connections.lua` | **New** - connection topology (Space Age only) |
| `prototypes/planets.lua` | **New** - planet prototypes (Space Age only) |
| `prototypes/connections.lua` | **New** - connection prototypes (Space Age only) |
| `data.lua` | Require new prototypes conditionally |
| `migrations/mts_0_3_0.lua` | **New** - save migration |
