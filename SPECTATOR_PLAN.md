# Spectator System — Implementation Plan

**Date:** 2026-04-05
**Status:** Draft — all major design items resolved, ready for implementation

## Problem Statement

In Multi-Team Support (vanilla, no god mode), players cannot view other players' surfaces
because chart data is not shared between forces. The Factorio API gates chart sharing
behind `set_friend()`, which also grants building access and turret immunity — an
unacceptable coupling for a competitive mod.

GPS tag clicking currently prints a rich-text tag to chat. When clicked, Factorio opens
a remote view on the target surface, but the player sees nothing (no chart data).

## Solution Overview

Adopt the **Biter Battles spectator force pattern**: a single dedicated `spectator`
force that is friends with all player forces, with `share_chart = true`. When a player
wants to view a non-friend's surface, temporarily swap them to the spectator force.
A permission group prevents any interaction beyond viewing and chatting.

Key difference from BB: players are **not physically teleported**. Their character stays
on their own surface. Only the force assignment changes.

## Design Principles

1. **Friends bypass spectator mode entirely.** If the target has friended the viewer,
   the viewer already has chart access — no force swap needed.
2. **Spectate from anywhere.** Players can spectate from their own base, from the
   Landing Pen, or while already viewing another surface.
3. **No persistent side effects.** When spectation ends, the player is fully restored
   to their original force with no gameplay impact.
4. **Admin-configurable notifications.** Spectation events are announced in chat,
   togglable by admin flag.
5. **Rich API.** All spectator state management is encapsulated in a dedicated
   `spectator.lua` module with debug logging everywhere.

---

## Architecture: `spectator.lua` Module

All spectator logic lives in a new `spectator.lua` module. This keeps the complex
state management out of `control.lua` and `platforms_gui.lua`, and provides a clean
API that both files call into. Every public function includes a `log()` call for
debug tracing.

### Full API Surface

```lua
local spectator = {}

-- ─── Setup ──────────────────────────────────────────────────────────
-- Called from on_init and on_configuration_changed.
-- Creates spectator force, permission group, and ensures all existing
-- player forces have the correct friendship/cease-fire/share_chart.
function spectator.init()

-- Called from create_player_force after force creation.
-- Sets up bidirectional friendship + cease-fire between the new force
-- and the spectator force. Enables share_chart on the new force.
function spectator.setup_force(new_force)

-- Called from on_init and on_load.
-- Ensures storage.spectator_real_force and storage.spectating_target exist.
function spectator.init_storage()

-- ─── Core Operations ────────────────────────────────────────────────
-- Begin spectating a target force's surface. Handles:
--   1. Save real force (if not already spectating)
--   2. Set storage.spectating_target
--   3. Swap to spectator force + permission group
--   4. Set character.destructible = false, show_on_map = false
--   5. Open remote view via set_controller
--   6. Announce spectation
-- Precondition: caller has already checked needs_spectator_mode().
function spectator.enter(player, target_force, surface, position)

-- Stop spectating. Handles:
--   1. Restore real force + Default permission group
--   2. Set character.destructible = true, show_on_map = true
--   3. Clear storage tables
--   4. Announce stop
-- Safe to call if player is not spectating (no-ops).
function spectator.exit(player)

-- Switch spectation target without leaving spectator force.
-- Updates storage.spectating_target and opens new remote view.
-- Only valid when player is already spectating.
function spectator.switch_target(player, target_force, surface, position)

-- Open a friend-view: direct remote view without spectator force swap.
-- The viewer stays on their own force (friendship gives chart access).
function spectator.enter_friend_view(player, surface, position)

-- ─── State Queries ──────────────────────────────────────────────────
-- Returns true if the player is currently on the spectator force
-- with a saved real force.
function spectator.is_spectating(player)

-- Returns the saved real force NAME (string) or nil.
function spectator.get_real_force(player)

-- Returns the player's effective force name — the real force if
-- spectating, otherwise the current force. Use this instead of
-- player.force.name when you need the "logical" force.
function spectator.get_effective_force(player)

-- Returns the target force NAME (string) or nil.
function spectator.get_target(player)

-- Returns true if the viewer's force needs spectator mode to view
-- the target force. False means friendship exists (direct view OK).
-- Accepts force objects, not names.
function spectator.needs_spectator_mode(viewer_force, target_force)

-- Given a surface, return the force name that owns it, or nil.
-- Checks space platform ownership and vanilla solo surface patterns.
function spectator.get_surface_owner(surface)

-- ─── Event Handlers ─────────────────────────────────────────────────
-- Called from on_player_controller_changed.
-- Detects remote-view exit (old=remote, new!=remote) and calls exit().
-- Does nothing when entering or switching remote views.
function spectator.on_controller_changed(player, old_controller_type)

-- Called from on_friend_toggle when a friendship changes.
-- Case A (friend added): if any spectator's real force now has access
--   to the target, upgrade them from spectator to friend-view.
-- Case B (friend removed): if any player is friend-viewing the target
--   and lost access, bounce them home.
function spectator.on_friend_changed(player_force, target_force, is_friend)

-- Called from on_player_left_game.
-- If the player was spectating, restore their force immediately.
function spectator.on_player_left(player)

-- Called from on_player_joined_game.
-- Verifies force is correct after reconnect. Defensive cleanup.
function spectator.on_player_joined(player)

-- ─── Chat ───────────────────────────────────────────────────────────
-- Returns the chat context prefix for a player, or "".
-- Spectator viewing B: "[on B's base][spectator] "
-- Friend viewing B:    "[on B's base][friend] "
-- On own base:         ""
function spectator.get_chat_prefix(player)

-- ─── Maintenance ────────────────────────────────────────────────────
-- Periodic chart cleanup: clears spectator force chart data for
-- surfaces with no active spectators. Call from on_nth_tick or similar.
function spectator.cleanup_charts()
```

