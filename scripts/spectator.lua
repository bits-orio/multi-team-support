-- Multi-Team Support - spectator.lua
-- Author: bits-orio
-- License: MIT
--
-- Spectator system: allows players to view other players' surfaces by
-- temporarily swapping to a dedicated spectator force that is friends
-- with all player forces (share_chart = true). A permission group
-- prevents any interaction beyond viewing and chatting.
--
-- Players whose target has friended them get a direct "friend view"
-- instead (no force swap needed — friendship grants chart access).

local admin_gui     = require("gui.admin")
local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")

local spectator = {}

-- ─── Internal Helpers ──────────────────────────────────────────────────

--- Move a player onto the spectator force and freeze their character.
--- Saves real force, crafting speed modifier, and hides map icon.
local function apply_spectator_state(player)
    if not spectator.is_spectating(player) then
        storage.spectator_real_force[player.index] = player.force.name
    end
    player.force = game.forces["spectator"]
    game.permissions.get_group("spectator").add_player(player)
    if player.character then
        storage.spectator_saved_craft_mod[player.index] =
            player.character_crafting_speed_modifier
        player.character_crafting_speed_modifier = -1
    end
    player.show_on_map = false
end

--- Restore a player from spectator force to their real force.
--- Resumes crafting, re-enables character, restores map icon.
--- Does NOT clear spectator storage — caller must do that.
local function restore_player_state(player)
    local real_fn    = storage.spectator_real_force[player.index]
    local real_force = real_fn and game.forces[real_fn]
    if real_force then
        player.force = real_force
    end
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(player) end
    if player.character then
        local saved = storage.spectator_saved_craft_mod[player.index]
        player.character_crafting_speed_modifier = saved or 0
    end
    storage.spectator_saved_craft_mod[player.index] = nil
    player.show_on_map = true
end

--- Clear all spectator storage entries for a player index.
local function clear_spectator_storage(idx)
    storage.spectator_real_force[idx]      = nil
    storage.spectating_target[idx]         = nil
    storage.spectator_saved_craft_mod[idx] = nil
    storage.spectator_saved_location[idx]  = nil
end

--- Recalculate which surfaces are visible to the spectator force.
--- Only surfaces owned by currently-spectated targets (and landing-pen) are shown.
--- Since set_surface_hidden is per-force (not per-player), all active spectators
--- share visibility — the spectator force sees the union of all targets' surfaces.
local function update_spectator_surfaces()
    local spec = game.forces["spectator"]
    if not spec then return end

    local visible_forces = {}
    for _, target_fn in pairs(storage.spectating_target) do
        visible_forces[target_fn] = true
    end

    for _, surface in pairs(game.surfaces) do
        if surface.name == "landing-pen" then
            helpers.set_surface_hidden(spec, surface, false)
        else
            local owner = surface_utils.get_owner(surface)
            helpers.set_surface_hidden(spec, surface, not (owner and visible_forces[owner]))
        end
    end
end

--- Announce spectation start/stop to all players (if notifications enabled).
--- `target_player` (optional): names the specific player being watched (used
--- by the follow-cam "expand" click). `surface` (optional): prepends the
--- human-readable surface name in parens so viewers know which planet.
local function announce_spectation(viewer, target_force, is_entering, target_player, surface)
    if not admin_gui.flag("spectate_notifications_enabled") then return end

    local target_name  = helpers.display_name(target_force.name)
    local action       = is_entering and "is now spectating" or "stopped spectating"
    local target_color = helpers.force_color(target_force)
    local team_tag     = helpers.colored_name(target_name, target_color)

    local surface_suffix = ""
    if surface and surface.valid then
        surface_suffix = " (" .. helpers.display_surface_name(surface.name) .. ")"
    end

    local target_text
    if target_player and target_player.valid then
        target_text = helpers.colored_name(target_player.name, target_player.chat_color)
            .. " (" .. team_tag .. ")" .. surface_suffix
    else
        target_text = team_tag .. surface_suffix
    end

    local msg = helpers.colored_name(viewer.name, viewer.chat_color)
        .. " " .. action .. " " .. target_text

    helpers.broadcast(msg)
    log("[multi-team-support:spectator] announcement: " .. viewer.name .. " " .. action
        .. " " .. (surface and surface.valid and (surface.name .. " / ") or "")
        .. (target_player and target_player.valid and (target_player.name .. " / ") or "")
        .. target_name)
