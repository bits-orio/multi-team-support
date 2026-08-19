-- gui/stats.lua
-- Production stats GUI facade: public API + top-nav wiring. The
-- implementation lives in gui/stats/ — discovery (prototype scans),
-- columns (categories + item lists + state), counts (statistics reads),
-- panel (frame construction), handlers (event routing).

local nav       = require("gui.nav")
local discovery = require("gui.stats.discovery")
local columns   = require("gui.stats.columns")
local panel     = require("gui.stats.panel")
local handlers  = require("gui.stats.handlers")

local stats_gui = {}

-- Re-export data API so mod-compat callers keep the same require path.
stats_gui.invalidate_categories   = discovery.invalidate_categories
stats_gui.get_category_item_names = columns.get_category_item_names

stats_gui.build_stats_gui     = panel.build_stats_gui
stats_gui.on_gui_click        = handlers.on_gui_click
stats_gui.on_gui_elem_changed = handlers.on_gui_elem_changed

function stats_gui.toggle(player)
    local screen = player.gui.screen
    if screen.sb_stats_frame then
        screen.sb_stats_frame.destroy()
    else
        panel.build_stats_gui(player)
    end
end

function stats_gui.on_player_created(player)
    nav.add_top_button(player, {
        name    = "sb_stats_btn",
        sprite  = "item/production-science-pack",
        -- TODO(locale-stage5): nav button specs (tooltip included) are
        -- persisted in storage.nav_button_order; stage 5 migrates them.
        tooltip = "Production Stats",
    })
end

nav.on_click("sb_stats_btn", function(e) stats_gui.toggle(e.player) end)

return stats_gui