### Debug Logging

Every public function logs entry and key state transitions:

```lua
function spectator.enter(player, target_force, surface, position)
    log("[multi-team-support:spectator] enter: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))
    -- ... implementation ...
    log("[multi-team-support:spectator] enter: done, force=" .. player.force.name)
end
```

Pattern: `[multi-team-support:spectator] <function>: <message>`. Always include player name
and relevant force/surface names. Log before and after state changes.

---

## Detailed Design

### 1. Spectator Force Setup

**Where:** `spectator.lua` — `spectator.init()`

```lua
function spectator.init()
    -- Create spectator force (idempotent)
    local spec = game.forces["spectator"]
    if not spec then
        spec = game.create_force("spectator")
        log("[multi-team-support:spectator] init: created spectator force")
    end
    spec.share_chart = true

    -- Friend + cease-fire with all existing player forces (both directions)
    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            spec.set_friend(force, true)
            force.set_friend(spec, true)
            force.share_chart = true  -- enable on all player forces
        end
        if force.name ~= "enemy" and force ~= spec then
            spec.set_cease_fire(force, true)
            force.set_cease_fire(spec, true)
        end
    end

    -- Permission group (idempotent)
    local p = game.permissions.get_group("spectator")
    if not p then
        p = game.permissions.create_group("spectator")
    end
    -- Deny everything first
    for action_name, _ in pairs(defines.input_action) do
        p.set_allows_action(defines.input_action[action_name], false)
    end
    -- Re-enable only safe actions (adapted from Biter Battles)
    local allowed = {
        "gui_click", "gui_checked_state_changed", "gui_confirmed",
        "gui_elem_changed", "gui_location_changed", "gui_selected_tab_changed",
        "gui_selection_state_changed", "gui_switch_state_changed",
        "gui_text_changed", "gui_value_changed",
        "remote_view_surface",
        "write_to_console",
        "toggle_show_entity_info",
        "clear_cursor",
        "open_character_gui",
        "change_active_quick_bar",
        "quick_bar_set_selected_page",
    }
    for _, name in ipairs(allowed) do
        p.set_allows_action(defines.input_action[name], true)
    end

    log("[multi-team-support:spectator] init: complete, permission group configured")
end
```