end

--- Open a remote view on a target surface.
local function open_remote_view(player, surface, position)
    player.set_controller({
        type     = defines.controllers.remote,
        surface  = surface,
        position = position,
    })
end

-- ─── Setup ─────────────────────────────────────────────────────────────

-- Actions the spectator permission group should allow (from Biter Battles).
local SPECTATOR_ALLOWED_ACTIONS = {
    "admin_action",
    "change_active_item_group_for_filters",
    "change_active_quick_bar",
    "change_multiplayer_config",
    "clear_cursor",
    "edit_permission_group",
    "gui_checked_state_changed",
    "gui_click",
    "gui_confirmed",
    "gui_elem_changed",
    "gui_location_changed",
    "gui_selected_tab_changed",
    "gui_selection_state_changed",
    "gui_switch_state_changed",
    "gui_text_changed",
    "gui_value_changed",
    "map_editor_action",
    "open_character_gui",
    "quick_bar_set_selected_page",
    "quick_bar_set_slot",
    "remote_view_surface",
    "set_filter",
    "set_player_color",
    "spawn_item",
    "start_walking",
    "toggle_map_editor",
    "toggle_show_entity_info",
    "write_to_console",
}

--- Create or update the spectator permission group.
local function setup_permission_group()
    local p = game.permissions.get_group("spectator")
    if not p then
        p = game.permissions.create_group("spectator")
    end
    for _, action_id in pairs(defines.input_action) do
        p.set_allows_action(action_id, false)
    end
    for _, name in ipairs(SPECTATOR_ALLOWED_ACTIONS) do
        local action = defines.input_action[name]
        if action then p.set_allows_action(action, true) end
    end
end

--- Create the spectator force, permission group, and ensure all existing
--- player forces have the correct friendship/cease-fire/share_chart.
function spectator.init()
    log("[multi-team-support:spectator] init: starting")

    local spec = game.forces["spectator"]
    if not spec then
        spec = game.create_force("spectator")
        log("[multi-team-support:spectator] init: created spectator force")
    end
    -- Spectator force must NOT share its chart — it accumulates everyone's
    -- chart data and sharing it back would leak all surfaces to all players.
    spec.share_chart = false

    for _, force in pairs(game.forces) do
        if force.name:find("^team%-") then
            spec.set_friend(force, true)
            force.set_friend(spec, true)
            force.share_chart = true
        end
        if force.name ~= "enemy" and force ~= spec then
            spec.set_cease_fire(force, true)
            force.set_cease_fire(spec, true)
        end
    end

    spec.technologies["toolbelt"].researched          = true
    spec.technologies["logistic-robotics"].researched = true

    setup_permission_group()

    -- Hide all surfaces from spectator force by default; they are selectively
    -- shown per-target when a player starts spectating.
    for _, surface in pairs(game.surfaces) do
        if surface.name ~= "landing-pen" then
            helpers.set_surface_hidden(spec, surface, true)
        end
    end

    log("[multi-team-support:spectator] init: complete, permission group configured")
end

--- Set up bidirectional friendship + cease-fire between a new player force
--- and the spectator force. Also hides all existing player surfaces.
function spectator.setup_force(new_force)
    new_force.share_chart = true
    local spec = game.forces["spectator"]
    if spec then
        new_force.set_friend(spec, true)
        spec.set_friend(new_force, true)
        spec.set_cease_fire(new_force, true)
        new_force.set_cease_fire(spec, true)
    end

    for _, surface in pairs(game.surfaces) do
        local owner = surface_utils.get_owner(surface)
        if owner and owner ~= new_force.name then
            helpers.set_surface_hidden(new_force, surface, true)
        end
    end

    log("[multi-team-support:spectator] setup_force: " .. new_force.name)
end

