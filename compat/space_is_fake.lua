-- Multi-Team Support - compat/space_is_fake.lua
-- Author: bits-orio
-- License: MIT
--
-- Compatibility with Space Is Fake ("Space Age compressed to Nauvis") by Crethor.
-- https://mods.factorio.com/mod/space-is-fake
--
-- Architecture
-- ────────────
-- SiF's terrain, ores, recipes, tech AND its demolisher territories are all
-- data-stage changes to the Nauvis prototype, so a team's Nauvis variant
-- inherits them and generates them natively. For that to survive, MTS must not
-- clone the base Nauvis onto the variant (clone_area destroys the demolishers),
-- so clone_mirror skips cloning whenever SiF is active. See clone_mirror.lua.
--
-- What still needs help even in native mode is SiF's one-time STARTING-AREA
-- setup. SiF places it in its on_player_created handler — a dead-engineer
-- chest with starting loot, a field of trees, lava-edge ash painting, an
-- optional ruin attractor — written to the real `nauvis` surface, which MTS
-- hides from teams. Native generation reproduces SiF's map-gen but NOT this
-- runtime placement, and there's no clone to copy it across, so each team's
-- variant would spawn bare. This shim re-runs that world setup on each team's
-- Nauvis variant exactly once, after the player has been teleported there
-- (so the surface is generated and nothing overwrites what we place).
--
-- Mirrors prototypes/control/on-player-created.lua in space-is-fake 1.0.45;
-- keep in sync if SiF changes its starting layout. Entities use the neutral
-- force, exactly as SiF does.
--
-- Not handled: SiF's per-player character kit / cheat loadout / intro prints
-- (per-player; SiF applies them itself), and the obsidiax sub-mode
-- (sif-map = "obsidiax"), whose lava-heat runtime rules are keyed to
-- surface.name == "nauvis" and would also need generalizing.

local remote_api = require("scripts.remote_api")

local M = {}

function M.is_active()
    return script.active_mods["space-is-fake"] ~= nil
end

-- Box-platform tile per alternate map setting. The default "sif" map keeps
-- "stone-path" (no box repaint), matching SiF: only these settings repaint.
local BOX_TILE = {
    vulcanus = "volcanic-cracks-warm",
    fulgora  = "fulgoran-rock",
    gleba    = "natural-yumako-soil",
    aquilo   = "snow-flat",
    pelagos  = "pelagos-sand-1",
    lignumis = "natural-gold-soil",
}

local TREE_POSITIONS = {
    { -28, 28 }, { -16, 28 }, { -8, 28 }, { 2, 28 }, { 12, 28 }, { 22, 28 },
    { -28, 36 }, { -18, 36 }, { -8, 36 }, { 4, 36 }, { 12, 36 }, { 22, 36 },
    { 14, 28 }, { 24, 28 }, { -26, 30 }, { -26, 32 }, { -16, 32 }, { 24, 32 },
    { 4,  34 }, { -6, 36 }, { 14, 36 }, { 24, 36 }, { -28, 30 }, { -18, 30 },
    { -8, 30 }, { 2, 30 }, { 14, 30 }, { 22, 30 }, { -28, 32 }, { -18, 32 },
    { -8, 32 }, { 2, 32 }, { 14, 32 }, { 22, 32 }, { -28, 34 }, { -18, 34 },
    { -8, 34 }, { 14, 34 }, { -22, 28 }, { -14, 28 }, { -2, 28 }, { 8, 28 },
    { 18, 28 }, { 28, 28 }, { -22, 36 }, { -12, 36 }, { 6, 36 }, { -2, 36 },
    { 18, 36 }, { 28, 36 }, { 16, 28 }, { 26, 28 }, { -24, 32 }, { -14, 32 },
    { 26, 32 }, { -24, 34 }, { 6, 34 }, { -4, 36 }, { 16, 36 }, { 26, 36 },
    { -22, 30 }, { -12, 30 }, { -2, 30 }, { 8, 30 }, { 16, 30 }, { -22, 32 },
    { -12, 32 }, { -2, 32 }, { 8, 32 }, { 16, 32 }, { 28, 32 }, { -22, 34 },
    { -12, 34 }, { -2, 34 }, { 16, 34 }, { 28, 34 }
}

local function is_lava(tile_name)
    return tile_name == "lava" or tile_name == "lava-hot"
end

