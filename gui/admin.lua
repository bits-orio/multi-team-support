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
local nav     = require("gui.nav")

local admin_gui = {}

local NAV_BTN_NAME = "sb_admin_btn"

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
        label   = "Multi-player teams",
        tooltip = "When enabled, players in the Landing Pen can request to join an existing team.",
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
    buddy_join_enabled              = true,
    friendship_enabled              = true,
    spectate_notifications_enabled  = false,
}

-- Buddy team size limit: how many players can share one force via buddy join.
local BUDDY_TEAM_LIMIT_DEFAULT = 2
local BUDDY_TEAM_LIMIT_MIN     = 2
local BUDDY_TEAM_LIMIT_MAX     = 10

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

--- Return the current buddy team size limit.
function admin_gui.buddy_team_limit()
    local flags = admin_gui.get_flags()
    local val = flags.buddy_team_limit
    if type(val) ~= "number" or val < BUDDY_TEAM_LIMIT_MIN or val > BUDDY_TEAM_LIMIT_MAX then
        flags.buddy_team_limit = BUDDY_TEAM_LIMIT_DEFAULT
        return BUDDY_TEAM_LIMIT_DEFAULT
    end
    return val
end

--- Return the human-readable label for a flag key.
function admin_gui.get_flag_label(key)
    for _, def in ipairs(FLAGS) do
        if def.key == key then return def.label end
    end
    return key
end

--- Return the admin-configured starter items list, or nil (= use compat defaults).
function admin_gui.get_starter_items()
    return storage.starter_items  -- nil until admin configures via Starter Items tab
end