**Called from:** `control.lua` `on_init` and `on_configuration_changed`.

### 2. New Force Integration

**Where:** `spectator.lua` — `spectator.setup_force(new_force)`

```lua
function spectator.setup_force(new_force)
    new_force.share_chart = true
    local spec = game.forces["spectator"]
    if spec then
        new_force.set_friend(spec, true)
        spec.set_friend(new_force, true)
        spec.set_cease_fire(new_force, true)
        new_force.set_cease_fire(spec, true)
    end
    log("[multi-team-support:spectator] setup_force: " .. new_force.name)
end
```

**Called from:** `create_player_force()` in `control.lua`, after the existing cease-fire
loop.

### 3. Storage Tables

**Where:** `spectator.lua` — `spectator.init_storage()`

```lua
function spectator.init_storage()
    storage.spectator_real_force = storage.spectator_real_force or {}
    storage.spectating_target    = storage.spectating_target    or {}
end
```

**Called from:** `on_init`, `on_load`, and `on_configuration_changed` in `control.lua`.

### 4. GUI Changes — Replace GPS Buttons with Spectate Buttons

**Where:** `platforms_gui.lua` — `build_platforms_gui`

**Current behavior:** Each platform/surface row has a GPS sprite-button that prints a
rich-text GPS tag to chat. Clicking the tag in chat opens remote view.

**New behavior:** Replace the GPS button with a spectate button.

#### Button appearance:
- **Icon:** `"utility/show_enemy_on_map"` (built-in binoculars icon; swap for a
  custom spy-eye sprite later if desired)
- **Tooltip:** `"Spectate <player>'s <platform-name>"` or
  `"Spectate <player>'s base on <planet>"`
- **Tags:** `{sb_spectate = true, sb_target_force = "player-alice",
  sb_surface = "surface-name", sb_position = {x, y}}`

#### Filtering rules:
- **Hide for own surfaces:** Don't show spectate buttons for surfaces belonging to
  the viewing player's own force. Use `spectator.get_effective_force(player)` to
  determine the viewer's logical force (handles the case where they're already
  spectating someone and their current `player.force` is "spectator").
- **Show for all other players:** Both friends and non-friends get spectate buttons.
  The button handler decides whether to use spectator force or direct remote view.

#### Click handler logic (in `platforms_gui.on_gui_click`):

```lua
if element.tags and element.tags.sb_spectate then
    local player = game.get_player(event.player_index)
    local target_force = game.forces[element.tags.sb_target_force]
    local surface = game.surfaces[element.tags.sb_surface]
    local position = element.tags.sb_position or {x = 0, y = 0}

    -- Determine viewer's real force
    local viewer_force = game.forces[spectator_mod.get_effective_force(player)]

    if spectator_mod.needs_spectator_mode(viewer_force, target_force) then
        if spectator_mod.is_spectating(player) then
            -- Already spectating someone else — just switch target
            spectator_mod.switch_target(player, target_force, surface, position)
        else
            spectator_mod.enter(player, target_force, surface, position)
        end
    else
        -- Friend view — direct remote view
        spectator_mod.enter_friend_view(player, surface, position)
    end
    return true
end
```

### 5. Remote View API

**Resolved:** Factorio 2.0 (Space Age) supports the `surface` parameter in
`set_controller` for remote view:

```lua
player.set_controller({
    type = defines.controllers.remote,
    surface = target_surface,  -- SurfaceIdentification (name, index, or object)
    position = {x, y},         -- MapPosition
})
```

This keeps the player's character on their physical surface and opens a camera view
on the target surface. The BB codebase omits the `surface` parameter because BB
predates Space Age (single-surface game). Multi-Team Support requires it because every player
is on a different surface.

