-- Multi-Team Support - nav.lua
-- Author: bits-orio
-- License: MIT
--
-- Thin wrapper around player.gui.top that provides a shared top-bar button
-- strip and a central click-handler registry.  Every GUI module registers its
-- own button and handler here.
-- NOTE: mod_gui was removed in Factorio 2.x; we use player.gui.top directly.

local nav = {}

-- name → function(event) registry, populated at module load time via nav.on_click.
local handlers = {}

-- Ordered list of button names registered via add_top_button.
-- Used by rebuild_buttons to recreate the strip when a player reconnects.
local btn_specs = {}   -- { name, sprite, tooltip } in registration order

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Add a sprite-button to the top GUI bar for this player.
--- Idempotent: safe to call on reconnect; skips creation if button exists.
--- spec = { name = string, sprite = string, tooltip = string }
function nav.add_top_button(player, spec)
    local flow = player.gui.top
    if flow[spec.name] then return end
    local btn = flow.add({
        type    = "sprite-button",
        name    = spec.name,
        sprite  = spec.sprite,
        tooltip = spec.tooltip,
        style   = "tool_button",
    })
    btn.style.width  = 56
    btn.style.height = 56
    -- Record spec for rebuild (avoid duplicates)
    for _, s in ipairs(btn_specs) do
        if s.name == spec.name then return end
    end
    btn_specs[#btn_specs + 1] = spec
end

--- Register a click handler for a named GUI element.
--- Typically called once at module load time, not per-player.
function nav.on_click(name, fn)
    handlers[name] = fn
end

--- Dispatch a gui_click event.  Returns true if the element name had a
--- registered handler and the event was consumed.
--- Call this as the first thing in control.lua's on_gui_click.
function nav.dispatch_click(event)
    local el = event.element
    if not (el and el.valid) then return false end
    local fn = handlers[el.name]
    if not fn then return false end
    local player = game.get_player(event.player_index)
    if not (player and player.valid) then return false end
    event.player = player
    fn(event)
    return true
end

--- Recreate all registered nav buttons for a player.
--- Call from on_player_joined_game to restore buttons after reconnect
--- (player.gui.top is wiped when a player disconnects).
function nav.rebuild_buttons(player)
    for _, spec in ipairs(btn_specs) do
        nav.add_top_button(player, spec)
    end
end

return nav
