-- Multi-Team Support - gui/pen_info_panel.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- An admin-editable info panel in the dead center of the landing pen. The host
-- edits its text from the Admin panel's "Run Info" tab to describe each run
-- (mods, goals, rules) so players landing in know what they're playing.
--
-- Built on the base-game display-panel entity (present with OR without Space
-- Age), pre-configured with the info icon and both visibility toggles, and left
-- NON-OPERABLE so it is display-only: clicking it opens nothing. All editing goes
-- through the Admin GUI via a script write, which sidesteps the pen's spectator
-- permission group (scripts/spectator/core.lua) -- that group blocks the
-- edit_display_panel_* input actions for everyone, admins included, so the native
-- panel GUI can't be used. Writing display_panel_text from a script needs no
-- input action, so no permission-group or force change is required.
--
-- Also charts the small pen area for every force, so the island + panel stay
-- visible on the map even for a player who spawned onto their team surface before
-- the pen finished charting (otherwise the pen reads as a black island when they
-- look back at it).

local helpers = require("scripts.helpers")

local pen_info_panel = {}

local SURFACE_NAME = "landing-pen"
local PANEL_NAME   = "display-panel"
local PANEL_POS    = {x = 0, y = 0}            -- dead center of the pen island
local CHART_AREA   = {{-20, -20}, {20, 20}}    -- covers the whole radius-15 island
local DEFAULT_TEXT = "An admin can describe this run from the Admin panel (Run Info tab)."

-- ─── Text ──────────────────────────────────────────────────────────────

function pen_info_panel.get_text()
    return storage.pen_info_text or DEFAULT_TEXT
end

-- Push the stored text onto the live panel. The panel is in single-message mode
-- (no circuit conditions), so display_panel_text is writable; pcall-guarded so
-- an unexpected mode never crashes the caller.
local function apply_text(panel)
    if not (panel and panel.valid) then return end
    pcall(function() panel.display_panel_text = pen_info_panel.get_text() end)
end

--- Set the run description (from the Admin GUI). Persists it and updates the live
--- panel if the pen already exists; otherwise ensure() applies it on pen build.
function pen_info_panel.set_text(text)
    storage.pen_info_text = (type(text) == "string" and text ~= "") and text or nil
    apply_text(storage.pen_info_panel)
end

-- ─── Panel entity ──────────────────────────────────────────────────────

-- Pre-configure so an admin only ever edits the text: info icon, always-show
-- (alt-mode) + show-in-chart on, indestructible + non-minable, and non-operable
-- so its (permission-blocked) native edit GUI never opens.
local function configure(panel)
    panel.destructible = false
    panel.minable      = false
    panel.operable     = false
    pcall(function()
        panel.display_panel_always_show   = true
        panel.display_panel_show_in_chart = true
        panel.display_panel_icon = {type = "virtual", name = "signal-info"}
    end)
    apply_text(panel)
end

--- Ensure the info panel exists at the pen center and is configured. Idempotent.
--- No-op if the display-panel prototype is unavailable (e.g. a mod removed it).
function pen_info_panel.ensure(surface)
    if not (surface and surface.valid) then return end
    if not prototypes.entity[PANEL_NAME] then return end

    local panel = storage.pen_info_panel
    if not (panel and panel.valid) then
        -- Reuse one already at the spot (e.g. after a reload dropped the ref).
        local found = surface.find_entities_filtered{name = PANEL_NAME, position = PANEL_POS, radius = 1}
        panel = found[1]
        if not (panel and panel.valid) then
            -- Owned by the same force pen players are on (spectator), so its text
            -- is visible to them; fall back to the player force if absent.
            local force = game.forces["spectator"] or game.forces.player
            panel = surface.create_entity{name = PANEL_NAME, position = PANEL_POS, force = force}
        end
        if not (panel and panel.valid) then return end
        storage.pen_info_panel = panel
    end
    configure(panel)
    return panel
end

--- True if this is the pen info panel (so pen chunk-gen doesn't clear it).
function pen_info_panel.is_panel(entity)
    return entity and entity.valid and entity.name == PANEL_NAME
        and storage.pen_info_panel == entity
end

-- ─── Charting (fix: pen reads as a black island when viewed from afar) ──

--- Chart the pen area for one force so the island + panel are always visible.
function pen_info_panel.chart_for(force)
    if not (force and force.valid) then return end
    local surface = game.surfaces[SURFACE_NAME]
    if surface and surface.valid then force.chart(surface, CHART_AREA) end
end

--- Chart the pen for every force (called once when the pen is first built).
function pen_info_panel.chart_all()
    for _, force in pairs(game.forces) do
        pen_info_panel.chart_for(force)
    end
end

return pen_info_panel
