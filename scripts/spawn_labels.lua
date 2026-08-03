-- Multi-Team Support - spawn_labels.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Renders a "<team_tag_with_leader>'s\n<location_name>" label (plus a
-- minute-resolution birth-clock line once the team's clock starts) at the
-- spawn area of every team-owned surface. The render-object id is tracked in
-- storage so the text can be live-refreshed when the team is renamed, when
-- the leader changes, or on the periodic clock refresh.
--
-- Storage layout:
--   storage.spawn_labels[force_name][surface_index] = render_object_id

local helpers = require("scripts.helpers")

local spawn_labels = {}

function spawn_labels.init_storage()
    storage.spawn_labels = storage.spawn_labels or {}
    storage.spawn_labels_disabled = storage.spawn_labels_disabled or {}
end

--- Opt a surface out of (or back into) the default spawn label. A consumer mod
--- that renders its own richer label on a surface it owns (e.g. Expanse, which
--- draws a combined team/cells/invasion overlay on each cell world) calls this to
--- suppress the duplicate. Keyed by surface NAME (stable across the game) so a
--- reused surface index can't carry a stale flag. Destroys any label already drawn.
function spawn_labels.set_enabled(surface_name, enabled)
    if type(surface_name) ~= "string" then return end
    storage.spawn_labels_disabled = storage.spawn_labels_disabled or {}
    storage.spawn_labels_disabled[surface_name] = (not enabled) or nil
    if enabled then return end
    local surface = game.surfaces[surface_name]
    if not (surface and surface.valid) then return end
    for _, labels in pairs(storage.spawn_labels or {}) do
        local id = labels[surface.index]
        if id then
            local obj = rendering.get_object_by_id(id)
            if obj and obj.valid then obj.destroy() end
            labels[surface.index] = nil
        end
    end
end

--- Display name for the second label line. Space platforms use the
--- platform's display name; planet variants / cloned surfaces use the
--- capitalised base planet name.
local function location_name_for(surface, force)
    for _, plat in pairs(force.platforms or {}) do
        if plat.surface and plat.surface.valid
           and plat.surface.index == surface.index then
            return plat.name
        end
    end
    return helpers.display_surface_name(surface.name)
end

local function compute_text(force_name, location_name)
    local text = helpers.team_tag_with_leader(force_name) .. "'s\n" .. location_name
    -- Birth-clock line, nearest-minute resolution: labels refresh every 10s
    -- (the 600-tick handler in events/ticks.lua), so a seconds digit would
    -- sit visibly stale. Omitted until the team's clock starts.
    local start = (storage.team_clock_start or {})[force_name]
    if start then
        text = text .. "\n[img=utility/clock] "
            .. helpers.fmt_duration_coarse(game.tick - start)
    end
    return text
end

--- Draw or replace the spawn label for a (force, surface) pair.
---
--- opts:
---   target        — entity or position table (default {x = 0, y = -8})
---   target_offset — offset from the target entity (entity targets only)
function spawn_labels.draw(force_name, surface, opts)
    opts = opts or {}
    if not (surface and surface.valid) then return end
    if (storage.spawn_labels_disabled or {})[surface.name] then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end

    storage.spawn_labels = storage.spawn_labels or {}
    storage.spawn_labels[force_name] = storage.spawn_labels[force_name] or {}

    local existing_id = storage.spawn_labels[force_name][surface.index]
    if existing_id then
        local obj = rendering.get_object_by_id(existing_id)
        if obj and obj.valid then obj.destroy() end
    end

    local args = {
        text          = compute_text(force_name, location_name_for(surface, force)),
        surface       = surface,
        target        = opts.target or {x = 0, y = -8},
        color         = {r = 1, g = 1, b = 1, a = 1},
        scale         = 3,
        alignment     = "center",
        use_rich_text = true,
    }
    if opts.target_offset then args.target_offset = opts.target_offset end

    local obj = rendering.draw_text(args)
    storage.spawn_labels[force_name][surface.index] = obj and obj.id or nil
end

--- Update text on every label belonging to this force. Cleans stale entries.
function spawn_labels.refresh_for_force(force_name)
    storage.spawn_labels = storage.spawn_labels or {}
    local labels = storage.spawn_labels[force_name]
    if not labels then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end

    for surface_index, render_id in pairs(labels) do
        local surface = game.surfaces[surface_index]
        local obj = rendering.get_object_by_id(render_id)
        if surface and surface.valid and obj and obj.valid then
            obj.text = compute_text(force_name, location_name_for(surface, force))
        else
            labels[surface_index] = nil
        end
    end
end

--- Recompute text on every drawn label (periodic clock refresh).
function spawn_labels.refresh_all()
    for force_name in pairs(storage.spawn_labels or {}) do
        spawn_labels.refresh_for_force(force_name)
    end
end

return spawn_labels
