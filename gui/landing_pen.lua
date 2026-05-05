-- Multi-Team Support - landing_pen.lua
-- Author: bits-orio
-- License: MIT
--
-- A shared pre-game waiting surface ("Landing Pen") where all new players
-- land before spawning into the actual game. Players can either start their
-- own team or request to join an existing team.

local admin_gui       = require("gui.admin")
local helpers         = require("scripts.helpers")
local terrain         = require("gui.landing_pen_terrain")
local platformer      = require("compat.platformer")
local voidblock       = require("compat.voidblock")
local compat_utils    = require("compat.compat_utils")
local force_utils     = require("scripts.force_utils")
local ultracube_compat = require("compat.ultracube")

local landing_pen = {}

-- Re-export chunk handler (wired in control.lua)
landing_pen.on_chunk_generated = terrain.on_chunk_generated

local SURFACE_NAME = terrain.SURFACE_NAME

-- ─── Buddy Request GUI ─────────────────────────────────────────────────

local function show_buddy_request_gui(target, requester)
    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end
    local frame = target.gui.screen.add{
        type = "frame", name = "sb_buddy_req_frame", direction = "vertical",
    }
    frame.auto_center = true

    local title_bar = helpers.add_title_bar(frame, "Buddy Request")

    local msg = frame.add{type = "label", caption = requester.name .. " wants to join your team."}
    msg.style.top_margin    = 6
    msg.style.bottom_margin = 4
    msg.style.left_margin   = 4

    frame.add{type = "line"}

    local btn_flow = frame.add{type = "flow", direction = "horizontal"}
    btn_flow.style.top_margin    = 4
    btn_flow.style.bottom_margin = 2
    local accept_btn = btn_flow.add{
        type = "button", name = "sb_buddy_accept", caption = "Accept",
        style = "confirm_button", tags = {sb_requester_index = requester.index},
    }
    accept_btn.style.horizontally_stretchable = true
    local reject_btn = btn_flow.add{
        type = "button", name = "sb_buddy_reject", caption = "Reject",
        style = "red_button", tags = {sb_requester_index = requester.index},
    }
    reject_btn.style.horizontally_stretchable = true
end

-- ─── Public API ────────────────────────────────────────────────────────

function landing_pen.is_in_pen(player)
    storage.spawned_players = storage.spawned_players or {}
    return not storage.spawned_players[player.index]
end

function landing_pen.place_player(player)
    local surface = terrain.get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}

    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end

    if player.surface == surface then
        local spec_group = game.permissions.get_group("spectator")
        if spec_group then spec_group.add_player(player) end
        landing_pen.build_pen_gui(player)
        landing_pen.update_pen_gui_all()
    else
        storage.pending_pen_tp = storage.pending_pen_tp or {}
        storage.pending_pen_tp[player.index] = {
            surface  = surface,
            position = terrain.get_spawn_position(storage.pen_slots[player.index]),
        }
    end
end

