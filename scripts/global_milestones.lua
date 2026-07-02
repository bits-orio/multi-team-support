-- scripts/global_milestones.lua
-- Server-wide "first ever" celebrations: first rocket launched and first
-- landing on each planet. Each flag fires at most once per save, and the
-- announcement is broadcast to every player + drawn on every screen via
-- pop_text.global_milestone.
--
-- LuaSurface.planet.name identifies the planet, but each per-team variant
-- is its own planet prototype (mts-vulcanus-1, mts-vulcanus-2, ...), so the
-- name is normalized back to its canonical base ("vulcanus") via
-- space_age.parse_variant. Without this every team's variant counts as a
-- distinct planet and the "first landing" celebration fires once per team
-- instead of once per save. Modded planets (any prototype registered as a
-- planet) are detected automatically and normalized the same way.

local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local pop_text    = require("scripts.pop_text")
local space_age   = require("scripts.space_age")
local remote_api  = require("scripts.remote_api")

local M = {}

function M.init_storage()
    storage.global_records = storage.global_records or {}
    storage.global_records.first_rocket          = storage.global_records.first_rocket or false
    storage.global_records.first_planet_landings = storage.global_records.first_planet_landings or {}
    -- force name -> rockets_launched total at the last bridge announcement
    storage.rocket_announced = storage.rocket_announced or {}
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

-- Late-game teams launch rockets continuously (tens of thousands of launches),
-- which floods the Discord bridge. Announce every launch up to 10 total, then
-- one per 5 launches up to 100, then one per 25.
--
-- Announce when the counter reaches-or-passes the NEXT ROUND MULTIPLE of the step
-- (…30275, 30300, 30325), rather than `total % step == 0`: force.rockets_launched
-- skips and duplicates values when several rockets resolve close together (live
-- logs show "...30254, 30254, 30256..."), so the exact-multiple check goes silent
-- for a whole window when the multiple lands on a skipped value, and double-posts
-- when a duplicate lands on one. Reach-or-pass keeps announced totals on round
-- numbers in the common case and only overshoots by the skip amount otherwise.
local function should_announce_rocket(force_name, total)
    if total <= 10 then return true end
    local step = (total <= 100) and 5 or 25
    local last = storage.rocket_announced[force_name] or 0
    if total < last then return true end -- counter reset (force deleted/recreated): re-arm
    local next_mark = (math.floor(last / step) + 1) * step
    return total >= next_mark
end

function M.on_rocket_launched(event)
    M.init_storage()

    local rocket = event.rocket
    if not (rocket and rocket.valid) then return end
    local force = rocket.force

    -- Team-specific Discord announcement (suppresses vanilla.rocket_launched),
    -- throttled by should_announce_rocket to keep late-game spam down.
    if force_utils.is_team_force(force.name) and should_announce_rocket(force.name, force.rockets_launched) then
        storage.rocket_announced[force.name] = force.rockets_launched
        local team = (storage.team_names or {})[force.name] or force.name
        remote_api.emit_to_bridge("mts.rocket_launched", {
            team         = team,
            flight_count = force.rockets_launched,
            text         = string.format("%s launched a rocket (total: %d)", team, force.rockets_launched),
        })
    end

    -- First-ever rocket global milestone (fires once per save).
    if storage.global_records.first_rocket then return end
    storage.global_records.first_rocket = true

    local team_tag = helpers.team_tag_with_leader(force.name) or "A team"
    announce(team_tag .. " launched the first rocket into space!")
end

-- ─── First landing on each planet ─────────────────────────────────────

--- Returns the canonical planet name for a surface, or nil if the surface
--- isn't a planet (platform, landing-pen, custom non-planet surface).
local function planet_name_of(surface)
    if not (surface and surface.valid) then return nil end
    local planet = surface.planet
    if not (planet and planet.valid) then return nil end
    -- Collapse per-team variants (mts-vulcanus-1) to their base (vulcanus)
    -- so the first-landing gate is shared across every team's copy.
    local base = space_age.parse_variant(planet.name)
    return base or planet.name
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
