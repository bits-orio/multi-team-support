-- Multi-Team Support - gui/teams.lua
-- Author: bits-orio
-- License: MIT
--
-- Teams GUI: draggable panel showing all teams as cards.
-- Each card shows team name, members, surfaces, and action buttons
-- (watch, leave, rename for leader, friendship for other teams).
--
-- This replaces the earlier "Players & Platforms" GUI with a unified
-- team-centric view.

local nav           = require("gui.nav")
local spectator     = require("scripts.spectator")
local helpers       = require("scripts.helpers")
local surface_utils = require("scripts.surface_utils")
local friendship    = require("gui.friendship")
local admin_gui     = require("gui.admin")
local landing_pen   = require("gui.landing_pen")
local follow_cam    = require("gui.follow_cam")
local research_diff = require("gui.research_diff")

local teams_gui = {}

-- ─── GPS Helpers ───────────────────────────────────────────────────────

--- Build a Factorio rich-text GPS tag for a platform's hub location.
local function get_platform_gps(platform)
    local hub = platform.hub
    if not (hub and hub.valid and platform.surface) then return "" end
    local pos = hub.position
    return string.format("[gps=%d,%d,%s]", pos.x, pos.y, platform.surface.name)
end

-- ─── Data Collection ───────────────────────────────────────────────────

local SKIP_FORCES = {enemy = true, neutral = true, player = true, spectator = true}

--- Collect surfaces + platforms owned by a team force.
--- Returns a table of { name, location, gps, surface_name, position }.
local function collect_team_surfaces(force)
    local list = {}

    -- Space platforms
    for _, platform in pairs(force.platforms) do
        local location = platform.space_location and platform.space_location.name or "in transit"
        local hub = platform.hub
        local hub_pos = (hub and hub.valid) and hub.position or nil
        list[#list + 1] = {
            name         = platform.name,
            location     = location,
            gps          = get_platform_gps(platform),
            surface_name = platform.surface and platform.surface.name or nil,
            position     = hub_pos and {x = hub_pos.x, y = hub_pos.y} or helpers.ORIGIN,
        }
    end

    -- Vanilla/voidblock per-team surfaces: "team-N-planet"
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local owner_fn, planet = surface.name:match("^(team%-%d+)%-(%w+)$")
            if owner_fn == force.name then
                local planet_disp = planet:sub(1, 1):upper() .. planet:sub(2)
                list[#list + 1] = {
                    name         = planet_disp .. " base",
                    location     = planet_disp,
                    gps          = string.format("[gps=0,0,%s]", surface.name),
                    surface_name = surface.name,
                    position     = helpers.ORIGIN,
                }
            end
        end
    end

    -- Space Age per-team planet variants (surface named after the variant
    -- planet e.g. "mts-nauvis-1"). Only include surfaces that actually exist
    -- (planet surfaces are created lazily on first access).
    local per_team = (storage.map_force_to_planets or {})[force.name] or {}
    for base, variant in pairs(per_team) do
        local surface = game.surfaces[variant]
        if surface and surface.valid then
            local planet_disp = base:sub(1, 1):upper() .. base:sub(2)
            list[#list + 1] = {
                name         = planet_disp .. " base",
                location     = planet_disp,
                gps          = string.format("[gps=0,0,%s]", surface.name),
                surface_name = surface.name,
                position     = helpers.ORIGIN,
            }
        end
    end

    return list
end

