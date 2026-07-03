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
    -- force name -> the last announced launch MARK. Seeded from each force's
    -- current total on FIRST creation so adding/updating the mod on a live save
    -- doesn't re-announce the current neighbourhood -- it stays quiet until the
    -- next genuine mark is crossed. (Existing deployments already hold raw totals
    -- here from older versions, which give the same quiet behaviour, so the guard
    -- leaves them untouched.)
    if not storage.rocket_announced then
        storage.rocket_announced = {}
        for _, force in pairs(game.forces) do
            if force.valid and (force.rockets_launched or 0) > 0 then
                storage.rocket_announced[force.name] = force.rockets_launched
            end
        end
    end
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
-- which would flood the Discord bridge. The announcement cadence WIDENS in tiers
-- as the running total grows, so the number of posts per tier stays bounded no
-- matter how big the base gets:
--
--   total ≤ 10     every launch      (10 posts)
--   total ≤ 100    one per 5         (18 posts: 15, 20, … 100)
--   total ≤ 500    one per 25        (16 posts: 125, 150, … 500)
--   total ≤ 1000   one per 50        (10 posts: 550, 600, … 1000)
--   total > 1000   one per 100       (terminal cadence, forever)
--
-- So a 45k-launch megabase posts once every ~100 rockets, not the old every-25.
-- Each tier is ~10–18 posts, then a flat 1-per-100 — the feed never speeds up
-- again past 1000 launches.
local ROCKET_TIERS = {
    { upto = 10,        step = 1   },
    { upto = 100,       step = 5   },
    { upto = 500,       step = 25  },
    { upto = 1000,      step = 50  },
    { upto = math.huge, step = 100 },
}

--- The announcement step for a given running total (see ROCKET_TIERS).
local function rocket_announce_step(total)
    for _, tier in ipairs(ROCKET_TIERS) do
        if total <= tier.upto then return tier.step end
    end
    return 100  -- unreachable: the math.huge tier catches everything; defensive
end

-- Report the HIGHEST step-multiple the counter has reached that hasn't been
-- announced yet, rather than testing `total % step == 0`. Two engine realities:
--   • force.rockets_launched skips and duplicates values when several rockets
--     resolve close together (live logs show "...30254, 30254, 30256..."), so a
--     plain exact-multiple test goes silent when the multiple is skipped and
--     double-posts when a duplicate lands on one.
--   • the announced number should read cleanly, not as a raw overshoot (…45301).
-- floor(total/step)*step is the highest multiple the counter has reached; report
-- it whenever it exceeds the last reported mark. The feed never goes silent,
-- never double-posts, and every announced number past 10 is a step multiple
-- (…45300, 45400) — always ending in 0 or 5. Deriving the mark from the CURRENT
-- total (not last+step) also means a fresh install / counter reset on an already-
-- huge force jumps straight to the current neighbourhood instead of crawling up
-- from a low number. A tier boundary widens the step, so the next mark lands on
-- the wider grid (after 100 the next is 125, after 1000 it's 1100).
--- @return integer|nil  the mark reached — the highest unannounced step multiple
---   past 10, or the raw count at/below 10 — or nil when no new mark is due.
local function rocket_announce_mark(last, total)
    if total < last then return total end          -- counter reset (force recreated): re-arm on raw count
    if total <= 10 then                            -- pre-alignment tier: every launch, raw count
        return (total > last) and total or nil
    end
    local step = rocket_announce_step(total)
    local mark = math.floor(total / step) * step   -- highest step multiple the counter has reached
    return (mark > last) and mark or nil
end

function M.on_rocket_launched(event)
    M.init_storage()

    local rocket = event.rocket
    if not (rocket and rocket.valid) then return end
    local force = rocket.force

    -- Team-specific Discord announcement (suppresses vanilla.rocket_launched),
    -- throttled by rocket_announce_mark to keep late-game spam down. The reported
    -- total is the round MARK (a step multiple), not the raw counter, so the feed
    -- reads on clean numbers.
    if force_utils.is_team_force(force.name) then
        local mark = rocket_announce_mark(storage.rocket_announced[force.name] or 0, force.rockets_launched)
        if mark then
            storage.rocket_announced[force.name] = mark
            local team = (storage.team_names or {})[force.name] or force.name
            remote_api.emit_to_bridge("mts.rocket_launched", {
                team         = team,
                flight_count = mark,
                text         = string.format("%s launched a rocket (total: %d)", team, mark),
            })
        end
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