The character remains where it is — `player.physical_surface` and
`player.physical_position` stay the same, while `player.surface` reflects the
remotely-viewed surface. `player.controller_type` becomes `defines.controllers.remote`.

### 6. Controller Change Detection

**Where:** `spectator.lua` — `spectator.on_controller_changed()`

**Resolved:** The `on_player_controller_changed` event provides the previous controller
type. Exit spectator mode only when transitioning FROM remote TO non-remote:

```lua
function spectator.on_controller_changed(player, old_controller_type)
    -- Only act when LEAVING remote view (not entering or switching)
    if old_controller_type ~= defines.controllers.remote then return end
    if player.controller_type == defines.controllers.remote then return end

    -- Player exited remote view (Esc, or clicked back to own surface)
    if spectator.is_spectating(player) then
        log("[multi-team-support:spectator] on_controller_changed: " .. player.name
            .. " exited remote view, restoring force")
        spectator.exit(player)
    end
end
```

**Integration with existing handler in control.lua (lines 489-494):**
```lua
script.on_event(defines.events.on_player_controller_changed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.connected then
        spectator.on_controller_changed(player, event.old_controller_type)
        bounce_if_foreign(player)
    end
end)
```

Order matters: exit spectator mode FIRST (restoring real force), THEN bounce
(which uses the real force to determine home surface).

### 7. Friendship Changes During Spectation

**Where:** `spectator.lua` — `spectator.on_friend_changed()`

```lua
function spectator.on_friend_changed(player_force, target_force, is_friend)
    log("[multi-team-support:spectator] on_friend_changed: "
        .. player_force.name .. (is_friend and " friended " or " unfriended ")
        .. target_force.name)

    if is_friend then
        -- Case A: target_force just friended player_force.
        -- Any spectator whose real force is player_force AND who is spectating
        -- target_force can be upgraded to friend-view.
        -- NOTE: the friendship direction here is target_force → player_force,
        -- meaning player_force members now have chart access to target_force.
        for idx, target_fn in pairs(storage.spectating_target) do
            if target_fn == target_force.name then
                local real_fn = storage.spectator_real_force[idx]
                if real_fn == player_force.name then
                    local p = game.get_player(idx)
                    if p and p.connected then
                        -- Upgrade: restore real force, keep remote view
                        p.force = game.forces[real_fn]
                        game.permissions.get_group("Default").add_player(p)
                        if p.character then p.character.destructible = true end
                        p.show_on_map = true
                        storage.spectator_real_force[idx] = nil
                        storage.spectating_target[idx] = nil
                        p.print("[multi-team-support] You are now viewing as a friend.")
                        log("[multi-team-support:spectator] upgraded " .. p.name
                            .. " from spectator to friend-view")
                    end
                end
            end
        end
    else
        -- Case B: target_force unfriended player_force.
        -- Find players on player_force who are friend-viewing target_force's
        -- surfaces and bounce them home (they just lost chart access).
        for _, p in pairs(player_force.connected_players) do
            if p.controller_type == defines.controllers.remote then
                local owner = spectator.get_surface_owner(p.surface)
                if owner == target_force.name then
                    log("[multi-team-support:spectator] bouncing " .. p.name
                        .. " from friend-view (unfriended)")
                    p.print("[multi-team-support] " .. target_force.name:match("^player%-(.+)$")
                        .. " unfriended you. Returning to your base.")
                    -- Exit remote view → triggers on_controller_changed → bounce
                    p.set_controller({type = defines.controllers.character,
                                      character = p.character})
                end
            end
        end
    end
end
```

**Called from:** `platforms_gui.on_friend_toggle()`, passing the correct direction:

```lua
-- When player A (on player_force) toggles friend toward target_force:
-- This means player_force is friending target_force.
-- The chart sharing direction: target_force members can see player_force's chart.
-- So we call: on_friend_changed(target_force, player_force, new_state)
-- Wait — let's be precise about the direction.
```

**Friendship direction clarification:**

