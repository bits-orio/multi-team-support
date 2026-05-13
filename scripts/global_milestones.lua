-- scripts/global_milestones.lua
-- Server-wide "first ever" celebrations: first rocket launched and first
-- landing on each planet. Each flag fires at most once per save, and the
-- announcement is broadcast to every player + drawn on every screen via
-- pop_text.global_milestone.
--
-- LuaSurface.planet.name is used to identify the planet, which works
-- transparently for per-team planet variants (mts-vulcanus-1 etc. all
-- report "vulcanus") and for modded planets (any prototype registered
-- as a planet is detected automatically).

local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local pop_text    = require("scripts.pop_text")

local M = {}

function M.init_storage()
    storage.global_records = storage.global_records or {}
    storage.global_records.first_rocket          = storage.global_records.first_rocket or false
    storage.global_records.first_planet_landings = storage.global_records.first_planet_landings or {}
end

-- Tried in order; first valid path wins. "achievement_unlocked" is the
-- ideal fit but isn't in every base game version, so research_completed
-- is the fallback (every Factorio install has it).
local SOUND_CANDIDATES = {
    "utility/achievement_unlocked",
    "utility/research_completed",
}

local function play_global_sound()
    for _, p in pairs(game.players) do
        if p.connected then
            for _, path in ipairs(SOUND_CANDIDATES) do
                local ok = pcall(function() p.play_sound{path = path} end)
                if ok then break end
            end
        end
    end
end

local function announce(text_str)
    helpers.broadcast(text_str)
    pop_text.global_milestone(text_str)
    play_global_sound()
end

-- ─── First rocket launched ────────────────────────────────────────────

function M.on_rocket_launched(event)
    M.init_storage()
    if storage.global_records.first_rocket then return end
    storage.global_records.first_rocket = true

    local rocket = event.rocket
    local force = rocket and rocket.valid and rocket.force or nil
    local team_tag = force and helpers.team_tag_with_leader(force.name) or "A team"

    announce(team_tag .. " launched the first rocket into space!")
end

-- ─── First landing on each planet ─────────────────────────────────────

--- Returns the canonical planet name for a surface, or nil if the surface
--- isn't a planet (platform, landing-pen, custom non-planet surface).
local function planet_name_of(surface)
    if not (surface and surface.valid) then return nil end
    local planet = surface.planet
    if not (planet and planet.valid) then return nil end
    return planet.name
end

--- Called from the existing on_player_changed_surface handler. `was_spawning`
--- is true when the player just transitioned from the landing-pen / spawn
--- flow -- in that case we mark the planet as seen silently (so a later
--- visit from a platform doesn't fire a misleading "first landing") without
--- broadcasting, since the starting planet would otherwise fanfare for the
--- very first team to spawn.
function M.check_planet_landing(player, was_spawning)
    if not (player and player.valid and player.connected) then return end

    -- Not actually present: in remote view of someone else's surface.
    if player.physical_surface
       and player.physical_surface.valid
       and player.surface
       and player.physical_surface.index ~= player.surface.index then
        return
    end

    -- Spectator force shouldn't trigger first-landing announcements.
    if not force_utils.is_team_force(player.force.name) then return end

    local pname = planet_name_of(player.surface)
    if not pname then return end

    M.init_storage()
    local landings = storage.global_records.first_planet_landings
    if landings[pname] then return end
    landings[pname] = player.force.name

    if was_spawning then return end

    local team_tag   = helpers.team_tag_with_leader(player.force.name)
    local planet_tag = "[planet=" .. pname .. "]"

    announce(team_tag .. " was first to set foot on " .. planet_tag .. "!")
end

-- ─── Event registration ───────────────────────────────────────────────

function M.register()
    script.on_event(defines.events.on_rocket_launched, M.on_rocket_launched)
end

return M