--- Collect member info for a team: leader, members list.
--- Uses *effective* force so spectating members still appear under their
--- real team (they move to spectator force temporarily, but remain team
--- members for UI purposes).
--- Returns { leader = player_or_nil, members = {player, ...} }
local function collect_team_members(force)
    local leader_idx = (storage.team_leader or {})[force.name]
    local leader = leader_idx and game.get_player(leader_idx) or nil

    local members = {}
    for _, p in pairs(game.players) do
        if p.valid and spectator.get_effective_force(p) == force.name then
            members[#members + 1] = p
        end
    end
    table.sort(members, function(a, b)
        -- Leader first, then alphabetical
        if a == leader then return true end
        if b == leader then return false end
        return a.name < b.name
    end)

    return { leader = leader, members = members }
end

--- A team is "occupied" if its slot is claimed, regardless of whether the
--- current members are temporarily on the spectator force.
--- This prevents team cards from disappearing when a member spectates.
local function is_team_occupied(force_name)
    local slot = tonumber(force_name:match("^team%-(%d+)$"))
    if not slot then return false end
    return (storage.team_pool or {})[slot] == "occupied"
end

--- Public helper used by /mts-players command and other modules.
--- Returns three tables: owners, order, owner_info (legacy API shape).
function teams_gui.get_platforms_by_owner()
    local owners     = {}
    local owner_info = {}
    local order      = {}

    for _, force in pairs(game.forces) do
        if not SKIP_FORCES[force.name] and is_team_occupied(force.name) then
            local owner        = helpers.display_name(force.name)
            local surfaces     = collect_team_surfaces(force)
            local members      = collect_team_members(force)
            local leader       = members.leader
            local online       = leader and leader.connected or false
            owners[owner]      = surfaces
            owner_info[owner]  = {
                gps        = "",
                color      = (leader and leader.chat_color) or helpers.WHITE,
                force_name = force.name,
                online     = online,
            }
            order[#order + 1]  = owner
        end
    end

    return owners, order, owner_info
end

-- ─── Activity Tracking Helpers ────────────────────────────────────────

local function fmt_ago(ticks)
    if ticks < 3600 then return "just now" end
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local d = math.floor(h / 24)
    if d >= 1 then return d .. "d ago" end
    if h >= 1 then return h .. "h " .. m .. "m ago" end
    return m .. "m ago"
end

local function fmt_playtime(ticks)
    local s = math.floor(ticks / 60)
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h >= 1 then return h .. "h " .. m .. "m" end
    return (m > 0 and m .. "m" or "< 1m")
end

--- Tick when this player was last active (game.tick if currently online).
local function player_last_active_tick(player)
    if player.connected then return game.tick end
    return (storage.player_last_seen or {})[player.index]
end

--- Tick when any member of this team was last active.
local function team_last_active_tick(member_list)
    local best = nil
    for _, p in ipairs(member_list) do
        local t = player_last_active_tick(p)
        if t and (not best or t > best) then best = t end
    end
    return best
end

--- Tooltip string listing each member's playtime and last-seen.
local function build_activity_tooltip(member_list)
    if #member_list == 0 then return nil end
    local lines = {}
    for _, p in ipairs(member_list) do
        local c = p.chat_color
        local hex = string.format("#%02x%02x%02x",
            math.floor((c.r or c[1] or 0) * 255),
            math.floor((c.g or c[2] or 0) * 255),
            math.floor((c.b or c[3] or 0) * 255))
        local t = player_last_active_tick(p)
        local seen = p.connected and "online now" or (t and ("last seen: " .. fmt_ago(game.tick - t)) or "never seen")
        lines[#lines + 1] = "[color=" .. hex .. "]" .. p.name .. "[/color]: Played " .. fmt_playtime(p.online_time) .. " (" .. seen .. ")"
    end
    return table.concat(lines, "\n")
end

-- ─── Card Rendering Helpers ────────────────────────────────────────────

--- Add a horizontal colored stripe as a visual separator at the card top.
local function add_color_stripe(parent, color)
    local stripe = parent.add{type = "line"}
    stripe.style.top_margin = 0
    -- Note: Factorio doesn't support custom-colored lines; use a label with
    -- a colored background as a workaround. Fall back to default line.
end

--- Add the card header row: team name, team ID, member count, Watch button.
--- Renaming is handled by /mts-rename and Leaving by /mts-leave to keep the GUI minimal.
local function add_card_header(card, force, members, viewer_player, is_own)
    local hdr = card.add{type = "flow", name = "sb_card_hdr", direction = "horizontal"}
    hdr.style.vertical_align           = "center"
    hdr.style.horizontally_stretchable = true

    local display_name = helpers.display_name(force.name)
    local force_color  = helpers.force_color(force)

    -- Team display name (colored by force color)
    local name_label = hdr.add{type = "label", caption = display_name}
    name_label.style.font       = "default-bold"
    name_label.style.font_color = force_color

    -- Internal team ID (subtle)
    local id_label = hdr.add{type = "label", caption = " [" .. force.name .. "]"}
    id_label.style.font        = "default-small"
    id_label.style.font_color  = {0.5, 0.5, 0.5}
    id_label.style.left_margin = 4

    -- Member count
    local count = #members.members
    local count_label = hdr.add{
        type    = "label",
        caption = " — " .. count .. (count == 1 and " player" or " players"),
    }
    count_label.style.font       = "default-small"
    count_label.style.font_color = {0.7, 0.7, 0.7}

    -- Last-active indicator with per-player playtime tooltip
    local last_tick = team_last_active_tick(members.members)
    if last_tick then
        local ago_ticks = game.tick - last_tick
        local any_online = false
        for _, p in ipairs(members.members) do
            if p.connected then any_online = true; break end
        end
        local ago_text = any_online and "active" or fmt_ago(ago_ticks)
        local color
        if ago_ticks < 216000 then          -- < 1 hour
            color = {0.4, 1.0, 0.4}
        elseif ago_ticks < 5184000 then     -- < 24 hours
            color = {1.0, 0.8, 0.2}
        else
            color = {1.0, 0.4, 0.4}
        end
        local tip = build_activity_tooltip(members.members)
        local ago_label = hdr.add{
            type    = "label",
            name    = "sb_card_activity",
            caption = " · " .. ago_text,
            tooltip = tip,
        }
        ago_label.style.font        = "default-small"
        ago_label.style.font_color  = color
        ago_label.style.left_margin = 4
    end

    -- Research queue: spacer pushes 7 fixed slots to the right
    local spacer = hdr.add{type = "empty-widget"}
    spacer.style.horizontally_stretchable = true
    research_diff.add_queue_icons(hdr, force, 7)
end

--- Add a row for a single team member.
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

    -- Player name, colored
    local name_lbl = row.add{type = "label", caption = member.name}
    name_lbl.style.font_color = member.chat_color

    -- Follow Cam toggle button, after the name (for any player except self).
    -- Uses the radar icon to visually separate from the map Spectate button
    -- on surface rows (Spectate teleports your view; Follow Cam opens a
    -- passive mini-camera).
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

    -- Online/offline indicator
    if member.connected then
        local dot = row.add{type = "label", caption = "  \xE2\x97\x8F"}  -- ●
        dot.style.font_color = {0.4, 0.9, 0.4}
        dot.style.left_margin = 4
    else
        local dot = row.add{type = "label", caption = "  \xE2\x97\x8B"}  -- ○
        dot.style.font_color = {0.55, 0.55, 0.55}
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
                friendship.get_state(viewer_force_name, target_force_name, viewer_force, target_force, helpers.display_name(target_force_name))

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

--- Add the members section of a team card.
local function add_members_section(card, force, members, viewer, viewer_force_name, target_force_name, is_own_team)
    local sub = card.add{type = "label", caption = "Players"}
    sub.style.font        = "default-bold"
    sub.style.top_margin  = 4
    sub.style.font_color  = {0.85, 0.85, 0.85}

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

--- Add the surfaces section of a team card.
local function add_surfaces_section(card, force, surfaces, is_own_team, is_current_target, viewer_player)
    local sub = card.add{type = "label", caption = "Surfaces"}
    sub.style.font        = "default-bold"
    sub.style.top_margin  = 6
    sub.style.font_color  = {0.85, 0.85, 0.85}

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

        -- Spectate button: shown for any surface the viewer isn't
        -- currently on, regardless of which team owns it.
        --
        -- Use cases:
        --   • Foreign team's surface — full MTS spectator mode (force
        --     swap + remote view + crafting paused). Click handler
        --     routes via spectator.enter / switch_target.
        --   • Own team's surface (e.g. viewing your own planet from
        --     your platform) — friend-view-style remote view (no
        --     force change, no crafting pause). Click handler routes
        --     via spectator.enter_friend_view because
        --     needs_spectator_mode returns false for same-team views.
        --
        -- Excluded only when the viewer is physically on this surface,
        -- where "spectate this" is nonsensical (they're already here).
        --
        -- Allowed for pen players too — they're on the spectator
        -- force and can use spectate buttons normally.
        local viewer_phys_surface = viewer_player.physical_surface
            and viewer_player.physical_surface.valid
            and viewer_player.physical_surface.name
        if info.surface_name and info.surface_name ~= viewer_phys_surface then
            row.add{type = "empty-widget"}.style.horizontally_stretchable = true
            -- Tooltip phrasing varies by ownership: foreign teams need
            -- the crafting-pause warning; own-team views don't.
            local tip
            if is_own_team then
                tip = "View this surface in remote view"
            else
                tip = "Spectate this surface (opens remote view; pauses your crafting while active)"
            end
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

--- Build a single team card for the given force.
local function build_team_card(parent, force, viewer_player, viewer_force_name, current_target)
    local members  = collect_team_members(force)
    local surfaces = collect_team_surfaces(force)
    local is_own   = (force.name == viewer_force_name)
    local is_current_target = (force.name == current_target)

    -- Outer frame for the card; highlight own team
    local card_style = is_own and "inside_deep_frame" or "inside_shallow_frame"
    local card = parent.add{
        type      = "frame",
        name      = "sb_card_" .. force.name,
        direction = "vertical",
        style     = card_style,
    }
    card.style.horizontally_stretchable = true
    card.style.padding      = 6
    card.style.margin       = 0
    card.style.bottom_margin = 4

    add_card_header(card, force, members, viewer_player, is_own)
    card.add{type = "line"}.style.top_margin = 2
    add_members_section(card, force, members, viewer_player, viewer_force_name, force.name, is_own)
    add_surfaces_section(card, force, surfaces, is_own, is_current_target, viewer_player)
end

-- ─── GUI Building ──────────────────────────────────────────────────────

--- Find the player's home surface (delegates to surface_utils).
local function get_home_surface(force, player_index)
    return surface_utils.get_home_surface(force, player_index)
end

--- Add the footer with return/stop-spectating button.
local function add_footer(frame, player, viewer_force)
    local in_pen  = landing_pen.is_in_pen(player)
    local is_spec = spectator.is_spectating(player)

    -- Pen players: only show "Stop spectating" when they're spectating.
    if in_pen then
        if not is_spec then return end
    else
        if not viewer_force then return end

        -- Spectator gets the button regardless of where the camera is —
        -- it doubles as "Stop spectating".
        --
        -- Non-spectator players get the button only when they're on a
        -- surface NOT owned by their own team. Specifically:
        --   • On their planet variant (mts-nauvis-N) — hide.
        --   • On a cloned non-Space-Age nauvis (team-N-nauvis) — hide.
        --   • On any of their team's platforms — hide.
        --     (Even though the platform isn't "home", it's still THEIR
        --     surface; offering a magic teleport from platform → planet
        --     would let players bypass cargo-pod travel, which is the
        --     intended Space Age mechanic for descending from orbit.)
        --   • On a foreign team's surface — show. The button bounces
        --     them back to their home surface via the shared force-utils
        --     bounce path.
        --   • On a shared/neutral surface (default nauvis, landing pen) —
        --     show. The button gets them home from places they shouldn't
        --     normally be.
        if not is_spec then
            local owner = surface_utils.get_owner(player.surface)
            if owner == viewer_force.name then return end
        end

        -- Compute the destination for the click handler. We do this
        -- after the visibility check so we don't waste work on a
        -- button that won't render.
        local return_surface = get_home_surface(viewer_force, player.index)
        if not return_surface then return end
    end

    -- player.crafting_queue_size errors with "No crafting queue" when
    -- the player isn't in a controller that has one (god, spectator,
    -- remote view). is_spec means we're already in remote/spectator,
    -- so guard on player.character before reading it.
    local crafting = is_spec and player.character
        and player.crafting_queue_size > 0

    -- Single label "Exit remote view" covers both cases:
    --   • Spectator: actually exits remote view back to character.
    --   • Non-spectator on a foreign or shared surface: teleports home,
    --     conceptually "exiting" the wrong-place state. Same word fits
    --     even though no remote view is involved, because to the player
    --     the button feels like "get me back to where I belong".
    -- Append the crafting-paused note only when relevant.
    local caption = "Exit remote view"
    if is_spec and crafting then
        caption = "Exit remote view (crafting paused)"
    end

    local tooltip
    if in_pen then
        tooltip = "Exit remote view and return to the Landing Pen"
    elseif is_spec then
        tooltip = "Exit remote view and return to your base"
    else
        tooltip = "Teleport back to your base"
    end

    local footer = frame.add{type = "flow", direction = "horizontal"}
    footer.style.top_margin       = 4
    footer.style.horizontal_align = "center"
    footer.style.horizontally_stretchable = true
    footer.add{
        type    = "button",
        name    = "sb_return_to_base",
        caption = caption,
        style   = "button",
        tooltip = tooltip,
    }
end

--- Build (or rebuild) the teams GUI for a single player.
function teams_gui.build_gui(player)
    storage.gui_location = storage.gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_platforms_frame", storage.gui_location, {x = 5, y = 400})

    local title_bar = helpers.add_title_bar(frame, "Teams")
    title_bar.style.horizontal_spacing = 8
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_platforms_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close panel",
    }

    frame.style.maximal_height = 600
    frame.style.minimal_width  = 480
    frame.style.maximal_width  = 560

    local show_offline = helpers.show_offline(player)
    helpers.add_show_offline_checkbox(frame, player)

    local scroll = frame.add{
        type = "scroll-pane",
        name = "sb_platforms_scroll",
        direction = "vertical",
        horizontal_scroll_policy = "never",
        vertical_scroll_policy   = "auto-and-reserve-space",
    }
    scroll.style.maximal_height             = 520
    scroll.style.horizontally_stretchable   = true

    local viewer_force_name = spectator.get_effective_force(player)
    local viewer_force      = game.forces[viewer_force_name]
    local current_target    = spectator.get_target(player)

    -- Sort teams: own team first, then by team number.
    -- Uses team_pool to detect occupancy so spectating members don't hide a team.
    local team_forces = {}
    for _, force in pairs(game.forces) do
        if not SKIP_FORCES[force.name] and is_team_occupied(force.name) then
            team_forces[#team_forces + 1] = force
        end
    end
    table.sort(team_forces, function(a, b)
        if a.name == viewer_force_name then return true end
        if b.name == viewer_force_name then return false end
        return a.name < b.name
    end)

    local visible_count = 0
    for _, force in ipairs(team_forces) do
        local is_own = (force.name == viewer_force_name)
        local online = helpers.team_has_online_member(force.name)
        if online or is_own or show_offline then
            visible_count = visible_count + 1
            build_team_card(scroll, force, player, viewer_force_name, current_target)
        end
    end

    if visible_count == 0 then
        local none = scroll.add{type = "label", caption = "No teams yet."}
        none.style.font_color = {0.7, 0.7, 0.7}
    end

    add_footer(frame, player, viewer_force)
end

--- Rebuild the teams GUI for all connected players.
function teams_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected and player.gui.screen.sb_platforms_frame then
            teams_gui.build_gui(player)
        end
    end
end

--- Update only the last-active labels in-place (no GUI rebuild).
--- Navigate: sb_platforms_frame → sb_platforms_scroll → sb_card_<force>
---            → sb_card_hdr → sb_card_activity
function teams_gui.update_activity_labels_all()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen.sb_platforms_frame
        if not frame then goto next_player end
        local scroll = frame.sb_platforms_scroll
        if not scroll then goto next_player end
        for _, force in pairs(game.forces) do
            if SKIP_FORCES[force.name] then goto next_force end
            local card = scroll["sb_card_" .. force.name]
            if not (card and card.valid) then goto next_force end
            local hdr = card.sb_card_hdr
            if not (hdr and hdr.valid) then goto next_force end
            local lbl = hdr.sb_card_activity
            if not (lbl and lbl.valid) then goto next_force end

            local members = collect_team_members(force)
            local last_tick = team_last_active_tick(members.members)
            if not last_tick then goto next_force end

            local ago_ticks = game.tick - last_tick
            local any_online = false
            for _, p in ipairs(members.members) do
                if p.connected then any_online = true; break end
            end
            local ago_text = any_online and "active" or fmt_ago(ago_ticks)
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
            lbl.tooltip          = build_activity_tooltip(members.members)
            ::next_force::
        end
        ::next_player::
    end
end

--- Update only the research progress bars in-place (no GUI rebuild).
--- Navigate: sb_platforms_frame → sb_platforms_scroll → sb_card_<force>
---            → sb_card_hdr → sb_qslot_<i> → sb_qprog
function teams_gui.update_queue_progress_all()
    for _, player in pairs(game.connected_players) do
        local frame = player.gui.screen.sb_platforms_frame
        if not frame then goto next_player end
        local scroll = frame.sb_platforms_scroll
        if not scroll then goto next_player end

        for _, force in pairs(game.forces) do
            if SKIP_FORCES[force.name] then goto next_force end
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

-- ─── Click Handlers ────────────────────────────────────────────────────

--- Handle return-to-base click: exit spectation, then teleport home.
local function on_return_to_base(player)
    if spectator.is_spectating(player) then
        spectator.exit(player)
        -- Rebuild the panel so the button hides (or relabels) immediately.
        -- Without this, the button stays rendered with its spectator-mode
        -- caption even though spectator.exit already restored the player's
        -- force/controller. A second click would then fall through to the
        -- non-spectator branch below and teleport them home — confusing
        -- because to the user "first click did nothing, second click
        -- magically warped me to Nauvis." The visible disappearance of
        -- the button on the first click is the user's confirmation that
        -- spectator.exit actually worked, especially when their pre-
        -- spectator physical location was already what the camera was
        -- showing (which makes the underlying teleport invisible).
        teams_gui.build_gui(player)
        return
    end
    local saved = storage.spectator_saved_location
        and storage.spectator_saved_location[player.index]
    local target_surface, target_pos
    if saved then
        target_surface = game.surfaces[saved.surface_name]
        target_pos     = saved.position
        storage.spectator_saved_location[player.index] = nil
    end
    if not target_surface then
        target_surface = get_home_surface(player.force, player.index)
        target_pos     = helpers.ORIGIN
    end
    if target_surface then
        if player.character then
            local safe = target_surface.find_non_colliding_position(
                player.character.name, target_pos, 8, 0.5)
            target_pos = safe or target_pos
        end
        helpers.diag("teams_gui.on_return_to_base: TELEPORT → "
            .. target_surface.name, player)
        player.teleport(target_pos, target_surface)
    end
end

--- Handle spectate button click.
local function on_spectate_click(player, tags)
    local target_force = game.forces[tags.sb_target_force]
    local surface      = game.surfaces[tags.sb_surface]
    local position     = tags.sb_position or helpers.ORIGIN
    if not (target_force and surface) then return end

    -- If the target's leader is on this surface, spectate their live position
    local leader_idx = (storage.team_leader or {})[target_force.name]
    local leader = leader_idx and game.get_player(leader_idx)
    if leader and leader.connected and leader.surface == surface then
        position = leader.position
    end

    local viewer_force = game.forces[spectator.get_effective_force(player)]
    if not viewer_force then return end

    if spectator.needs_spectator_mode(viewer_force, target_force) then
        if spectator.is_spectating(player) then
            spectator.switch_target(player, target_force, surface, position)
        else
            spectator.enter(player, target_force, surface, position)
        end
    else
        spectator.enter_friend_view(player, surface, position)
    end
end

--- Handle per-player Follow Cam toggle button.
local function on_follow_cam_toggle(player, tags)
    if not tags.target_idx then return end
    follow_cam.toggle_target(player, tags.target_idx)
    -- Rebuild only this player's panel; only their radar tooltip changed
    teams_gui.build_gui(player)
end

--- Handle GUI click events. Returns true if consumed.
function teams_gui.on_gui_click(event)
    local element = event.element
    if not element or not element.valid then return end

    if element.name == "sb_return_to_base" then
        local player = game.get_player(event.player_index)
        if player then on_return_to_base(player) end
        return true
    end

    if element.name == "sb_platforms_close" then
        local player = game.get_player(event.player_index)
        if player then teams_gui.toggle(player) end
        return true
    end

    if element.tags and element.tags.sb_spectate then
        local player = game.get_player(event.player_index)
        if player then on_spectate_click(player, element.tags) end
        return true
    end

    if element.tags and element.tags.sb_follow_cam_toggle then
        local player = game.get_player(event.player_index)
        if player then on_follow_cam_toggle(player, element.tags) end
        return true
    end

    return false
end

-- ─── Friend Toggle ─────────────────────────────────────────────────────

--- Handle friend checkbox toggle (delegates to gui.friendship).
function teams_gui.on_friend_toggle(event)
    if not admin_gui.flag("friendship_enabled") then return end
    local player = game.get_player(event.player_index)
    if not player or landing_pen.is_in_pen(player) then return end
    if friendship.on_toggle(event) then
        teams_gui.update_all()
    end
end

-- ─── Panel Toggle & Nav ────────────────────────────────────────────────

--- Toggle the teams panel open/closed for a player.
function teams_gui.toggle(player)
    local frame = player.gui.screen.sb_platforms_frame
    if frame then
        storage.gui_location = storage.gui_location or {}
        storage.gui_location[player.index] = frame.location
        frame.destroy()
    else
        teams_gui.build_gui(player)
    end
end

--- Register the nav bar button for this player.
function teams_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_platforms_btn",
        sprite  = "utility/gps_map_icon",
        tooltip = "Teams",
    })
end

-- Register click handler at module load (desync-safe, fires on every script load).
nav.on_click("sb_platforms_btn", function(e)
    teams_gui.toggle(e.player)
end)

return teams_gui