When player A calls `player_A.force.set_friend(target_force_B, true)`:
- A's force is now a friend of B's force
- Effect: B's turrets won't fire at A. A can build on B's entities.
- Chart sharing: if A's force has `share_chart = true`, A's chart data flows to B
  (because A is B's friend, B receives A's shared chart)

Wait — the relevant direction for VIEWING is the reverse:
- For A to SEE B's chart, B must friend A (B.set_friend(A, true)) AND B.share_chart = true
- For B to SEE A's chart, A must friend B (A.set_friend(B, true)) AND A.share_chart = true

So in `on_friend_toggle`, when player A checks the "friend B" checkbox:
- `player_A.force.set_friend(target_force_B, true)` is called
- This means B can now see A's chart (A shared toward B)
- For A to see B's chart, B must separately friend A

The on_friend_changed call should check: does the NEWLY FRIENDED force now have
chart access? Specifically, when A friends B, check if any spectator was spectating
A's surfaces from B's force — they can now see A's chart as a friend.

```lua
-- In on_friend_toggle:
spectator.on_friend_changed(player.force, target_force, new_state)
-- player.force just changed its friendship toward target_force.
-- If new_state=true: target_force members can now see player.force's chart.
-- If new_state=false: target_force members lose chart access to player.force.
```

### 8. Chat Prefix During Spectation

**Where:** `spectator.lua` — `spectator.get_chat_prefix()`

```lua
function spectator.get_chat_prefix(player)
    -- Case 1: spectating (on spectator force)
    local target_fn = storage.spectating_target and storage.spectating_target[player.index]
    if target_fn then
        local target_name = target_fn:match("^player%-(.+)$") or target_fn
        return "[on " .. target_name .. "'s base][spectator] "
    end

    -- Case 2: friend-viewing (on own force but remote-viewing foreign surface)
    if player.controller_type == defines.controllers.remote then
        local owner = spectator.get_surface_owner(player.surface)
        if owner and owner ~= player.force.name then
            local owner_name = owner:match("^player%-(.+)$") or owner
            return "[on " .. owner_name .. "'s base][friend] "
        end
    end

    return ""
end
```

**Integration in control.lua `on_console_chat`:**

```lua
script.on_event(defines.events.on_console_chat, function(event)
    if not event.player_index then return end
    local author = game.get_player(event.player_index)
    if not author then return end

    local prefix = spectator.get_chat_prefix(author)

    for _, player in pairs(game.players) do
        if player.force ~= author.force then
            player.print(prefix .. author.name .. ": " .. event.message,
                         {color = author.color})
        end
    end
end)
```

### 9. Surface Owner Lookup

**Where:** `spectator.lua` — `spectator.get_surface_owner()`

```lua
function spectator.get_surface_owner(surface)
    if not surface or not surface.valid then return nil end

    -- Check space platforms: iterate all forces' platforms
    for _, force in pairs(game.forces) do
        if force.name:find("^player%-") then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid
                   and plat.surface.index == surface.index then
                    return force.name
                end
            end
        end
    end

    -- Check vanilla solo surfaces: pattern "st-<player_index>-<planet>"
    local owner_idx = tonumber(surface.name:match("^st%-(%d+)%-"))
    if owner_idx then
        local owner = game.get_player(owner_idx)
        if owner then return owner.force.name end
    end

    return nil
end
```

### 10. Spectation Notifications

**Admin flag:** `spectate_notifications_enabled` (default: `true`)

**Where:** `admin_gui.lua` — add to `FLAGS` table:
```lua
{
    key     = "spectate_notifications_enabled",
    label   = "Spectate Notifications",
    tooltip = "When enabled, all players are notified when someone starts or stops spectating.",
}
```

