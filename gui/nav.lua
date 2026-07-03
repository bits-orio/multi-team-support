-- Multi-Team Support - nav.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Thin wrapper around player.gui.top that provides a shared top-bar button
-- strip and a central click-handler registry.  Every GUI module registers its
-- own button and handler here.
-- NOTE: mod_gui was removed in Factorio 2.x; we use player.gui.top directly.

local nav = {}

-- name → function(event) registry, populated at module load time via nav.on_click.
local handlers = {}

-- The ordered button list lives in storage.nav_button_order (array of
-- { name, sprite, tooltip } in registration order), NOT a module-local: a peer
-- that loads a save whose gui.top already holds the buttons must compute the same
-- insert index as the host. A module-local reset to {} on that peer's load, so
-- position_after_mts returned a divergent index -> gui.top child order (a
-- checksummed part of MP state) differed across peers -> desync.

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Add a sprite-button to the top GUI bar for this player.
--- Idempotent: safe to call on reconnect; skips creation if button exists.
--- spec = { name = string, sprite = string, tooltip = string }
function nav.add_top_button(player, spec)
    -- Record registration order in storage BEFORE the create guard, so a peer
    -- that early-returns (button already exists in a loaded save) still records
    -- the order. Called only from on_player_created / on_player_joined_game
    -- (event context), so the storage write is legal and deterministic.
    storage.nav_button_order = storage.nav_button_order or {}
    local known = false
    for _, s in ipairs(storage.nav_button_order) do
        if s.name == spec.name then known = true; break end
    end
    if not known then
        storage.nav_button_order[#storage.nav_button_order + 1] =
            { name = spec.name, sprite = spec.sprite, tooltip = spec.tooltip }
    end

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

--- Recreate all registered nav buttons for a player from the stored order/specs.
--- The live reconnect path recreates buttons via register_nav_buttons -> each
--- module's add_top_button; this is a convenience to rebuild the whole strip.
function nav.rebuild_buttons(player)
    for _, spec in ipairs(storage.nav_button_order or {}) do
        nav.add_top_button(player, spec)
    end
end

--- Find the 1-based index to insert a new button so it stays grouped with
--- the mts buttons (right after the last registered mts nav button).
--- Other mods' buttons are pushed after this group.
--- Returns nil if none of our buttons are present yet (caller should append).
function nav.position_after_mts(player)
    local top = player.gui.top
    -- Build a set of our button names for fast lookup (from the shared stored
    -- order, so this resolves identically on every peer).
    local mts_names = {}
    for _, spec in ipairs(storage.nav_button_order or {}) do mts_names[spec.name] = true end

    local last_idx = nil
    for i, child in ipairs(top.children) do
        if mts_names[child.name] then
            last_idx = i
        end
    end
    if not last_idx then return nil end
    return last_idx + 1
end

return nav
