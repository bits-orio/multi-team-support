-- Multi-Team Support - gui/team_settings.lua
-- Author: bits-orio
-- License: MIT
--
-- Per-team settings panel. Everyone on a team can open it; only the team
-- leader can change values. Any change is broadcast to all players so the
-- rest of the server knows when a leader renames their team.
--
-- Settings:
--   • Team name   — textfield (shares storage.team_names with /mts-rename)

local helpers     = require("scripts.helpers")
local nav         = require("gui.nav")
local force_utils = require("scripts.force_utils")
local teams_gui   = require("gui.teams")
local awards_gui  = require("gui.awards")

local team_settings = {}

local NAV_BTN_NAME = "sb_team_settings_btn"
local FRAME_NAME   = "sb_team_settings_frame"

-- Max length for a custom team name (matches /mts-rename).
local MAX_TEAM_NAME_LEN = 32

-- ─── Storage ──────────────────────────────────────────────────────────

function team_settings.init_storage()
    storage.team_settings_location = storage.team_settings_location or {}
end

-- ─── Eligibility ──────────────────────────────────────────────────────

--- Players only have team settings once they're on a team-N force.
--- Pen occupants (spectator force) and other edge cases see no panel.
local function is_on_team(player)
    return player and player.valid
        and player.force and player.force.name:find("^team%-") ~= nil
end

local function is_leader(player)
    return force_utils.is_team_leader(player)
end

-- ─── GUI ──────────────────────────────────────────────────────────────