**Announcement in spectator.lua:**
```lua
local function announce_spectation(viewer, target_force, is_entering)
    if not admin_gui.flag("spectate_notifications_enabled") then return end

    local viewer_name = viewer.name
    local target_name = target_force.name:match("^player%-(.+)$") or target_force.name
    local action = is_entering and "is now spectating" or "stopped spectating"

    -- Find target color
    local tr, tg, tb = 1, 1, 1
    local target_players = target_force.connected_players
    if target_players[1] then
        tr = target_players[1].chat_color.r
        tg = target_players[1].chat_color.g
        tb = target_players[1].chat_color.b
    end

    local msg = string.format(
        "[color=%.2f,%.2f,%.2f]%s[/color] %s [color=%.2f,%.2f,%.2f]%s[/color]",
        viewer.chat_color.r, viewer.chat_color.g, viewer.chat_color.b,
        viewer_name, action, tr, tg, tb, target_name
    )

    for _, p in pairs(game.players) do
        if p.connected then p.print(msg) end
    end

    log("[multi-team-support:spectator] announcement: " .. viewer_name .. " " .. action
        .. " " .. target_name)
end
```

**Admin flag change announcements:** All admin flag toggles broadcast.
Modify `control.lua` `on_gui_checked_state_changed`, after the flag change:
```lua
local state_str = admin_gui.flag(changed_flag) and "enabled" or "disabled"
local label = admin_gui.get_flag_label(changed_flag)  -- new helper to expose label
local msg = "[Admin] " .. player.name .. " " .. state_str .. " " .. label
for _, p in pairs(game.players) do
    if p.connected then p.print(msg) end
end
```

Add helper in `admin_gui.lua`:
```lua
function M.get_flag_label(key)
    for _, def in ipairs(FLAGS) do
        if def.key == key then return def.label end
    end
    return key
end
```

### 11. GUI Layout Changes Summary

**platforms_gui.lua — `build_platforms_gui`:**

For each platform/surface row (currently lines 231-246):

**Before:**
```
  Platform Name  [GPS icon]  |  Location
```

**After:**
```
  Platform Name  [Spectate icon]  |  Location
```

- The GPS icon (`utility/gps_map_icon`) becomes `"utility/show_enemy_on_map"`
- Tag changes from `{sb_gps = ...}` to `{sb_spectate = true, ...}`
- Tooltip changes from `"Ping <name>"` to `"Spectate <owner>'s <name>"`
- **Own surfaces:** No spectate button (compare force using
  `spectator.get_effective_force(player)`)
- **Click handler:** `platforms_gui.on_gui_click` handles `sb_spectate` tag

**"Return to my base" button** (lines 254-278):
- Still shown when player is away from home surface
- When clicked during spectation: calls `spectator.exit()` first, then teleports home
- Tooltip updates to "Stop spectating and return to my base" when
  `spectator.is_spectating(player)` is true

### 12. Force Filtering in GUI

The spectator force must be hidden from all player-facing GUIs:

- **`get_platforms_by_owner`:** Skip `force.name == "spectator"` (add to the existing
  skip list alongside "enemy", "neutral", "player")
- **Friend checkboxes:** Don't render friend toggle for the spectator force
- **Research GUI:** Skip spectator force
- **Stats GUI:** Skip spectator force
- **Landing pen player list:** Show spectating players with a "[spectating]" label

### 13. Edge Cases

#### Player disconnects while spectating
- `on_player_left_game` → `spectator.on_player_left(player)`:
  Restore force immediately so buildings/turrets remain correctly assigned.

#### Player reconnects after disconnect during spectation
- `on_player_joined_game` → `spectator.on_player_joined(player)`:
  Verify force is correct. If `storage.spectator_real_force[idx]` is still set but
  player is already on the correct force (restored during disconnect), clean up
  stale storage entries.

#### Multiple spectators watching the same player
- Works naturally. Both are on the spectator force. Both see the same chart data.
  Both get bounced independently when they exit.

#### Spectator clicks spectate button for a different player (while already spectating)
- Calls `spectator.switch_target()`: updates `storage.spectating_target`, opens new
  remote view. No exit/re-enter needed — already on spectator force.

#### 64-force limit
- The spectator force uses 1 additional force slot. Document this in the mod
  description. Effective player limit drops from ~60 to ~59.

