-- gui/admin.lua
-- Admin panel GUI: feature flags tab, starter items tab, nav button.

local helpers        = require("scripts.helpers")
local nav            = require("gui.nav")
local admin_flags    = require("scripts.admin_flags")
local team_modifiers = require("scripts.team_modifiers")
local pen_info_panel = require("gui.pen_info_panel")

local admin_gui = {}

-- Re-export data API so all callers keep the same require path.
admin_gui.FLAGS                     = admin_flags.FLAGS
admin_gui.get_flags                 = admin_flags.get_flags
admin_gui.flag                      = admin_flags.flag
admin_gui.buddy_team_limit          = admin_flags.buddy_team_limit
admin_gui.get_flag_label            = admin_flags.get_flag_label
admin_gui.ls_get_flag_label         = admin_flags.ls_get_flag_label
admin_gui.get_starter_items         = admin_flags.get_starter_items
admin_gui.auto_populate_starter_items = admin_flags.auto_populate_starter_items
admin_gui.insert_starter_item       = admin_flags.insert_starter_item

local NAV_BTN_NAME         = "sb_admin_btn"
local BUDDY_TEAM_LIMIT_MIN = admin_flags.BUDDY_TEAM_LIMIT_MIN
local BUDDY_TEAM_LIMIT_MAX = admin_flags.BUDDY_TEAM_LIMIT_MAX

local function is_admin(player) return player.admin end

-- ─── GUI Building ──────────────────────────────────────────────────────

