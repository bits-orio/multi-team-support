-- Multi-Team Support - spawn_labels.lua
-- Author: bits-orio
-- License: MIT
--
-- Renders a "<team_tag_with_leader>'s\n<location_name>" label at the spawn
-- area of every team-owned surface. The render-object id is tracked in
-- storage so the text can be live-refreshed when the team is renamed or
-- when the leader changes.
--
-- Storage layout:
--   storage.spawn_labels[force_name][surface_index] = render_object_id

local helpers = require("scripts.helpers")

local spawn_labels = {}

function spawn_labels.init_storage()
    storage.spawn_labels = storage.spawn_labels or {}
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
    return helpers.team_tag_with_leader(force_name) .. "'s\n" .. location_name
end

--- Draw or replace the spawn label for a (force, surface) pair.
---
--- opts:
---   target        — entity or position table (default {x = 0, y = -8})
---   target_offset — offset from the target entity (entity targets only)
function spawn_labels.draw(force_name, surface, opts)
    opts = opts or {}
    if not (surface and surface.valid) then return end
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

return spawn_labels