#### Player's own force while on spectator force
- While player is on spectator force, their real force still exists. Their
  buildings/turrets still belong to their real force. Because spectator force is
  friends with all player forces, turrets won't fire at the player's character
  (which is still on their home surface).

#### `player.show_on_map = false`
- Hides the player's position marker (icon/arrow) from the map for all other players.
  Used during spectation so the spectator doesn't appear on the target's map.

---

## Spectate Button Icon

Using built-in `"utility/show_enemy_on_map"` (binoculars icon). No custom sprite
or `data.lua` changes needed. Can be swapped for a custom spy-eye sprite later by
adding a PNG to `graphics/` and registering it in `data.lua` (same pattern as the
existing `sb-discord` and `sb-qr-code` sprites).

---

## Chart Data Accumulation Analysis

### How It Works

With `share_chart = true` on all player forces and bidirectional friendship between
every player force and the spectator force:
- Each player force shares its chart data with the spectator force
- The spectator force's chart becomes the **union** of all player forces' charts
- This is ONE extra copy of the combined chart data across all players

### Memory Impact by Scenario

**Platformer mode (space platforms):**
- Each platform: ~20-50 chunks (platforms are small, ~200x200 tiles)
- 20 players: 20 x 50 = ~1,000 chunks
- Chart metadata per chunk: ~0.5-2 KB (explored tiles bitmap, entity visibility cache)
- **Total: ~1-2 MB — negligible**

**Vanilla mode (separate nauvis copies):**
- Each player: ~500-2,000 explored chunks after extended play
- 20 players: 20 x 2,000 = ~40,000 chunks
- **Total: ~40-80 MB of duplicated chart metadata**
- This is the "full map knowledge" equivalent — meaningful but within reason

**Mixed mode:** Somewhere between the two.

### Mitigation Strategy (v1: Hybrid Cleanup)

Accept the accumulation but add periodic cleanup for surfaces with no active spectators.

```lua
function spectator.cleanup_charts()
    local spec = game.forces["spectator"]
    if not spec then return end

    -- Build set of surfaces currently being spectated
    local active_surfaces = {}
    for _, target_fn in pairs(storage.spectating_target) do
        -- We don't track the surface directly, but the target force.
        -- Mark all surfaces owned by active target forces.
        local force = game.forces[target_fn]
        if force then
            for _, plat in pairs(force.platforms) do
                if plat.surface and plat.surface.valid then
                    active_surfaces[plat.surface.index] = true
                end
            end
        end
    end

    -- Clear chart for non-active surfaces
    for _, surface in pairs(game.surfaces) do
        if not active_surfaces[surface.index] then
            -- Only clear for non-spectator-owned surfaces
            local owner = spectator.get_surface_owner(surface)
            if owner and owner ~= "spectator" then
                spec.clear_chart(surface)
            end
        end
    end

    log("[multi-team-support:spectator] cleanup_charts: cleared inactive surface charts")
end
```

**Frequency:** Call from `on_nth_tick` every ~18,000 ticks (5 minutes).
This is a lazy optimization — charts will re-accumulate via `share_chart` when
someone spectates that surface again, but peak memory stays bounded.

**Future escalation path (if needed):**
- Replace `share_chart = true` with manual `force.chart(surface, area)` calls that
  only chart a window around the spectator's view position (per-tick polling)
- This is significantly more code but gives surgical control over chart data

---

## File Change Summary