--- Give specific items to all spawned players (not in pen, not spectating).
local function distribute_items_to_spawned(items)
    storage.spawned_players = storage.spawned_players or {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p and p.valid and p.connected and p.character then
            for _, item in pairs(items) do
                pcall(function() p.insert(item) end)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Starter Items helpers
-- ---------------------------------------------------------------------------

--- Collect all items from a player's character inventories.
local function collect_character_items(player)
    local items = {}
    local seen  = {}
    if not player.character then return items end
    for _, inv_type in pairs({
        defines.inventory.character_main,
        defines.inventory.character_guns,
        defines.inventory.character_ammo,
        defines.inventory.character_armor,
    }) do
        local inv = player.get_inventory(inv_type)
        if inv then
            for i = 1, #inv do
                local stack = inv[i]
                if stack and stack.valid_for_read then
                    if seen[stack.name] then
                        seen[stack.name].count = seen[stack.name].count + stack.count
                    else
                        local entry = {name = stack.name, count = stack.count}
                        seen[stack.name] = entry
                        items[#items + 1] = entry
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

--- Auto-populate starter items from the first player's inventory.
--- Called once on the first spawn — captures whatever the game/scenario
--- gave them as the template for all future players.
function admin_gui.auto_populate_starter_items(player)
    if storage.starter_items then return end   -- already configured
    if not player.character then return end
    storage.starter_items = collect_character_items(player)
    if #storage.starter_items > 0 then
        log("[multi-team-support] auto-populated starter items from " .. player.name
            .. " (" .. #storage.starter_items .. " item types)")
    end
end

-- ---------------------------------------------------------------------------
-- GUI
-- ---------------------------------------------------------------------------

--- Returns true when this player should see the admin panel.
local function is_admin(player)
    return player.admin
end

--- Build (or rebuild) the admin panel for one player.
--- No-ops if the player is not an admin.
function admin_gui.build_admin_gui(player)
    if not is_admin(player) then return end

    storage.admin_gui_location = storage.admin_gui_location or {}

    -- Save selected tab before frame is cleared by reuse_or_create_frame
    local prev_tab = 1
    local old_frame = player.gui.screen.sb_admin_frame
    if old_frame and old_frame.sb_admin_tabs and old_frame.sb_admin_tabs.valid then
        prev_tab = old_frame.sb_admin_tabs.selected_tab_index or 1
    end

    local frame = helpers.reuse_or_create_frame(
        player, "sb_admin_frame", storage.admin_gui_location, {x = 270, y = 200})

    local title_bar = helpers.add_title_bar(frame, "Admin")
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_admin_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = "Close panel",
    }

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

    -- Buddy team size limit dropdown (shown when buddy join is enabled)
    if flags.buddy_join_enabled then
        flags_content.add{type = "line"}.style.top_margin = 4
        local limit_row = flags_content.add{type = "flow", direction = "horizontal"}
        limit_row.style.vertical_align     = "center"
        limit_row.style.horizontal_spacing = 8
        local limit_lbl = limit_row.add{
            type    = "label",
            caption = "Max team size",
            tooltip = "Maximum number of players allowed in a team via buddy join. Only enforced at join time.",
        }
        limit_lbl.style.minimal_width = 160
        local items = {}
        for i = BUDDY_TEAM_LIMIT_MIN, BUDDY_TEAM_LIMIT_MAX do
            items[#items + 1] = tostring(i)
        end
        local current_limit = admin_gui.buddy_team_limit()
        limit_row.add{
            type           = "drop-down",
            name           = "sb_buddy_team_limit",
            items          = items,
            selected_index = current_limit - BUDDY_TEAM_LIMIT_MIN + 1,
            tooltip        = "Maximum number of players allowed in a team via buddy join.",
        }
    end

    -- Tab: Starter Items
    local starter_tab     = tabs.add{type = "tab",  caption = "Starter Items"}
    local starter_content = tabs.add{type = "flow", direction = "vertical", name = "sb_admin_starter_content"}
    starter_content.style.left_padding    = 8
    starter_content.style.right_padding   = 8
    starter_content.style.top_padding     = 8
    starter_content.style.bottom_padding  = 8
    starter_content.style.vertical_spacing = 6
    tabs.add_tab(starter_tab, starter_content)

    -- "Copy from my inventory" button
    starter_content.add{
        type    = "button",
        name    = "sb_copy_inventory",
        caption = "Copy from my inventory",
        tooltip = "Replace the starter items list with everything in your character inventories.",
    }

    -- Current items list
    local hdr = starter_content.add{type = "label", caption = "Items given when returning to pen:"}
    hdr.style.font = "default-bold"

    local starter_items = storage.starter_items
    if starter_items and #starter_items > 0 then
        local tbl = starter_content.add{
            type = "table", name = "sb_starter_table", column_count = 3,
        }
        tbl.style.horizontal_spacing = 8
        tbl.style.vertical_spacing   = 4
        for i, item in ipairs(starter_items) do
            local name_flow = tbl.add{type = "flow", direction = "horizontal"}
            name_flow.style.vertical_align = "center"
            name_flow.style.horizontal_spacing = 4
            pcall(function()
                name_flow.add{type = "sprite", sprite = "item/" .. item.name}
            end)
            name_flow.add{type = "label", caption = item.name}
            tbl.add{type = "label", caption = "x" .. item.count}
            tbl.add{
                type    = "sprite-button",
                name    = "sb_starter_remove_" .. i,
                sprite  = "utility/close",
                style   = "mini_button",
                tags    = {sb_starter_index = i},
                tooltip = "Remove " .. item.name,
            }
        end
    else
        local note = starter_content.add{type = "label", caption = "  (using default items)"}
        note.style.font_color = {0.6, 0.6, 0.6}
    end

    starter_content.add{type = "line"}.style.top_margin = 4

    -- Add item row
    local add_flow = starter_content.add{type = "flow", direction = "horizontal"}
    add_flow.style.vertical_align     = "center"
    add_flow.style.horizontal_spacing = 6
    add_flow.style.top_margin         = 4
    add_flow.add{type = "label", caption = "Add:"}
    add_flow.add{
        type      = "choose-elem-button",
        name      = "sb_starter_elem",
        elem_type = "item",
        tooltip   = "Select an item to add",
    }
    local count_field = add_flow.add{
        type           = "textfield",
        name           = "sb_starter_count",
        text           = "1",
        numeric        = true,
        allow_decimal  = false,
        allow_negative = false,
        tooltip        = "Count",
    }
    count_field.style.width = 60
    add_flow.add{
        type    = "button",
        name    = "sb_starter_add",
        caption = "+",
        style   = "tool_button",
        tooltip = "Add this item to the starter list",
    }

    -- Restore selected tab
    tabs.selected_tab_index = prev_tab
end

--- Ensure the admin nav button is in sync with each player's admin status.
--- Also destroys the admin panel for non-admins.
--- Call on connectivity changes (join/leave).
function admin_gui.update_all()
    for _, player in pairs(game.players) do
        if player.connected then
            admin_gui.refresh_nav_button(player)
            if not is_admin(player) and player.gui.screen.sb_admin_frame then
                player.gui.screen.sb_admin_frame.destroy()
            end
        end
    end
end

--- Handle click events. Returns true if consumed.
function admin_gui.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end

    if el.name == "sb_admin_close" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then admin_gui.toggle(player) end
        return true
    end

    -- Starter Items: copy from inventory
    if el.name == "sb_copy_inventory" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local old_items = storage.starter_items or {}
            local old_counts = {}
            for _, item in pairs(old_items) do
                old_counts[item.name] = item.count
            end
            storage.starter_items = collect_character_items(player)
            -- Distribute only the NEW or increased items to spawned players
            local diff = {}
            for _, item in pairs(storage.starter_items) do
                local prev = old_counts[item.name] or 0
                if item.count > prev then
                    diff[#diff + 1] = {name = item.name, count = item.count - prev}
                end
            end
            if #diff > 0 then
                distribute_items_to_spawned(diff)
            end
            admin_gui.build_admin_gui(player)
        end
        return true
    end

    -- Starter Items: add item
    if el.name == "sb_starter_add" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local flow        = el.parent
            local elem_btn    = flow and flow.sb_starter_elem
            local count_field = flow and flow.sb_starter_count
            if elem_btn and elem_btn.elem_value and count_field then
                local item_name = elem_btn.elem_value
                local count     = tonumber(count_field.text) or 1
                if count < 1 then count = 1 end
                storage.starter_items = storage.starter_items or {}
                -- If item already exists, add to its count
                local found = false
                for _, existing in pairs(storage.starter_items) do
                    if existing.name == item_name then
                        existing.count = existing.count + count
                        found = true
                        break
                    end
                end
                if not found then
                    storage.starter_items[#storage.starter_items + 1] = {name = item_name, count = count}
                end
                -- Give the added item to all already-spawned players
                distribute_items_to_spawned({{name = item_name, count = count}})
                admin_gui.build_admin_gui(player)
            end
        end
        return true
    end

    -- Starter Items: remove item
    if el.tags and el.tags.sb_starter_index and el.name:find("^sb_starter_remove_") then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local idx = el.tags.sb_starter_index
            if storage.starter_items and storage.starter_items[idx] then
                table.remove(storage.starter_items, idx)
                if #storage.starter_items == 0 then
                    storage.starter_items = nil  -- revert to defaults
                end
                admin_gui.build_admin_gui(player)
            end
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

--- Handle dropdown selection changes.
--- Returns true if consumed (the event was ours).
function admin_gui.on_gui_selection_state_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if el.name ~= "sb_buddy_team_limit" then return false end

    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end

    local new_limit = el.selected_index + BUDDY_TEAM_LIMIT_MIN - 1
    local flags = admin_gui.get_flags()
    flags.buddy_team_limit = new_limit
    log("[multi-team-support] buddy_team_limit changed by " .. player.name .. ": " .. tostring(new_limit))

    return true
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

--- Ensure the admin nav button exists for admins, remove it for non-admins.
--- Call whenever admin status might have changed (on_player_joined_game after
--- a short delay, on_player_promoted, on_player_demoted).
--- Safe to call repeatedly — add_top_button is idempotent.
function admin_gui.refresh_nav_button(player)
    if not (player and player.valid and player.connected) then return end
    local top = player.gui.top
    if is_admin(player) then
        -- Idempotent: safe to call repeatedly
        if not top[NAV_BTN_NAME] then
            -- Insert right after the last mts nav button so the admin button
            -- stays grouped with our buttons (before other mods like helmod)
            -- even after demote/promote cycles.
            local insert_index = nav.position_after_mts(player)
            local add_args = {
                type    = "sprite-button",
                name    = NAV_BTN_NAME,
                sprite  = "utility/bookmark",
                tooltip = "Open Admin panel",
                style   = "tool_button",
            }
            if insert_index then add_args.index = insert_index end
            local btn = top.add(add_args)
            btn.style.width  = 56
            btn.style.height = 56
        end
    else
        if top[NAV_BTN_NAME] then top[NAV_BTN_NAME].destroy() end
    end
end

--- Register the nav click handler at module load (desync-safe).
nav.on_click(NAV_BTN_NAME, function(event)
    admin_gui.toggle(event.player)
end)

--- Called from control.lua on_player_created. Admin status isn't guaranteed
--- yet, so we defer the nav button registration to on_player_joined_game
--- via the pending_admin_check mechanism.
function admin_gui.on_player_created(_player)
    -- intentionally empty
end

return admin_gui
