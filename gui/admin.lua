-- Multi-Team Support - admin_gui.lua
-- Author: bits-orio
-- License: MIT
--
-- Admin control panel: collapsible window with tabs for runtime configuration.
-- Only shown to players with admin privileges (player.admin).
--
-- Tab: Feature Flags
--   landing_pen_enabled  — whether new players land in the pen or spawn directly

local helpers = require("helpers")

local admin_gui = {}

-- ---------------------------------------------------------------------------
-- Flag definitions
-- ---------------------------------------------------------------------------

-- Ordered list of all feature flags shown in the Feature Flags tab.
local FLAGS = {
    {
        key     = "landing_pen_enabled",
        label   = "Landing Pen",
        tooltip = "When enabled, new players wait in the Landing Pen before spawning into the game.",
    },
    {
        key     = "buddy_join_enabled",
        label   = "Buddy Join",
        tooltip = "When enabled, players in the Landing Pen can request to join another player's force.",
    },
    {
        key     = "friendship_enabled",
        label   = "Allow Friendship",
        tooltip = "When enabled, players can send friend requests. Disabling breaks all existing friendships.",
    },
    {
        key     = "spectate_notifications_enabled",
        label   = "Spectate Notifications",
        tooltip = "When enabled, all players are notified when someone starts or stops spectating.",
    },
}

-- Defaults used on first init.
local FLAG_DEFAULTS = {
    landing_pen_enabled             = true,
    buddy_join_enabled              = false,
    friendship_enabled              = true,
    spectate_notifications_enabled  = false,
}

-- ---------------------------------------------------------------------------
-- Storage helpers
-- ---------------------------------------------------------------------------

--- Return the admin_flags table, initialising defaults for any missing keys.
function admin_gui.get_flags()
    storage.admin_flags = storage.admin_flags or {}
    for k, v in pairs(FLAG_DEFAULTS) do
        if storage.admin_flags[k] == nil then
            storage.admin_flags[k] = v
        end
    end
    return storage.admin_flags
end

--- Read a single flag value.
function admin_gui.flag(key)
    return admin_gui.get_flags()[key]
end

--- Return the human-readable label for a flag key.
function admin_gui.get_flag_label(key)
    for _, def in ipairs(FLAGS) do
        if def.key == key then return def.label end
    end
    return key
end

-- ---------------------------------------------------------------------------
-- GUI
-- ---------------------------------------------------------------------------

--- Returns true when this player should see the admin panel.
local function is_admin(player)
    return player.admin
end

local function is_collapsed(player)
    storage.admin_gui_collapsed = storage.admin_gui_collapsed or {}
    return storage.admin_gui_collapsed[player.index] or false
end

--- Build (or rebuild) the admin panel for one player.
--- No-ops if the player is not an admin.
function admin_gui.build_admin_gui(player)
    if not is_admin(player) then return end

    storage.admin_gui_location = storage.admin_gui_location or {}
    local frame = helpers.reuse_or_create_frame(
        player, "sb_admin_frame", storage.admin_gui_location, {x = 270, y = 200})

    local collapsed = is_collapsed(player)
    local title_bar = helpers.add_title_bar(frame, "Admin")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_admin_toggle",
        caption = collapsed and "+" or "-",
        style   = "close_button",
        tooltip = collapsed and "Expand" or "Collapse",
    }

    if collapsed then return end

    frame.style.minimal_width = 280

    -- Tabbed pane
    local tabs = frame.add{type = "tabbed-pane", name = "sb_admin_tabs"}
    tabs.style.top_margin = 4

    -- Tab: Feature Flags
    local flags_tab     = tabs.add{type = "tab",  caption = "Feature Flags"}
    local flags_content = tabs.add{type = "flow", direction = "vertical", name = "sb_admin_flags_content"}
    flags_content.style.left_padding   = 8
    flags_content.style.right_padding  = 8
    flags_content.style.top_padding    = 8
    flags_content.style.bottom_padding = 8
    flags_content.style.vertical_spacing = 6
    tabs.add_tab(flags_tab, flags_content)
    tabs.selected_tab_index = 1

    local flags = admin_gui.get_flags()
    for _, def in ipairs(FLAGS) do
        local row = flags_content.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align    = "center"
        row.style.horizontal_spacing = 8
        row.add{
            type    = "checkbox",
            state   = flags[def.key] == true,
            tags    = {sb_admin_flag = def.key},
            tooltip = def.tooltip,
        }
        local lbl = row.add{type = "label", caption = def.label, tooltip = def.tooltip}
        lbl.style.minimal_width = 160
    end
end

--- Ensure the admin panel exists for all connected admins; destroy it for non-admins.
--- Only creates the panel if it doesn't exist yet — periodic rebuilds are unnecessary
--- because flag changes already trigger their own rebuild via checkbox handlers.
function admin_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected then
            if is_admin(player) then
                if not player.gui.screen.sb_admin_frame then
                    admin_gui.build_admin_gui(player)
                end
            elseif player.gui.screen.sb_admin_frame then
                player.gui.screen.sb_admin_frame.destroy()
            end
        end
    end
end

--- Handle click events. Returns true if consumed.
function admin_gui.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end

    if el.name == "sb_admin_toggle" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            storage.admin_gui_collapsed = storage.admin_gui_collapsed or {}
            storage.admin_gui_collapsed[player.index] = not is_collapsed(player)
            admin_gui.build_admin_gui(player)
        end
        return true
    end

    return false
end

--- Handle checkbox changes.
--- Returns the changed flag key (truthy = consumed) so the caller can apply
--- side effects, or false if the event was not an admin flag change.
function admin_gui.on_gui_checked_state_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if not (el.tags and el.tags.sb_admin_flag) then return false end

    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end

    local key = el.tags.sb_admin_flag
    local flags = admin_gui.get_flags()
    flags[key] = el.state
    log("[multi-team-support] admin flag changed by " .. player.name .. ": " .. key .. " = " .. tostring(el.state))

    -- Return the key so control.lua can apply immediate side effects.
    return key
end

--- Toggle the admin panel open/closed for a player.
function admin_gui.toggle(player)
    if not is_admin(player) then return end
    local frame = player.gui.screen.sb_admin_frame
    if frame then
        storage.admin_gui_location = storage.admin_gui_location or {}
        storage.admin_gui_location[player.index] = frame.location
        frame.destroy()
    else
        admin_gui.build_admin_gui(player)
    end
end

--- No nav bar button — the admin panel is shown automatically by the
--- 60-tick update_all cycle for the host player (index 1).  Adding a
--- button during on_player_created caused multiplayer desyncs because
--- player.admin is not synchronised at that point.
function admin_gui.on_player_created(_player)
    -- intentionally empty
end

return admin_gui