| File | Changes |
|------|---------|
| `spectator.lua` | **NEW FILE.** All spectator state management, API, event handlers, chart cleanup. |
| `control.lua` | `require("spectator")`. Call `spectator.init()` in on_init/on_configuration_changed. Call `spectator.init_storage()` in on_init/on_load. Call `spectator.setup_force()` in create_player_force. Wire `spectator.on_controller_changed()` into on_player_controller_changed. Wire `spectator.on_player_left/joined()`. Update on_console_chat to use `spectator.get_chat_prefix()`. Add admin flag announcement broadcasts. Add on_nth_tick for chart cleanup. |
| `platforms_gui.lua` | Replace GPS buttons with spectate buttons using `"utility/show_enemy_on_map"` sprite. Add spectate click handler delegating to `spectator.enter/switch_target/enter_friend_view`. Skip `"spectator"` force in `get_platforms_by_owner`. Hide spectate buttons for own surfaces. Wire `spectator.on_friend_changed()` into on_friend_toggle. Modify return-to-base to call `spectator.exit()` first. |
| `admin_gui.lua` | Add `spectate_notifications_enabled` flag. Add `get_flag_label()` helper. |

## Implementation Order

1. `spectator.lua` — create module with `init()`, `init_storage()`, `setup_force()`
2. `control.lua` — wire spectator.init into on_init/on_configuration_changed/on_load
3. `control.lua` — call `spectator.setup_force()` from `create_player_force()`
4. `platforms_gui.lua` — replace GPS buttons with spectate buttons (UI only, no handler)
6. `spectator.lua` — implement `enter()`, `exit()`, `switch_target()`, `enter_friend_view()`
7. `platforms_gui.lua` — add spectate click handler calling spectator API
8. `spectator.lua` — implement `on_controller_changed()`; wire in `control.lua`
9. `spectator.lua` — implement `on_friend_changed()`; wire in `platforms_gui.lua`
10. `spectator.lua` — implement `get_chat_prefix()`; wire in `control.lua` on_console_chat
11. `admin_gui.lua` — add `spectate_notifications_enabled` flag + `get_flag_label()`
12. `spectator.lua` — implement `announce_spectation()`
13. `control.lua` — add admin flag change broadcasts
14. `spectator.lua` — implement `on_player_left()`, `on_player_joined()`, `cleanup_charts()`
15. `control.lua` — wire disconnect/reconnect handlers + on_nth_tick cleanup
16. Force filtering — skip "spectator" in all GUI modules
17. Testing (see matrix below)

## Testing Matrix

| # | Scenario | Expected |
|---|----------|----------|
| 1 | A spectates B (no friendship) | A swaps to spectator force, sees B's surface, permission-locked |
| 2 | A spectates B (B has friended A) | A stays on own force, direct remote view via friendship |
| 3 | A spectates B, then B friends A | A auto-upgrades from spectator to friend-view on own force |
| 4 | A spectates B, presses Esc | A returns to own force, bounced to home surface |
| 5 | A spectates B, clicks spectate C | A stays on spectator force, switches to C's surface |
| 6 | A spectates B, clicks "Return to base" | spectator.exit() called, then teleport home |
| 7 | A spectates B, disconnects | A's force restored immediately on disconnect |
| 8 | A reconnects after disconnect during spectation | Force correct, stale storage cleaned up |
| 9 | A spectates B, chats | Message shows "[on B's base][spectator] " prefix |
| 10 | A friend-views B, chats | Message shows "[on B's base][friend] " prefix |
| 11 | A on own base, chats | No prefix |
| 12 | Admin toggles notifications off | No more spectation announcements |
| 13 | Admin toggles any flag | Announcement broadcast to all: "[Admin] X enabled/disabled Y" |
| 14 | A views own surfaces in GUI | No spectate button shown |
| 15 | Spectator force in any GUI | Hidden from platforms, research, stats GUIs |
| 16 | 2 players spectate same target | Both work independently |
| 17 | B unfriends A while A is friend-viewing B | A bounced back to home surface |
| 18 | A only friended B (not mutual), A spectates B | A needs spectator force (B hasn't friended A) |
| 19 | Chart cleanup runs with no active spectators | Spectator force chart cleared for all player surfaces |
| 20 | Chart cleanup runs with active spectators | Only non-spectated surfaces cleared |
| 21 | New player joins after spectator force exists | New force gets friendship + cease-fire with spectator |
| 22 | A spectates from Landing Pen | Works same as from own base |
