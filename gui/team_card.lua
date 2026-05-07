-- gui/team_card.lua
-- Card rendering and in-place updaters for the teams GUI.

local helpers       = require("scripts.helpers")
local friendship    = require("gui.friendship")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")
local follow_cam    = require("gui.follow_cam")
local research_diff = require("gui.research_diff")
local teams_data    = require("gui.teams_data")

local M = {}

-- ─── Card Rendering ────────────────────────────────────────────────────

local function add_card_header(card, force, members, viewer_player, is_own)
    local hdr = card.add{type = "flow", name = "sb_card_hdr", direction = "horizontal"}
    hdr.style.vertical_align           = "center"
    hdr.style.horizontally_stretchable = true

    local display_name = helpers.display_name(force.name)
    local force_color  = helpers.force_color(force)

    local count = #members.members
    local name_label = hdr.add{
        type    = "label",
        caption = display_name,
        tooltip = force.name .. " — " .. count .. (count == 1 and " player" or " players"),
    }
    name_label.style.font       = "default-bold"
    name_label.style.font_color = force_color

    local last_tick = teams_data.team_last_active_tick(members.members)
    if last_tick then
        local ago_ticks = game.tick - last_tick
        local any_online = false
        for _, p in ipairs(members.members) do
            if p.connected then any_online = true; break end
        end
        local ago_text = any_online and "active" or teams_data.fmt_ago(ago_ticks)
        local color
        if ago_ticks < 216000 then
            color = {0.4, 1.0, 0.4}
        elseif ago_ticks < 5184000 then
            color = {1.0, 0.8, 0.2}
        else
            color = {1.0, 0.4, 0.4}
        end
        local ago_label = hdr.add{
            type    = "label",
            name    = "sb_card_activity",
            caption = " · " .. ago_text,
            tooltip = teams_data.build_activity_tooltip(members.members),
        }
        ago_label.style.font        = "default-small"
        ago_label.style.font_color  = color
        ago_label.style.left_margin = 4
    end

    local spacer = hdr.add{type = "empty-widget"}
    spacer.style.horizontally_stretchable = true
    research_diff.add_queue_icons(hdr, force, 7)
end

local function add_member_row(parent, member, is_leader_of_team, viewer, viewer_force_name, target_force, target_force_name, is_own_team)
    local row = parent.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"

    -- Fixed-width column for the leader star so names in a card align
    -- regardless of which row is the leader.
    local star_cell = row.add{type = "label", caption = is_leader_of_team and "\xE2\x98\x85" or ""}
    star_cell.style.width        = 14
    star_cell.style.right_margin = 4
    if is_leader_of_team then
        star_cell.style.font_color = {1, 0.8, 0}
    end

    local name_lbl = row.add{type = "label", caption = member.name}
    name_lbl.style.font_color = member.chat_color

    if member.index ~= viewer.index then
        local already = follow_cam.is_following(viewer.index, member.index)
        local cam_btn = row.add{
            type    = "sprite-button",
            sprite  = "item/radar",
            style   = "mini_button",
            tags    = {sb_follow_cam_toggle = true, target_idx = member.index},
            tooltip = already and ("Stop following " .. member.name)
                               or ("Follow " .. member.name
                                   .. " in a mini-camera (does not move your character)"),
        }
        cam_btn.style.left_margin = 4
    end

    if member.connected then
        local dot = row.add{type = "label", caption = "  \xE2\x97\x8F"}
        dot.style.font_color  = {0.4, 0.9, 0.4}
        dot.style.left_margin = 4
    else
        local dot = row.add{type = "label", caption = "  \xE2\x97\x8B"}
        dot.style.font_color  = {0.55, 0.55, 0.55}
        dot.style.left_margin = 4
        local off = row.add{type = "label", caption = " (offline)"}
        off.style.font       = "default-small"
        off.style.font_color = {0.55, 0.55, 0.55}
    end

    -- Friendship control: only on leader row, only for other teams,
    -- only when leader is online, only when viewer is not in pen.
    if is_leader_of_team
       and not is_own_team
       and member.connected
       and admin_gui.flag("friendship_enabled")
       and not landing_pen.is_in_pen(viewer) then
        local viewer_force = game.forces[viewer_force_name]
        if viewer_force and target_force then
            local lbl_text, lbl_color, tip, checked =
                friendship.get_state(viewer_force_name, target_force_name,
                    viewer_force, target_force, helpers.display_name(target_force_name))

            row.add{type = "empty-widget"}.style.horizontally_stretchable = true

            local friend_label = row.add{type = "label", caption = lbl_text}
            friend_label.style.font         = "default-small"
            friend_label.style.font_color   = lbl_color
            friend_label.style.right_margin = 4
            row.add{
                type    = "checkbox",
                state   = checked,
                tags    = {sb_friend_toggle = true, sb_target_force = target_force_name},
                tooltip = tip,
            }
        end
    end
end

local function add_members_section(card, force, members, viewer, viewer_force_name, target_force_name, is_own_team)
    local sub = card.add{type = "label", caption = "Players"}
    sub.style.font       = "default-bold"
    sub.style.top_margin = 4
    sub.style.font_color = {0.85, 0.85, 0.85}

    if #members.members == 0 then
        local none = card.add{type = "label", caption = "  (no players)"}
        none.style.font_color = {0.5, 0.5, 0.5}
        return
    end

    for _, member in ipairs(members.members) do
        local is_leader = (members.leader and member.index == members.leader.index)
        add_member_row(card, member, is_leader, viewer, viewer_force_name, force, target_force_name, is_own_team)
    end
end