function landing_pen.process_pending_teleports()
    if not storage.pending_pen_tp then return end
    if not next(storage.pending_pen_tp) then return end
    local done = {}
    for player_index, tp in pairs(storage.pending_pen_tp) do
        local player = game.get_player(player_index)
        if player and player.valid and tp.surface and tp.surface.valid then
            if player.controller_type == defines.controllers.cutscene then
                player.exit_cutscene()
            end
            helpers.diag("landing_pen.process_pending_teleports: TELEPORT → "
                .. tp.surface.name, player)
            local ok = player.teleport(tp.position, tp.surface)
            if ok then
                -- Pen players stay on spectator force until they click "Spawn"
                local spec_group = game.permissions.get_group("spectator")
                if spec_group then spec_group.add_player(player) end
                done[#done + 1] = player_index
            end
        else
            done[#done + 1] = player_index
        end
    end
    for _, idx in ipairs(done) do
        storage.pending_pen_tp[idx] = nil
    end
    if #done > 0 then
        for _, idx in ipairs(done) do
            local player = game.get_player(idx)
            if player and player.connected then
                landing_pen.build_pen_gui(player)
            end
        end
        landing_pen.update_pen_gui_all()
    end
end

-- ���── Pen GUI ───────────────────────────────────────────────────────────

--- Add the "join an existing team" section with one row per team.
--- Shows team name + leader, and a "Request to join" button per team.
--- Request is sent to the team leader (they accept/reject).
local function add_join_team_section(frame, player)
    if not admin_gui.flag("buddy_join_enabled") then return end

    -- Collect all occupied teams with an online leader to route the request to
    local rows = {}
    for i = 1, force_utils.max_teams() do
        local force_name = "team-" .. i
        if (storage.team_pool or {})[i] == "occupied" then
            local force = game.forces[force_name]
            local leader_idx = (storage.team_leader or {})[force_name]
            local leader = leader_idx and game.get_player(leader_idx)
            if force and leader then
                rows[#rows + 1] = {
                    force_name = force_name,
                    force      = force,
                    leader     = leader,
                }
            end
        end
    end

    if #rows == 0 then return end

    -- Prominent "OR join an existing team" divider so the option isn't missed.
    local or_flow = frame.add{type = "flow", direction = "horizontal"}
    or_flow.style.horizontal_align         = "center"
    or_flow.style.horizontally_stretchable = true
    or_flow.style.top_margin               = 10
    or_flow.style.bottom_margin            = 2
    local or_label = or_flow.add{
        type    = "label",
        caption = "─────  OR  join an existing team  ─────",
    }
    or_label.style.font       = "heading-2"
    or_label.style.font_color = {1, 0.85, 0.3}

    local limit = admin_gui.buddy_team_limit()
    local limit_flow = frame.add{type = "flow", direction = "horizontal"}
    limit_flow.style.horizontal_align         = "center"
    limit_flow.style.horizontally_stretchable = true
    limit_flow.style.bottom_margin            = 4
    local limit_note = limit_flow.add{
        type    = "label",
        caption = "(max " .. limit .. " per team)",
    }
    limit_note.style.font       = "default-small"
    limit_note.style.font_color = {0.7, 0.7, 0.7}

    storage.buddy_requests = storage.buddy_requests or {}
    local my_request = storage.buddy_requests[player.index]

    for _, row_info in ipairs(rows) do
        local row = frame.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align           = "center"
        row.style.left_margin              = 4
        row.style.top_margin               = 2
        row.style.horizontally_stretchable = true

        -- Team name (colored) + leader info
        local team_name_lbl = row.add{
            type    = "label",
            caption = helpers.team_tag(row_info.force_name),
        }
        team_name_lbl.style.minimal_width = 140

        local leader_text = "(leader: " .. row_info.leader.name
            .. (row_info.leader.connected and "" or " — offline")
            .. ")"
        local leader_lbl = row.add{type = "label", caption = leader_text}
        leader_lbl.style.font       = "default-small"
        leader_lbl.style.font_color = row_info.leader.connected
            and row_info.leader.chat_color
            or {0.55, 0.55, 0.55}

        -- Spacer
        local spacer = row.add{type = "empty-widget"}
        spacer.style.horizontally_stretchable = true

        -- State / action
        local member_count = #row_info.force.players
        local has_room = member_count < limit

        if my_request == row_info.leader.index then
            -- This is the team we requested to join — show a cancel button
            -- so the requester can withdraw without needing to wait.
            local pending = row.add{type = "label", caption = "Pending..."}
            pending.style.font         = "default-small"
            pending.style.font_color   = {1, 1, 0.4}
            pending.style.right_margin = 4
            row.add{
                type    = "button",
                name    = "sb_buddy_cancel",
                caption = "Cancel request",
                style   = "red_button",
                tooltip = "Withdraw your request to join "
                    .. helpers.display_name(row_info.force_name),
            }
        elseif not has_room then
            local full = row.add{type = "label", caption = "Full (" .. member_count .. "/" .. limit .. ")"}
            full.style.font       = "default-small"
            full.style.font_color = {1, 0.4, 0.4}
        elseif not row_info.leader.connected then
            local off = row.add{type = "label", caption = "Leader offline"}
            off.style.font       = "default-small"
            off.style.font_color = {0.55, 0.55, 0.55}
        elseif my_request then
            -- Another request is pending — disable this team's join button
            -- until the requester cancels or gets a response.
            local btn = row.add{
                type    = "button",
                name    = "sb_buddy_request_disabled",
                caption = "Request to join",
                style   = "confirm_button",
                tooltip = "Cancel your pending request first to join a different team.",
                enabled = false,
            }
        else
            -- confirm_button style gives it the same green emphasis as the
            -- "Start a new team" button, so both actions feel equally primary.
            row.add{
                type    = "button",
                name    = "sb_buddy_request",
                caption = "Request to join",
                style   = "confirm_button",
                tags    = {sb_target_index = row_info.leader.index},
                tooltip = "Ask " .. row_info.leader.name
                    .. " to join " .. helpers.display_name(row_info.force_name),
            }
        end
    end
end

--- Count occupied team slots.
local function occupied_team_count()
    local n = 0
    for i = 1, force_utils.max_teams() do
        if (storage.team_pool or {})[i] == "occupied" then
            n = n + 1
        end
    end
    return n
end

function landing_pen.build_pen_gui(player)
    storage.pen_gui_location = storage.pen_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_pen_frame", storage.pen_gui_location, {x = 5, y = 80})

    helpers.add_title_bar(frame, "Landing Pen")
    frame.style.minimal_width = 360
    frame.style.maximal_width = 480

    -- Primary action at the top. Disabled while the player has a pending
    -- request to join another team, so options are mutually exclusive.
    storage.buddy_requests = storage.buddy_requests or {}
    local has_pending = storage.buddy_requests[player.index] ~= nil
    local btn = frame.add{
        type    = "button",
        name    = "sb_spawn_btn",
        caption = "Start a new team",
        style   = "confirm_button",
        enabled = not has_pending,
        tooltip = has_pending
            and "Cancel your pending join request first to start a new team."
            or "Claim a new team slot and spawn into the game.",
    }
    btn.style.top_margin               = 4
    btn.style.bottom_margin            = 2
    btn.style.horizontally_stretchable = true

    -- Only render the "join existing team" section when multi-player teams
    -- are enabled AND there is at least one occupied team to join.
    -- This keeps the pen GUI compact when it's the only option anyway.
    if admin_gui.flag("buddy_join_enabled") and occupied_team_count() > 0 then
        local scroll = frame.add{
            type      = "scroll-pane",
            direction = "vertical",
            horizontal_scroll_policy = "never",
            vertical_scroll_policy   = "auto-and-reserve-space",
        }
        scroll.style.maximal_height           = 500
        scroll.style.horizontally_stretchable = true

        add_join_team_section(scroll, player)
    end
end

function landing_pen.update_pen_gui_all()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end
    for _, player in pairs(game.players) do
        if player.connected and player.surface == surface and landing_pen.is_in_pen(player) then
            landing_pen.build_pen_gui(player)
        end
    end
end

-- ─── Starting Items ───────────────────────────────────────────────────

--- Clear inventory and grant starter items. Uses admin-configured list if set,
--- otherwise falls back to the active compat module's defaults.
--- Called on every spawn from the pen (first spawn and return-to-pen).
function landing_pen.grant_starter_items(player)
    if not player.character then return end
    local items = admin_gui.get_starter_items()
    if not items then
        -- No admin config — use compat defaults
        if platformer.is_active() then
            items = platformer.CHARACTER_STARTING_ITEMS
        elseif voidblock.is_active() then
            items = voidblock.CHARACTER_STARTING_ITEMS
        else
            items = compat_utils.CHARACTER_STARTING_ITEMS
        end
    end
    player.character.clear_items_inside()
    for _, item in pairs(items) do
        pcall(function() player.insert(item) end)
    end
end

-- ─── Return to Pen ────────────────────────────────────────────────────

--- Return a spawned player to the landing pen.
--- Kills the character (dropping inventory as a corpse), then creates a fresh
--- character on the pen surface — matching the exact state of a new player.
--- Call after force_utils.remove_from_team() has moved them to their own force.
function landing_pen.return_to_pen(player)
    -- Cancel any buddy requests targeting this player
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, tgt_idx in pairs(storage.buddy_requests) do
        if tgt_idx == player.index then
            storage.buddy_requests[req_idx] = nil
            local requester = game.get_player(req_idx)
            if requester and requester.connected then
                requester.print(helpers.colored_name(player.name, player.chat_color) .. " is no longer available for buddy join.")
                landing_pen.build_pen_gui(requester)
            end
        end
    end

    -- Dismiss any buddy request GUI the player has open
    if player.gui.screen.sb_buddy_req_frame then
        player.gui.screen.sb_buddy_req_frame.destroy()
    end

    -- Close gameplay GUIs so the player returns to a clean state
    for _, frame_name in pairs({
        "sb_platforms_frame", "sb_research_frame", "sb_stats_frame",
    }) do
        if player.gui.screen[frame_name] then
            player.gui.screen[frame_name].destroy()
        end
    end

    -- Mark as not spawned BEFORE the die/teleport sequence so that any
    -- events triggered mid-flow (on_player_controller_changed, etc.) see
    -- the player as "in the pen" and don't fight our teleport.
    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[player.index] = nil

    -- Kill the character — drops a corpse with full inventory at the
    -- player's current position (on the team's surface).
    if player.character then
        player.character.die()
    end

    -- Prepare pen surface and allocate a slot
    local surface = terrain.get_or_create_surface()
    storage.pen_slots = storage.pen_slots or {}
    if not storage.pen_slots[player.index] then
        local used = {}
        for _, s in pairs(storage.pen_slots) do used[s] = true end
        local slot = 0
        while used[slot] do slot = slot + 1 end
        storage.pen_slots[player.index] = slot
    end
    local pos = terrain.get_spawn_position(storage.pen_slots[player.index])

    -- Set spectator permissions regardless of connection state.
    local spec_group = game.permissions.get_group("spectator")
    if spec_group then spec_group.add_player(player) end

    -- Teleport, character creation, and GUI require an active connection.
    -- If the player is offline (e.g. kicked while disconnected) we skip these;
    -- on_player_joined_game will call place_player when they reconnect.
    if not player.connected then
        landing_pen.update_pen_gui_all()
        return
    end

    -- Exit the death state so we can teleport and create a fresh character
    if not player.character then
        player.set_controller({type = defines.controllers.god})
    end
    helpers.diag("landing_pen.return_to_pen: TELEPORT → " .. surface.name, player)
    player.teleport(pos, surface)
    if not player.character then
        player.create_character()
    end

    -- Give the player the standard starting loadout
    landing_pen.grant_starter_items(player)

    -- Force is already set to spectator by remove_from_team.
    -- Player will claim a new team slot when they click "Spawn" again.

    -- Build pen GUI
    landing_pen.build_pen_gui(player)
    landing_pen.update_pen_gui_all()
end

-- ─── Team Size Check ──────────────────────────────────────────────────

--- Count how many players belong to a force.
local function count_force_members(force)
    local n = 0
    for _ in pairs(force.players) do n = n + 1 end
    return n
end

--- Returns true if the target's team has room for another buddy.
function landing_pen.team_has_room(target)
    local limit = admin_gui.buddy_team_limit()
    return count_force_members(target.force) < limit
end

-- ─── Spawn & Buddy ────────────────────────────────────────────────────

function landing_pen.finish_spawn(player)
    storage.spawned_players = storage.spawned_players or {}
    storage.spawned_players[player.index] = true
    if storage.pen_slots then storage.pen_slots[player.index] = nil end
    if player.gui.screen.sb_pen_frame then
        player.gui.screen.sb_pen_frame.destroy()
    end
    landing_pen.update_pen_gui_all()
end

function landing_pen.rebuild_buddy_request_guis()
    storage.buddy_requests = storage.buddy_requests or {}
    for req_idx, tgt_idx in pairs(storage.buddy_requests) do
        local target    = game.get_player(tgt_idx)
        local requester = game.get_player(req_idx)
        if target and target.connected and requester and requester.valid then
            if not target.gui.screen.sb_buddy_req_frame then
                show_buddy_request_gui(target, requester)
            end
        end
    end
end

function landing_pen.send_buddy_request(requester, target)
    if not landing_pen.team_has_room(target) then
        requester.print(helpers.team_tag(target.force.name) .. " is full.")
        landing_pen.build_pen_gui(requester)
        return
    end
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester.index] = target.index
    show_buddy_request_gui(target, requester)
    landing_pen.build_pen_gui(requester)

    -- Announce the request: requester gets private confirmation; everyone
    -- else gets a broadcast so the whole server can see a team is growing.
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)

    requester.print("You requested to join " .. team_tag
        .. ". Waiting for " .. leader_tag .. " (leader) to approve.")

    helpers.broadcast("[Team] " .. requester_tag .. " wants to join " .. team_tag .. ".")