--- Ensure storage tables exist.
function spectator.init_storage()
    storage.spectator_real_force      = storage.spectator_real_force      or {}
    storage.spectating_target         = storage.spectating_target         or {}
    storage.spectator_saved_craft_mod = storage.spectator_saved_craft_mod or {}
    storage.spectator_saved_location  = storage.spectator_saved_location  or {}
    storage.friend_intents            = storage.friend_intents            or {}
end

-- ─── State Queries ─────────────────────────────────────────────────────

function spectator.is_spectating(player)
    return storage.spectator_real_force[player.index] ~= nil
end

function spectator.get_real_force(player)
    return storage.spectator_real_force[player.index]
end

function spectator.get_effective_force(player)
    return storage.spectator_real_force[player.index] or player.force.name
end

function spectator.get_target(player)
    return storage.spectating_target and storage.spectating_target[player.index]
end

function spectator.needs_spectator_mode(viewer_force, target_force)
    -- Viewing your own team's surfaces never requires spectator mode.
    -- A LuaForce isn't its own friend by default, so without this
    -- short-circuit `target_force.get_friend(viewer_force)` returns
    -- false for same-team and the function would falsely demand a
    -- force swap. That trapped clicks on own-team surfaces (which we
    -- now show in the Teams GUI) into the full spectator path,
    -- including spectator-force assignment and crafting pause —
    -- neither of which makes sense when you're already on the
    -- target team.
    if viewer_force == target_force then return false end
    return not target_force.get_friend(viewer_force)
end

--- Resolve where to aim a follow-cam / spectator view for a target player.
--- Returns (force, surface, position) where `force` is the target's REAL
--- team (never "spectator"), and surface/position are what the viewer
--- should actually see:
---
---   • If the target is currently mts-spectating another team
---     (is_spectating() = true), we fall back to their physical
---     surface/position so the viewer sees the target's body — not
---     whatever surface the target is watching (avoids chain-spectating).
---
---   • Otherwise, we use player.surface/position directly. That correctly
---     gives the target's current view: their character when walking,
---     or whatever planet/platform they're remoting into from their own
---     team (the common "managing my space platform" pattern).
---
--- Returns nil values for any field that can't be resolved — callers
--- should guard.
function spectator.resolve_view_for(target)
    if not (target and target.valid) then return nil, nil, nil end
    local force = game.forces[spectator.get_effective_force(target)]
    local surface, position
    if spectator.is_spectating(target) then
        surface  = target.physical_surface
        position = target.physical_position
    else
        surface  = target.surface
        position = target.position
    end
    return force, surface, position
end

-- ─── Core Operations ───────────────────────────────────────────────────