function admin_gui.build_admin_gui(player)
    if not is_admin(player) then return end

    storage.admin_gui_location = storage.admin_gui_location or {}

    -- Save selected tab before rebuild so it survives the frame destroy.
    local prev_tab = 1
    local old_frame = player.gui.screen.sb_admin_frame
    if old_frame and old_frame.sb_admin_tabs and old_frame.sb_admin_tabs.valid then
        prev_tab = old_frame.sb_admin_tabs.selected_tab_index or 1
    end

    local frame = helpers.reuse_or_create_frame(
        player, "sb_admin_frame", storage.admin_gui_location, {x = 270, y = 200})

    local title_bar = helpers.add_title_bar(frame, {"mts-gui.admin-title"})
    title_bar.add{
        type    = "sprite-button",
        name    = "sb_admin_close",
        sprite  = "utility/close",
        style   = "close_button",
        tooltip = {"mts-tip.close-panel"},
    }
    frame.style.minimal_width = 280

    local tabs = frame.add{type = "tabbed-pane", name = "sb_admin_tabs"}
    tabs.style.top_margin = 4

    -- ── Feature Flags tab ────────────────────────────────────────────────
    local flags_tab     = tabs.add{type = "tab", caption = {"mts-gui.tab-feature-flags"}}
    local flags_content = tabs.add{type = "flow", direction = "vertical",
        name = "sb_admin_flags_content"}
    flags_content.style.left_padding    = 8
    flags_content.style.right_padding   = 8
    flags_content.style.top_padding     = 8
    flags_content.style.bottom_padding  = 8
    flags_content.style.vertical_spacing = 6
    tabs.add_tab(flags_tab, flags_content)

    local flags = admin_gui.get_flags()
    for _, def in ipairs(admin_flags.FLAGS) do
        local row = flags_content.add{type = "flow", direction = "horizontal"}
        row.style.vertical_align     = "center"
        row.style.horizontal_spacing = 8
        row.add{
            type    = "checkbox",
            state   = flags[def.key] == true,
            tags    = {sb_admin_flag = def.key},
            tooltip = def.ls_tooltip,
        }
        local lbl = row.add{type = "label", caption = def.ls_label, tooltip = def.ls_tooltip}
        lbl.style.minimal_width = 160
    end

    if flags.buddy_join_enabled then
        flags_content.add{type = "line"}.style.top_margin = 4
        local limit_row = flags_content.add{type = "flow", direction = "horizontal"}
        limit_row.style.vertical_align     = "center"
        limit_row.style.horizontal_spacing = 8
        local limit_lbl = limit_row.add{
            type    = "label",
            caption = {"mts-gui.max-team-size"},
            tooltip = {"mts-tip.max-team-size"},
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
            tooltip        = {"mts-tip.max-team-size-dropdown"},
        }
    end

    -- ── Team modifiers (visible only in non-competitive mode) ────────────
    if flags.non_competitive_enabled then
        flags_content.add{type = "line"}.style.top_margin = 4
        local mod_hdr = flags_content.add{
            type    = "label",
            caption = {"mts-gui.team-modifiers-header"},
        }
        mod_hdr.style.font       = "default-bold"
        mod_hdr.style.font_color = team_modifiers.MODE_COLOR
        flags_content.add{type = "label",
            caption = {"mts-gui.team-modifiers-hint"},
        }.style.font_color = {0.6, 0.6, 0.6}

        for _, def in ipairs(team_modifiers.MODIFIERS) do
            local def_lbl = flags_content.add{
                type    = "label",
                caption = def.ls_label,
                tooltip = def.ls_tooltip,
            }
            def_lbl.style.font       = "default-bold"
            def_lbl.style.top_margin = 2

            local any_team = false
            -- force_utils.max_teams() is off-limits here (require cycle via
            -- spectator -> gui.admin), so read the startup setting directly.
            for i = 1, settings.startup["mts_max_teams"].value do
                if (storage.team_pool or {})[i] == "occupied" then
                    any_team = true
                    local force_name = "team-" .. i
                    local row = flags_content.add{type = "flow", direction = "horizontal"}
                    row.style.vertical_align     = "center"
                    row.style.horizontal_spacing = 8
                    row.add{
                        type    = "checkbox",
                        state   = team_modifiers.has(force_name, def.key),
                        tags    = {sb_team_modifier = def.key, sb_target_force = force_name},
                        tooltip = {"mts-tip.modifier-for-team", def.ls_label, def.ls_tooltip},
                    }
                    -- Standardized team display: colored tag + leader in dim
                    -- brackets (rich text renders in label captions), plus
                    -- the permanent non-competitive badge once marked.
                    local badge = team_modifiers.ls_marked_badge(force_name)
                    local name_lbl = row.add{type = "label",
                        caption = badge
                            and {"mts-gui.team-line-marked",
                                helpers.team_tag_with_leader(force_name), badge}
                            or helpers.team_tag_with_leader(force_name)}
                    if badge then
                        name_lbl.tooltip = {"mts-tip.marked-noncompetitive"}
                    end
                end
            end
            if not any_team then
                flags_content.add{type = "label", caption = {"mts-gui.no-teams-yet"}}
                    .style.font_color = {0.6, 0.6, 0.6}
            end
        end
    end

    -- ── Starter Items tab ────────────────────────────────────────────────
    local starter_tab     = tabs.add{type = "tab", caption = {"mts-gui.tab-starter-items"}}
    local starter_content = tabs.add{type = "flow", direction = "vertical",
        name = "sb_admin_starter_content"}
    starter_content.style.left_padding    = 8
    starter_content.style.right_padding   = 8
    starter_content.style.top_padding     = 8
    starter_content.style.bottom_padding  = 8
    starter_content.style.vertical_spacing = 6
    tabs.add_tab(starter_tab, starter_content)

    starter_content.add{
        type    = "button",
        name    = "sb_copy_inventory",
        caption = {"mts-gui.copy-from-inventory"},
        tooltip = {"mts-tip.copy-from-inventory"},
    }

    local hdr = starter_content.add{type = "label", caption = {"mts-gui.starter-items-header"}}
    hdr.style.font = "default-bold"

    local starter_items = storage.starter_items
    if starter_items and #starter_items > 0 then
        local tbl = starter_content.add{type = "table", name = "sb_starter_table", column_count = 3}
        tbl.style.horizontal_spacing = 8
        tbl.style.vertical_spacing   = 4
        for i, item in ipairs(starter_items) do
            local name_flow = tbl.add{type = "flow", direction = "horizontal"}
            name_flow.style.vertical_align    = "center"
            name_flow.style.horizontal_spacing = 4
            pcall(function() name_flow.add{type = "sprite", sprite = "item/" .. item.name} end)
            -- Stored names can outlive their prototypes (a mod removed between
            -- sessions), so fall back to the raw internal name.
            local proto      = prototypes.item[item.name]
            local item_label = proto and proto.localised_name or item.name
            local name_lbl = name_flow.add{type = "label", caption = item_label}
            if item.grid then
                local parts = {}
                for _, eq in ipairs(item.grid) do
                    local eq_proto = prototypes.equipment[eq.name]
                    parts[#parts + 1] = eq_proto and eq_proto.localised_name or eq.name
                end
                name_lbl.caption = {"", item_label, " [+grid]"}
                name_lbl.tooltip = {"mts-tip.equipment-list",
                    helpers.ls_join(parts, ", ")}
            end
            tbl.add{type = "label", caption = {"mts-gui.starter-item-count", item.count}}
            tbl.add{
                type    = "sprite-button",
                name    = "sb_starter_remove_" .. i,
                sprite  = "utility/close",
                style   = "mini_button",
                tags    = {sb_starter_index = i},
                tooltip = {"mts-tip.remove-item", item_label},
            }
        end
    else
        local note = starter_content.add{type = "label", caption = {"mts-gui.using-default-items"}}
        note.style.font_color = {0.6, 0.6, 0.6}
    end

    starter_content.add{type = "line"}.style.top_margin = 4

    local add_flow = starter_content.add{type = "flow", direction = "horizontal"}
    add_flow.style.vertical_align     = "center"
    add_flow.style.horizontal_spacing = 6
    add_flow.style.top_margin         = 4
    add_flow.add{type = "label", caption = {"mts-gui.add-item"}}
    add_flow.add{
        type      = "choose-elem-button",
        name      = "sb_starter_elem",
        elem_type = "item",
        tooltip   = {"mts-tip.select-item-to-add"},
    }
    local count_field = add_flow.add{
        type           = "textfield",
        name           = "sb_starter_count",
        text           = "1",
        numeric        = true,
        allow_decimal  = false,
        allow_negative = false,
        tooltip        = {"mts-tip.starter-count"},
    }
    count_field.style.width = 60
    add_flow.add{
        type    = "button",
        name    = "sb_starter_add",
        caption = "+",
        style   = "tool_button",
        tooltip = {"mts-tip.add-starter-item"},
    }

    -- ── Run Info tab (landing-pen display panel) ─────────────────────────
    local info_tab     = tabs.add{type = "tab", caption = {"mts-gui.tab-run-info"}}
    local info_content = tabs.add{type = "flow", direction = "vertical",
        name = "sb_admin_info_content"}
    info_content.style.left_padding    = 8
    info_content.style.right_padding   = 8
    info_content.style.top_padding     = 8
    info_content.style.bottom_padding  = 8
    info_content.style.vertical_spacing = 6
    tabs.add_tab(info_tab, info_content)

    local info_hdr = info_content.add{type = "label",
        caption = {"mts-gui.run-info-header"}}
    info_hdr.style.font = "default-bold"
    info_content.add{type = "label",
        caption = {"mts-gui.run-info-hint"},
    }.style.font_color = {0.6, 0.6, 0.6}

    local info_box = info_content.add{
        type = "text-box",
        name = "sb_admin_info_text",
        text = pen_info_panel.get_text(),
    }
    info_box.word_wrap      = true
    info_box.style.width    = 320
    info_box.style.height   = 120
    info_content.add{
        type    = "button",
        name    = "sb_admin_info_save",
        caption = {"mts-gui.save-description"},
        style   = "confirm_button",
        tooltip = {"mts-tip.save-description"},
    }

    tabs.selected_tab_index = prev_tab
end

-- ─── Public API ────────────────────────────────────────────────────────

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

function admin_gui.on_gui_click(event)
    local el = event.element
    if not el or not el.valid then return false end

    if el.name == "sb_admin_close" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then admin_gui.toggle(player) end
        return true
    end

    if el.name == "sb_admin_info_save" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local box = el.parent and el.parent.sb_admin_info_text
            if box and box.valid then
                pen_info_panel.set_text(box.text)
                player.print({"mts-chat.pen-info-updated"})
            end
        end
        return true
    end

    if el.name == "sb_copy_inventory" then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local old_items = storage.starter_items or {}
            local old_counts = {}
            for _, item in pairs(old_items) do old_counts[item.name] = item.count end
            storage.starter_items = admin_flags.collect_character_items(player)
            local diff = {}
            for _, item in pairs(storage.starter_items) do
                local prev = old_counts[item.name] or 0
                if item.count > prev then
                    -- Carry the grid (and the quality it was captured at) so
                    -- already-spawned players get the armor loaded too;
                    -- insert_starter_item places it as its own stack, and the
                    -- delivery-override raise strips both fields.
                    diff[#diff + 1] = {
                        name    = item.name,
                        count   = item.count - prev,
                        grid    = item.grid,
                        quality = item.quality,
                    }
                end
            end
            if #diff > 0 then
                admin_flags.distribute_items_to_spawned(diff)
                admin_flags.announce_starter_items_added(diff, player)
            end
            admin_gui.build_admin_gui(player)
        end
        return true
    end

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
                local found = false
                for _, existing in pairs(storage.starter_items) do
                    if existing.name == item_name then
                        existing.count = existing.count + count; found = true; break
                    end
                end
                if not found then
                    storage.starter_items[#storage.starter_items + 1] = {name = item_name, count = count}
                end
                local added = {{name = item_name, count = count}}
                admin_flags.distribute_items_to_spawned(added)
                admin_flags.announce_starter_items_added(added, player)
                admin_gui.build_admin_gui(player)
            end
        end
        return true
    end

    if el.tags and el.tags.sb_starter_index and el.name:find("^sb_starter_remove_") then
        local player = game.get_player(event.player_index)
        if player and is_admin(player) then
            local idx = el.tags.sb_starter_index
            if storage.starter_items and storage.starter_items[idx] then
                table.remove(storage.starter_items, idx)
                if #storage.starter_items == 0 then storage.starter_items = nil end
                admin_gui.build_admin_gui(player)
            end
        end
        return true
    end

    return false
end

function admin_gui.on_gui_confirmed(event)
    local el = event.element
    if not (el and el.valid and el.name == "sb_starter_count") then return false end
    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end
    local flow      = el.parent
    local elem_btn  = flow and flow.sb_starter_elem
    if not (elem_btn and elem_btn.elem_value) then return false end
    local item_name = elem_btn.elem_value
    local count     = tonumber(el.text) or 1
    if count < 1 then count = 1 end
    storage.starter_items = storage.starter_items or {}
    local found = false
    for _, existing in pairs(storage.starter_items) do
        if existing.name == item_name then
            existing.count = existing.count + count; found = true; break
        end
    end
    if not found then
        storage.starter_items[#storage.starter_items + 1] = {name = item_name, count = count}
    end
    local added = {{name = item_name, count = count}}
    admin_flags.distribute_items_to_spawned(added)
    admin_flags.announce_starter_items_added(added, player)
    admin_gui.build_admin_gui(player)
    return true
end

--- Returns the changed flag key, or false if not consumed.
function admin_gui.on_gui_checked_state_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if not (el.tags and el.tags.sb_admin_flag) then return false end
    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end
    local key = el.tags.sb_admin_flag
    local flags = admin_gui.get_flags()
    flags[key] = el.state
    log("[multi-team-support] admin flag changed by " .. player.name
        .. ": " .. key .. " = " .. tostring(el.state))
    return key
end

function admin_gui.on_gui_selection_state_changed(event)
    local el = event.element
    if not el or not el.valid then return false end
    if el.name ~= "sb_buddy_team_limit" then return false end
    local player = game.get_player(event.player_index)
    if not (player and is_admin(player)) then return false end
    local new_limit = el.selected_index + BUDDY_TEAM_LIMIT_MIN - 1
    local flags = admin_gui.get_flags()
    flags.buddy_team_limit = new_limit
    log("[multi-team-support] buddy_team_limit changed by " .. player.name
        .. ": " .. tostring(new_limit))
    return true
end

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

function admin_gui.refresh_nav_button(player)
    if not (player and player.valid and player.connected) then return end
    local top = player.gui.top
    if is_admin(player) then
        if not top[NAV_BTN_NAME] then
            local insert_index = nav.position_after_mts(player)
            local add_args = {
                type    = "sprite-button",
                name    = NAV_BTN_NAME,
                sprite  = "utility/bookmark",
                tooltip = {"mts-tip.open-admin-panel"},
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

nav.on_click(NAV_BTN_NAME, function(event) admin_gui.toggle(event.player) end)

function admin_gui.on_player_created(_player) end

return admin_gui