-- Paint volcanic ash over lava tiles just inside a water edge, within
-- `radius` of `center`. Faithful to SiF's lava-edge pass.
local function paint_lava_ash(surface, center)
    local radius = 200
    local area = {
        { center.x - radius, center.y - radius },
        { center.x + radius, center.y + radius },
    }
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local set_tiles = {}
    for _, tile in pairs(surface.find_tiles_filtered{ area = area, name = "water" }) do
        local tx, ty = tile.position.x, tile.position.y
        for _, d in pairs(dirs) do
            local neighbor = surface.get_tile(tx + d[1], ty + d[2])
            if neighbor and is_lava(neighbor.name) then
                for i = 1, 2 do
                    local lx, ly = tx + d[1] * i, ty + d[2] * i
                    local lava = surface.get_tile(lx, ly)
                    if lava and is_lava(lava.name) then
                        set_tiles[#set_tiles + 1] =
                            { name = "volcanic-ash-dark", position = { lx, ly } }
                    end
                end
            end
        end
    end
    if #set_tiles > 0 then surface.set_tiles(set_tiles, true) end
end

-- Repaint the starting platform box for alternate map settings (no-op for the
-- default "sif" map), clearing decoratives and rocks from it as SiF does.
local function paint_box(surface, map_setting)
    local box_tile = BOX_TILE[map_setting]
    if not box_tile then return end
    local tiles = {}
    for x = -33, 32 do
        for y = 23, 40 do
            tiles[#tiles + 1] = { name = box_tile, position = { x, y } }
        end
    end
    surface.set_tiles(tiles, true)
    local box_area = { { -33, 23 }, { 32, 40 } }
    surface.destroy_decoratives{ area = box_area }
    for _, entity in pairs(surface.find_entities_filtered{ area = box_area, type = "simple-entity" }) do
        if entity.valid then entity.destroy() end
    end
end

-- Place SiF's full starting layout on `surface`, centered on the spawn at
-- `center`. SiF splits tiles (player.surface) and entities (game.surfaces.
-- nauvis) across two surfaces; on a single team variant the two coincide.
local function place_starting_area(surface, center)
    paint_lava_ash(surface, center)
    paint_box(surface, settings.startup["sif-map"].value)

    for _, pos in ipairs(TREE_POSITIONS) do
        surface.create_entity{ name = "tree-plant", position = pos, force = "neutral" }
    end

    local chest = surface.create_entity{ name = "dead-engineer", position = { 4, 10 }, force = "neutral" }
    if chest and chest.valid then
        local inv = chest.get_inventory(defines.inventory.chest)
        if inv then
            inv.insert{ name = "lucky-coin", count = 6 }
            inv.insert{ name = "scrap", count = 50 }
            inv.insert{ name = "cliff-explosives", count = 20 }
        end
    end

    if settings.startup["space-is-fake-zstorm"].value then
        surface.create_entity{ name = "fulgoran-ruin-attractor", position = { 0, 8 }, force = "neutral" }
    end
end

-- Called from compat_utils.process_pending_teleports, once the player is on
-- their team surface. Sets up the SiF starting area on the team's Nauvis
-- variant exactly once (guard keyed by surface name).
function M.after_spawn(player)
    if not M.is_active() then return end
    if not (player and player.valid) then return end
    local surface = player.surface
    if not (surface and surface.valid) then return end

    -- Only the team's Nauvis variant. SiF requires Space Age, so the home
    -- surface is "mts-nauvis-<N>"; "team-<N>-nauvis" matched as defence-in-depth.
    local base = surface.name:match("^mts%-(.+)%-%d+$")
              or surface.name:match("^team%-%d+%-(.+)$")
    if base ~= "nauvis" then return end

    storage.sif_setup_done = storage.sif_setup_done or {}
    if storage.sif_setup_done[surface.name] then return end
    storage.sif_setup_done[surface.name] = true

    place_starting_area(surface, player.position)
end

-- Called from init_events().
function M.register_events()
    if not M.is_active() then return end
    -- On slot recycle the team's surface is deleted. Clear the setup guard for
    -- any surface that no longer exists, so the next occupant of a recycled
    -- slot (fresh surface, same name) gets its starting area.
    script.on_event(remote_api.events.on_team_released, function()
        if not storage.sif_setup_done then return end
        for name in pairs(storage.sif_setup_done) do
            if not game.surfaces[name] then
                storage.sif_setup_done[name] = nil
            end
        end
    end)
end

return M