--- Begin spectating a target force's surface.
--- `target_player` is optional; when given, the broadcast names them explicitly
--- (used by the follow-cam expand button to say who the viewer is watching).
function spectator.enter(player, target_force, surface, position, target_player)
    log("[multi-team-support:spectator] enter: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    -- Save pre-spectate location for restoring on exit.
    -- Use physical_position/physical_surface: player.position and player.surface
    -- reflect the remote-view camera when the player is in map view, which
    -- would restore them to the wrong place on exit.
    if not spectator.is_spectating(player) then
        storage.spectator_saved_location[player.index] = {
            surface_name = player.physical_surface.name,
            position     = {x = player.physical_position.x, y = player.physical_position.y},
            -- Capture the pre-spectate controller so we can restore it
            -- on exit. This matters for players who were already in
            -- remote view before clicking spectate (e.g. sitting in a
            -- space platform hub, looking at their own platform).
            -- Without this, exit always reverts to character, which
            -- yanks them out of the hub view they intentionally opened
            -- before starting to spectate.
            controller_type = player.controller_type,
            -- LuaControl.hub is non-nil when the player is currently
            -- sitting in a space platform hub. The proper way to put
            -- them back is LuaPlayer.enter_space_platform(platform)
            -- — set_controller alone preserves the camera but not the
            -- hub-pilot relationship that drives "Drop to a planet"
            -- and the platform schedule UI.
            was_in_hub = player.hub ~= nil,
        }
    end

    helpers.diag("spectator.enter: BEFORE state changes", player)
    storage.spectating_target[player.index] = target_force.name
    apply_spectator_state(player)
    helpers.diag("spectator.enter: AFTER apply_spectator_state", player)
    open_remote_view(player, surface, position)
    helpers.diag("spectator.enter: AFTER open_remote_view", player)
    announce_spectation(player, target_force, true, target_player, surface)
    update_spectator_surfaces()

    log("[multi-team-support:spectator] enter: done, force=" .. player.force.name)
end

--- Stop spectating. Safe to call if not spectating (no-ops).
--- Always teleports the player home to prevent stranding on foreign surfaces
--- (especially in God mode where there's no character anchor).
function spectator.exit(player)
    if not spectator.is_spectating(player) then return end
    log("[multi-team-support:spectator] exit: " .. player.name)
    helpers.diag("spectator.exit: BEFORE restore_player_state", player)

    local target_fn = storage.spectating_target[player.index]
    -- Grab the spectated surface before restore_player_state repoints the
    -- player back to their real surface — we want the one they were viewing.
    local spectated_surface = player.surface
    restore_player_state(player)
    helpers.diag("spectator.exit: AFTER restore_player_state", player)

    -- Restore to saved location, or fall back to home surface origin.
    local saved = storage.spectator_saved_location[player.index]
    local target_surface, target_pos
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
    end
    if not target_surface then
        target_surface = surface_utils.get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
    end
    if target_surface then
        -- Collision avoidance only for the fallback origin: bots could have built
        -- there while the player was spectating. Skipped when restoring to the
        -- saved pre-spectate position because the character is still standing
        -- there — find_non_colliding_position would see the character itself as
        -- a blocker and return an offset position, shifting the player by ~1 tile.
        if not saved and player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        helpers.diag("spectator.exit: TELEPORT → " .. target_surface.name
            .. " at " .. string.format("(%.1f,%.1f)", target_pos.x, target_pos.y),
            player)
        player.teleport(target_pos, target_surface)

        -- Restore the player to remote view in two cases:
        --
        --   1. Pre-spectate they were already in remote view (e.g.
        --      they were sitting in a hub on a platform, or remote-
        --      viewing a planet). Without this, spectator.exit would
        --      drop them back to character mode and yank them out of
        --      whatever view they had open before clicking spectate.
        --
        --   2. They're on a space platform, regardless of how they
        --      entered spectator. The natural state on a platform is
        --      sitting in the hub looking at the platform from above
        --      (remote view), because there's almost nothing to do as
        --      a character on the platform tiles directly. Even if
        --      they clicked spectate while standing as a character,
        --      they expect to land in hub-view after exiting. Detect
        --      via LuaSurface.platform — non-nil if and only if the
        --      surface IS a space platform.
        --
        -- For character-mode-on-a-planet (the common case), neither
        -- branch fires; Factorio's default character attachment
        -- after teleport is correct.
        local restore_remote = false
        if saved and saved.controller_type == defines.controllers.remote then
            restore_remote = true
        end
        if target_surface.platform then
            restore_remote = true
        end
        if restore_remote then
            -- Two flavors of remote view exist in Factorio 2.0 and we
            -- have to pick the right one to preserve the player's
            -- pre-spectate UX:
            --
            -- (a) Position-based remote:
            --       set_controller{type=remote, surface=X, position=Y}
            --     A free-floating camera at coordinates Y on surface X.
            --     No hub-specific UI.
            --
            -- (b) Platform-bound remote:
            --       set_controller{type=remote, space_platform=P}
            --     The "sitting in the hub" state. Camera shows the
            --     platform from above AND Factorio shows the hub
            --     actions ("Drop to a planet", platform schedule, etc.)
            --     in the side panel. This is what a player who was
            --     riding the hub before spectating expects on exit.
            --
            -- LuaSurface.platform returns the LuaSpacePlatform when
            -- the surface IS that platform's surface, nil otherwise.
            -- Use (b) when we have a platform, fall through to (a) for
            -- non-platform surfaces (e.g. returning to a planet
            -- variant in remote view).
            -- Restore in priority order:
            --
            -- 1. If the player was sitting in a space platform hub
            --    pre-spectate, use LuaPlayer.enter_space_platform(P).
            --    That's the documented Factorio API for hub-piloting:
            --    it re-establishes the player as the hub's pilot and
            --    binds the remote view to the platform, including the
            --    "Drop to a planet" / platform schedule UI. Setting
            --    set_controller alone (with surface + position) only
            --    moves the camera; it doesn't restore the pilot
            --    relationship.
            --
            -- 2. If the saved surface IS a space platform but the
            --    player wasn't in the hub (e.g. they were standing as
            --    a character on the platform tiles), enter the hub
            --    anyway since hub-view is the natural state on a
            --    platform. This avoids leaving them in a confusing
            --    free-floating remote view over an empty platform.
            --
            -- 3. Otherwise (planet variant, etc.), fall back to the
            --    position-based remote camera.
            local platform = target_surface.platform
            local hub_entered = false
            if platform and platform.valid
               and (saved and saved.was_in_hub or target_surface.platform) then
                -- enter_space_platform returns false if the engine
                -- refuses (e.g. the player isn't a member of the
                -- platform's force). Fall through to the camera
                -- variant in that case.
                hub_entered = player.enter_space_platform(platform)
            end
            if not hub_entered then
                player.set_controller{
                    type     = defines.controllers.remote,
                    surface  = target_surface,
                    position = target_pos,
                }
            end
        end
    end
    storage.spectator_saved_location[player.index] = nil

    if target_fn then
        local target_force = game.forces[target_fn]
        if target_force then
            announce_spectation(player, target_force, false, nil, spectated_surface)
        end
    end

    clear_spectator_storage(player.index)
    update_spectator_surfaces()
    log("[multi-team-support:spectator] exit: done, force=" .. player.force.name)
end

--- Switch spectation target without leaving spectator force.
--- `target_player` is optional; see spectator.enter().
function spectator.switch_target(player, target_force, surface, position, target_player)
    log("[multi-team-support:spectator] switch_target: " .. player.name
        .. " → " .. target_force.name .. " on " .. surface.name)

    storage.spectating_target[player.index] = target_force.name
    open_remote_view(player, surface, position)
    announce_spectation(player, target_force, true, target_player, surface)
    update_spectator_surfaces()
end

--- Enter spectate mode when the player is already in remote view
--- (e.g. from a GPS tag click or map click to a foreign surface).
--- Like enter() but skips set_controller since the engine already did it.
function spectator.enter_from_remote(player, target_force, surface, position)
    log("[multi-team-support:spectator] enter_from_remote: " .. player.name
        .. " → " .. target_force.name
        .. " on " .. surface.name
        .. " at " .. serpent.line(position))

    if not spectator.is_spectating(player) then
        storage.spectator_saved_location[player.index] = {
            surface_name = player.physical_surface.name,
            position     = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type = player.controller_type,
            was_in_hub = player.hub ~= nil,
        }
    end

    storage.spectating_target[player.index] = target_force.name
    apply_spectator_state(player)
    announce_spectation(player, target_force, true, nil, surface)
    update_spectator_surfaces()

    log("[multi-team-support:spectator] enter_from_remote: done, force=" .. player.force.name)
end

--- Open a friend-view: direct remote view without spectator force swap.
--- When both target_force and target_player are given (follow-cam expand),
--- broadcasts the spectation announcement. Other callers pass neither and
--- suppress the announcement (chart access is implicit for friends).
function spectator.enter_friend_view(player, surface, position, target_force, target_player)
    log("[multi-team-support:spectator] enter_friend_view: " .. player.name
        .. " on " .. surface.name)
    -- Save pre-view location so "return to base" restores it.
    -- Use physical_position/physical_surface for the same reason as spectator.enter():
    -- player.position is the camera position when already in remote map view.
    if not spectator.is_spectating(player)
       and not storage.spectator_saved_location[player.index] then
        storage.spectator_saved_location[player.index] = {
            surface_name = player.physical_surface.name,
            position     = {x = player.physical_position.x, y = player.physical_position.y},
            controller_type = player.controller_type,
            was_in_hub = player.hub ~= nil,
        }
    end
    open_remote_view(player, surface, position)
    if target_force and target_player then
        announce_spectation(player, target_force, true, target_player, surface)
    end
end

-- ─── Event Handlers ────────────────────────────────────────────────────

--- Detects remote-view exit and calls exit().
--- Also detects GPS/map-click entry into remote view on a foreign surface
--- and retroactively wraps the player in spectate mode.
function spectator.on_controller_changed(player, old_controller_type)
    -- Case 1: Player entered remote view on a foreign surface (GPS click, map click).
    if player.controller_type == defines.controllers.remote
       and old_controller_type ~= defines.controllers.remote
       and not spectator.is_spectating(player) then
        local surface = player.surface
        local owner   = surface_utils.get_owner(surface)
        if owner then
            local viewer_force = game.forces[spectator.get_effective_force(player)]
            local target_force = game.forces[owner]
            if viewer_force and target_force and viewer_force ~= target_force then
                local position = player.position
                if spectator.needs_spectator_mode(viewer_force, target_force) then
                    spectator.enter_from_remote(player, target_force, surface, position)
                else
                    spectator.enter_friend_view(player, surface, position)
                end
            end
        end
        return
    end

    -- Case 2: Player exited remote view.
    if old_controller_type == defines.controllers.remote
       and player.controller_type ~= defines.controllers.remote
       and spectator.is_spectating(player) then
        log("[multi-team-support:spectator] on_controller_changed: " .. player.name
            .. " exited remote view, restoring force")
        spectator.exit(player)
    end
end

--- Detect when the spectated camera moves off the targeted team's
--- surfaces and auto-exit. This handles the case where pressing escape
--- on a space platform spectator session reverts the camera to the
--- player's own physical surface (without firing
--- on_player_controller_changed or on_gui_closed). When that happens,
--- the user is effectively "back home" but Factorio leaves them in
--- remote view + spectator force — and the user can't tell they're
--- still in spectator mode without trying to interact.
---
--- Heuristic: while spectating force F, if the camera surface is no
--- longer owned by F, the user has navigated away from F's territory
--- and we treat that as an implicit exit.
---
--- Edge cases covered:
---   • Multi-surface targets: team F has both `mts-nauvis-F` and
---     `platform-X` (their platform). Both are owned by F. Navigating
---     between them keeps us in spectator. Only when the camera lands
---     on a surface NOT owned by F do we exit.
---   • Initial spectator.enter: the first surface_changed event fires
---     with the camera on the target's surface, which IS owned by F,
---     so we don't immediately exit.
---   • Shared/neutral surfaces (default nauvis, landing pen): owner is
---     nil, treated as "not owned by F", auto-exit.
function spectator.on_player_changed_surface(player)
    if not (player and player.valid) then return end
    if not spectator.is_spectating(player) then return end

    local target_force_name = storage.spectating_target[player.index]
    if not target_force_name then return end

    local owner = surface_utils.get_owner(player.surface)
    if owner == target_force_name then return end

    log("[multi-team-support:spectator] on_player_changed_surface: "
        .. player.name .. " camera left target force territory ("
        .. target_force_name .. " → "
        .. (owner or "<unowned>")
        .. " on " .. player.surface.name .. "), auto-exiting spectator")
    spectator.exit(player)
end

--- Upgrade a spectator to friend-view (restore force, keep remote view).
local function upgrade_to_friend_view(p, idx)
    restore_player_state(p)
    clear_spectator_storage(idx)
    update_spectator_surfaces()
    -- crafting_queue_size errors when the player isn't in a controller
    -- that has one (god/spectator/remote). Guard on character even
    -- though restore_player_state above usually puts them back in one.
    if p.character and p.crafting_queue_size > 0 then
        p.print("[multi-team-support] You are now viewing as a friend. Crafting resumed.")
    else
        p.print("[multi-team-support] You are now viewing as a friend.")
    end
    log("[multi-team-support:spectator] upgraded " .. p.name .. " from spectator to friend-view")
end

--- Downgrade a friend-viewer to spectator (swap force, keep remote view).
local function downgrade_to_spectator(p, player_force)
    log("[multi-team-support:spectator] downgrading " .. p.name
        .. " from friend-view to spectator (unfriended)")

    storage.spectating_target[p.index] = player_force.name
    apply_spectator_state(p)
    update_spectator_surfaces()

    local unfriender = helpers.display_name(player_force.name)
    -- Same crafting_queue_size guard as upgrade_to_friend_view above:
    -- the call errors when the player isn't in a controller that has
    -- a crafting queue, which is exactly where this code path puts
    -- them (apply_spectator_state switches them to remote).
    if p.character and p.crafting_queue_size > 0 then
        p.print("[multi-team-support] " .. unfriender .. " unfriended you. Now spectating (crafting paused).")
    else
        p.print("[multi-team-support] " .. unfriender .. " unfriended you. Now spectating.")
    end
end

--- Handle friendship changes that affect active spectators/friend-viewers.
function spectator.on_friend_changed(player_force, target_force, is_friend)
    log("[multi-team-support:spectator] on_friend_changed: "
        .. player_force.name .. (is_friend and " friended " or " unfriended ")
        .. target_force.name)

    if is_friend then
        -- Upgrade spectators whose real force is target_force watching player_force
        for idx, spectated_fn in pairs(storage.spectating_target) do
            if spectated_fn == player_force.name
               and storage.spectator_real_force[idx] == target_force.name then
                local p = game.get_player(idx)
                if p and p.connected then
                    upgrade_to_friend_view(p, idx)
                end
            end
        end
    else
        -- Downgrade target_force players friend-viewing player_force's surfaces
        for _, p in pairs(target_force.connected_players) do
            if p.controller_type == defines.controllers.remote then
                local owner = surface_utils.get_owner(p.surface)
                if owner == player_force.name then
                    downgrade_to_spectator(p, player_force)
                end
            end
        end
    end
end

--- Called from on_player_left_game.
function spectator.on_player_left(player)
    if not spectator.is_spectating(player) then return end
    log("[multi-team-support:spectator] on_player_left: restoring " .. player.name)
    restore_player_state(player)
    clear_spectator_storage(player.index)
    update_spectator_surfaces()
end

--- Called from on_player_joined_game. Defensive cleanup.
function spectator.on_player_joined(player)
    local real_fn = storage.spectator_real_force[player.index]

    if real_fn then
        -- There is live spectator storage: restore force, permission group, and
        -- crafting modifier regardless of which force the player is currently on.
        -- The old code skipped restore_player_state when the force was already
        -- non-spectator, leaving character_crafting_speed_modifier at -1 and the
        -- player stuck in the spectator permission group.
        local was_on_spectator = (player.force.name == "spectator")
        restore_player_state(player)
        clear_spectator_storage(player.index)
        update_spectator_surfaces()
        if was_on_spectator then
            log("[multi-team-support:spectator] on_player_joined: restored " .. player.name
                .. " from spectator force")
        else
            log("[multi-team-support:spectator] on_player_joined: cleaned stale storage for "
                .. player.name)
        end
        return
    end

    -- No spectator storage, but the player may still be stuck in the spectator
    -- permission group or have a negative crafting modifier from a previous
    -- session where storage was cleared without restoring state.  Fix both
    -- defensively on every join when the player is on their own (non-spectator)
    -- force.
    if player.force.name ~= "spectator" then
        local pg = player.permission_group
        if pg and pg.name == "spectator" then
            local default_group = game.permissions.get_group("Default")
            if default_group then default_group.add_player(player) end
            log("[multi-team-support:spectator] on_player_joined: fixed leftover spectator"
                .. " permission group for " .. player.name)
        end
        if player.character and player.character_crafting_speed_modifier < 0 then
            player.character_crafting_speed_modifier = 0
            log("[multi-team-support:spectator] on_player_joined: reset negative crafting"
                .. " modifier for " .. player.name)
        end
    end
end

-- ─── Chat ──────────────────────────────────────────────────────────────

--- Returns the chat context prefix for a player, or "".
function spectator.get_chat_prefix(player)
    local target_fn = spectator.get_target(player)
    if target_fn then
        return "[on " .. helpers.display_name(target_fn) .. "'s base][spectator] "
    end

    if player.controller_type == defines.controllers.remote then
        local owner = surface_utils.get_owner(player.surface)
        if owner and owner ~= player.force.name then
            return "[on " .. helpers.display_name(owner) .. "'s base][friend] "
        end
    end

    return ""
end

return spectator