end

function landing_pen.accept_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not (requester and requester.valid) then return end

    -- Re-check team size at accept time (limit may have changed since request)
    if not landing_pen.team_has_room(target) then
        local ft = helpers.force_tag(target.force.name)
        target.print("Your team is full — cannot accept " .. helpers.colored_name(requester.name, requester.chat_color) .. "." .. ft)
        if requester.connected then
            requester.print(helpers.colored_name(target.name, target.chat_color) .. "'s team is now full." .. ft)
            landing_pen.build_pen_gui(requester)
        end
        landing_pen.update_pen_gui_all()
        return
    end

    -- Check if this is a rejoin (player previously left this team)
    storage.left_teams = storage.left_teams or {}
    local is_rejoin = storage.left_teams[requester.index]
        and storage.left_teams[requester.index][target.force.name]

    if is_rejoin then
        -- Anti-abuse: clear inventory entirely — they left this team before,
        -- their old items are in a corpse on the base already.
        if requester.character then
            requester.character.clear_items_inside()
        end
        requester.print("Your inventory was cleared because you previously left this team." .. helpers.force_tag(target.force.name))
    else
        -- First-time buddy join: grant admin-configured starter items
        landing_pen.grant_starter_items(requester)
    end

    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)

    helpers.broadcast("[Team] " .. leader_tag .. " accepted " .. requester_tag
        .. " into " .. team_tag .. ".")

    requester.force = target.force
    local default_group = game.permissions.get_group("Default")
    if default_group then default_group.add_player(requester) end
    landing_pen.finish_spawn(requester)
    local spawn_pos = target.surface.find_non_colliding_position(
        "character", target.position, 10, 1
    ) or target.position
    requester.teleport(spawn_pos, target.surface)
    -- Requester is now on their team surface — safe to run Ultracube setup.
    ultracube_compat.after_spawn(requester)

    storage.player_clock_start = storage.player_clock_start or {}
    if not storage.player_clock_start[requester.index] then
        storage.player_clock_start[requester.index] = game.tick
    end

    helpers.broadcast("[Team] " .. requester_tag .. " has joined " .. team_tag .. ".")

    local ft = helpers.force_tag(target.force.name)
    target.print(helpers.colored_name(requester.name, requester.chat_color) .. " has joined your team." .. ft)
    if requester.connected then
        requester.print("You joined " .. helpers.colored_name(target.name, target.chat_color) .. "'s team." .. ft)
    end