--- Build (or rebuild) the team settings panel for one player.
function team_settings.build_gui(player)
    if not is_on_team(player) then return end
    storage.team_settings_location = storage.team_settings_location or {}

    local force_name = player.force.name
    local leader     = is_leader(player)
    local team_tag   = helpers.team_tag(force_name)

    local frame = helpers.reuse_or_create_frame(
        player, FRAME_NAME, storage.team_settings_location, {x = 340, y = 240})

    local title_bar = helpers.add_title_bar(frame, "Team Settings")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_team_settings_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close panel",
    }

    frame.style.minimal_width = 340

    local content = frame.add{type = "flow", direction = "vertical"}
    content.style.left_padding    = 8
    content.style.right_padding   = 8
    content.style.top_padding     = 8
    content.style.bottom_padding  = 8
    content.style.vertical_spacing = 8

    -- Current team header (rich-text so the force's chat color shows).
    local header = content.add{
        type    = "label",
        caption = "Team: " .. team_tag,
    }
    header.style.font = "default-bold"

    -- Leader-only notice for read-only viewers.
    if not leader then
        local note = content.add{
            type    = "label",
            caption = "[color=1,0.65,0]Only your team leader can change these settings.[/color]",
        }
        note.style.single_line     = false
        note.style.maximal_width   = 320
    end

    content.add{type = "line"}

    -- ─── Rename row ──────────────────────────────────────────────────
    local name_row = content.add{type = "flow", direction = "horizontal"}
    name_row.style.vertical_align     = "center"
    name_row.style.horizontal_spacing = 6

    local name_lbl = name_row.add{type = "label", caption = "Team name"}
    name_lbl.style.minimal_width = 90

    local name_field = name_row.add{
        type = "textfield",
        name = "sb_team_settings_name",
        text = helpers.display_name(force_name),
    }
    name_field.style.width = 160
    name_field.enabled     = leader

    local save_btn = name_row.add{
        type    = "button",
        name    = "sb_team_settings_rename",
        caption = "Save",
        style   = "tool_button",
        tooltip = "Rename the team (leader only, max " .. MAX_TEAM_NAME_LEN .. " chars)",
    }
    save_btn.enabled = leader
end

--- Close this player's settings frame (if any). Saves frame location.
function team_settings.close(player)
    if not (player and player.valid) then return end
    local frame = player.gui.screen[FRAME_NAME]
    if frame then
        storage.team_settings_location = storage.team_settings_location or {}
        storage.team_settings_location[player.index] = frame.location
        frame.destroy()
    end
end

--- Open (or close) the panel for a player.
function team_settings.toggle(player)
    if not (player and player.valid and player.connected) then return end
    local frame = player.gui.screen[FRAME_NAME]
    if frame then
        team_settings.close(player)
    elseif is_on_team(player) then
        team_settings.build_gui(player)
    end
end

--- Refresh the panel for every player who has it open — useful after a
--- setting change so read-only viewers see the new value immediately.
function team_settings.update_all_for_force(force_name)
    for _, player in pairs(game.players) do
        if player.connected
           and player.force.name == force_name
           and player.gui.screen[FRAME_NAME] then
            team_settings.build_gui(player)
        end
    end
end

-- ─── Nav button ──────────────────────────────────────────────────────

--- Add or remove the nav button based on whether the player is on a team.
--- Called from on_player_joined_game, on_player_changed_force, and after
--- team-slot claim flows.
function team_settings.refresh_nav_button(player)
    if not (player and player.valid and player.connected) then return end
    local top = player.gui.top
    if is_on_team(player) then
        if not top[NAV_BTN_NAME] then
            local insert_index = nav.position_after_mts(player)
            local add_args = {
                type    = "sprite-button",
                name    = NAV_BTN_NAME,
                sprite  = "utility/custom_tag_icon",
                tooltip = "Open Team Settings",
                style   = "tool_button",
            }
            if insert_index then add_args.index = insert_index end
            local btn = top.add(add_args)
            btn.style.width  = 56
            btn.style.height = 56
        end
    else
        if top[NAV_BTN_NAME] then top[NAV_BTN_NAME].destroy() end
        -- Also close any open panel — player is no longer on a team.
        team_settings.close(player)
    end
end

-- ─── Event handlers ──────────────────────────────────────────────────

--- Attempt a rename. Duplicates-check mirrors /mts-rename.
local function try_rename(player, raw_text)
    if not is_leader(player) then
        player.print("Only the team leader can rename the team.")
        return
    end
    local new_name = (raw_text or ""):match("^%s*(.-)%s*$")
    if not new_name or new_name == "" then
        player.print("Team name cannot be empty.")
        return
    end
    if #new_name > MAX_TEAM_NAME_LEN then
        new_name = new_name:sub(1, MAX_TEAM_NAME_LEN)
    end

    local force_name = player.force.name
    local current    = helpers.display_name(force_name)
    if new_name == current then return end   -- no-op

    storage.team_names = storage.team_names or {}
    for fn, name in pairs(storage.team_names) do
        if fn ~= force_name and name == new_name then
            player.print("Another team already uses that name.")
            return
        end
    end

    storage.team_names[force_name] = new_name
    helpers.broadcast("[Team] " .. helpers.colored_name(player.name, player.chat_color)
        .. " renamed their team to " .. helpers.team_tag(force_name))

    team_settings.update_all_for_force(force_name)
    -- Teams panel caches team names, so refresh any open copies.
    teams_gui.update_all()
    awards_gui.update_all()
end

--- Handle GUI clicks. Returns true if consumed.
function team_settings.on_gui_click(event)
    local el = event.element
    if not (el and el.valid) then return false end

    if el.name == "sb_team_settings_close" then
        local player = game.get_player(event.player_index)
        if player then team_settings.close(player) end
        return true
    end

    if el.name == "sb_team_settings_rename" then
        local player = game.get_player(event.player_index)
        if not (player and is_on_team(player)) then return true end
        -- Save button and textfield share the same name_row parent.
        local field = el.parent and el.parent.sb_team_settings_name
        if field and field.valid then
            try_rename(player, field.text)
        end
        return true
    end

    return false
end

--- Handle textfield confirm (Enter key). Same as clicking Save.
function team_settings.on_gui_confirmed(event)
    local el = event.element
    if not (el and el.valid and el.name == "sb_team_settings_name") then return false end
    local player = game.get_player(event.player_index)
    if not (player and is_on_team(player)) then return true end
    try_rename(player, el.text)
    return true
end

-- Register the nav click handler at module load (desync-safe).
nav.on_click(NAV_BTN_NAME, function(event)
    team_settings.toggle(event.player)
end)

--- Called from control.lua on_player_created.
function team_settings.on_player_created(_player)
    -- Intentionally empty — the nav button is managed by refresh_nav_button,
    -- which is called from on_player_joined_game once force is known.
end

return team_settings