local function add_surfaces_section(card, force, surfaces, is_own_team, is_current_target, viewer_player)
    local sub = card.add{type = "label", caption = "Surfaces"}
    sub.style.font       = "default-bold"
    sub.style.top_margin = 6
    sub.style.font_color = {0.85, 0.85, 0.85}

    if #surfaces == 0 then
        local none = card.add{type = "label", caption = "  (no surfaces yet)"}
        none.style.font_color = {0.5, 0.5, 0.5}
        return
    end

    for _, info in ipairs(surfaces) do
        local row = card.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align = "center"

        local name_lbl = row.add{type = "label", caption = "  " .. info.name}
        name_lbl.style.font = "default-small"

        local loc_lbl = row.add{type = "label", caption = "  (" .. info.location .. ")"}
        loc_lbl.style.font       = "default-small"
        loc_lbl.style.font_color = {0.6, 0.6, 0.6}

        -- Spectate button: shown for any surface the viewer isn't currently on.
        -- Own-team views use friend-view (no force change); foreign teams use
        -- full spectator mode (force swap + crafting paused).
        local viewer_phys_surface = viewer_player.physical_surface
            and viewer_player.physical_surface.valid
            and viewer_player.physical_surface.name
        if info.surface_name and info.surface_name ~= viewer_phys_surface then
            row.add{type = "empty-widget"}.style.horizontally_stretchable = true
            local tip = is_own_team
                and "View this surface in remote view"
                or  "Spectate this surface (opens remote view; pauses your crafting while active)"
            row.add{
                type    = "sprite-button",
                sprite  = "utility/map",
                tags    = {
                    sb_spectate     = true,
                    sb_target_force = force.name,
                    sb_surface      = info.surface_name,
                    sb_position     = info.position,
                },
                style   = "mini_button",
                tooltip = tip,
            }
        end
    end
end

function M.build_team_card(parent, force, viewer_player, viewer_force_name, current_target)
    local members  = teams_data.collect_team_members(force)
    local surfaces = teams_data.collect_team_surfaces(force)
    local is_own   = (force.name == viewer_force_name)

    local card_style = is_own and "inside_deep_frame" or "inside_shallow_frame"
    local card = parent.add{
        type      = "frame",
        name      = "sb_card_" .. force.name,
        direction = "vertical",
        style     = card_style,
    }
    card.style.horizontally_stretchable = true
    card.style.padding       = 6
    card.style.margin        = 0
    card.style.bottom_margin = 4

    add_card_header(card, force, members, viewer_player, is_own)
    card.add{type = "line"}.style.top_margin = 2
    add_members_section(card, force, members, viewer_player, viewer_force_name, force.name, is_own)
    add_surfaces_section(card, force, surfaces, is_own, force.name == current_target, viewer_player)
end

-- ─── In-Place Updaters ─────────────────────────────────────────────────

--- Update only the last-active labels without a full GUI rebuild.
function M.update_activity_labels_all()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen.sb_platforms_frame
        if not frame then goto next_player end
        local scroll = frame.sb_platforms_scroll
        if not scroll then goto next_player end

        for _, force in pairs(game.forces) do
            if teams_data.SKIP_FORCES[force.name] then goto next_force end
            local card = scroll["sb_card_" .. force.name]
            if not (card and card.valid) then goto next_force end
            local hdr = card.sb_card_hdr
            if not (hdr and hdr.valid) then goto next_force end
            local lbl = hdr.sb_card_activity
            if not (lbl and lbl.valid) then goto next_force end

            local members = teams_data.collect_team_members(force)
            local last_tick = teams_data.team_last_active_tick(members.members)
            if not last_tick then goto next_force end

            local ago_ticks = game.tick - last_tick
            local any_online = false
            for _, p in ipairs(members.members) do
                if p.connected then any_online = true; break end
            end
            local ago_text = any_online and "active" or teams_data.fmt_ago(ago_ticks)
            local color
            if ago_ticks < 216000 then
                color = {0.4, 1.0, 0.4}
            elseif ago_ticks < 5184000 then
                color = {1.0, 0.8, 0.2}
            else
                color = {1.0, 0.4, 0.4}
            end
            lbl.caption          = " · " .. ago_text
            lbl.style.font_color = color
            lbl.tooltip          = teams_data.build_activity_tooltip(members.members)
            ::next_force::
        end
        ::next_player::
    end
end

--- Update only the research progress bars without a full GUI rebuild.
function M.update_queue_progress_all()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen.sb_platforms_frame
        if not frame then goto next_player end
        local scroll = frame.sb_platforms_scroll
        if not scroll then goto next_player end

        for _, force in pairs(game.forces) do
            if teams_data.SKIP_FORCES[force.name] then goto next_force end
            if not force.current_research then goto next_force end

            local card = scroll["sb_card_" .. force.name]
            if not (card and card.valid) then goto next_force end
            local hdr = card.sb_card_hdr
            if not (hdr and hdr.valid) then goto next_force end

            local queue = force.research_queue or {}
            for i = 1, 7 do
                local slot = hdr["sb_qslot_" .. i]
                if not (slot and slot.valid) then goto next_slot end
                local bar = slot.sb_qprog
                if not (bar and bar.valid) then goto next_slot end
                local btn = slot.sb_qbtn
                local tech = queue[i]
                if not (tech and tech.valid) then goto next_slot end
                local progress = (i == 1) and force.research_progress or tech.saved_progress
                bar.value = progress
                if btn and btn.valid then
                    btn.tooltip = research_diff.queue_tooltip(tech, i, progress)
                end
                ::next_slot::
            end
            ::next_force::
        end
        ::next_player::
    end
end

return M