end

--- Withdraw a pending buddy request initiated by the requester themselves.
--- Announces to the target team so they know the request was cancelled.
function landing_pen.cancel_buddy_request(requester)
    storage.buddy_requests = storage.buddy_requests or {}
    local target_idx = storage.buddy_requests[requester.index]
    if not target_idx then return end
    storage.buddy_requests[requester.index] = nil

    local target = game.get_player(target_idx)
    if target and target.valid then
        -- Close the accept/reject popup on the leader's screen
        if target.gui.screen.sb_buddy_req_frame then
            target.gui.screen.sb_buddy_req_frame.destroy()
        end

        local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
        local team_tag      = helpers.team_tag_with_leader(target.force.name)
        helpers.broadcast("[Team] " .. requester_tag .. " cancelled their request to join " .. team_tag .. ".")
    end

    if requester.connected then
        requester.print("You cancelled your join request.")
        landing_pen.build_pen_gui(requester)
    end
end

function landing_pen.reject_buddy_request(target, requester_index)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = nil

    if target.gui.screen.sb_buddy_req_frame then
        target.gui.screen.sb_buddy_req_frame.destroy()
    end

    local requester = game.get_player(requester_index)
    if not requester then return end

    local leader_tag    = helpers.colored_name(target.name, target.chat_color)
    local requester_tag = helpers.colored_name(requester.name, requester.chat_color)
    local team_tag      = helpers.team_tag_with_leader(target.force.name)

    helpers.broadcast("[Team] " .. leader_tag .. " declined " .. requester_tag
        .. "'s request to join " .. team_tag .. ".")

    if requester.connected then
        requester.print(leader_tag .. " declined your buddy request.")
        landing_pen.build_pen_gui(requester)
    end
end

return landing_pen
