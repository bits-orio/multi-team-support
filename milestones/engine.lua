-- Multi-Team Support - milestones/engine.lua
-- Author: bits-orio
-- License: MIT
--
-- Generic milestone tracking engine. Polls production counters and
-- announces first/fastest records when teams cross configured thresholds.
--
-- Polled every 300 ticks (5 seconds) via on_nth_tick in control.lua.
-- Uses the shared records module for first/fastest logic.

local records     = require("records")
local helpers     = require("helpers")
local force_utils = require("force_utils")
local config      = require("milestones.config")

local engine = {}

-- Special threshold marker for "first to produce" (count >= 1).
-- Stored under this key in milestone_records and milestone_reached.
local FIRST_THRESHOLD = 0

-- ─── Storage Initialization ───────────────────────────────────────────

function engine.init_storage()
    storage.milestone_records  = storage.milestone_records  or {}
    storage.milestone_reached  = storage.milestone_reached  or {}
    storage.milestone_items    = storage.milestone_items    or {}
end

--- Run each tracker's discover_items function to build the item set.
--- Called on_init and on_configuration_changed to handle mod changes.
function engine.discover_items()
    engine.init_storage()
    storage.milestone_items = {}
    for _, tracker in ipairs(config.trackers) do
        local items = tracker.discover_items() or {}
        storage.milestone_items[tracker.category] = items
    end
end

-- ─── Announcement Helpers ─────────────────────────────────────────────

--- Build the description of what was achieved.
---   first threshold + science → "produce their first [item=automation-science-pack]"
---   100 threshold + landfill  → "produce 100 landfill"
local function build_achievement_desc(tracker, item_name, threshold)
    if threshold == FIRST_THRESHOLD then
        return "produce their first " .. helpers.item_rich_name(item_name)
    end
    return string.format("produce %d %s", threshold, tracker.label)
end

--- Announce a "first to X" milestone.
local function announce_first(team_tag, achievement)
    helpers.broadcast(string.format(
        "[Records] %s was the first to %s!",
        team_tag, achievement
    ))
end

--- Announce a new speed record for an existing milestone.
local function announce_speed_record(team_tag, achievement, new_elapsed, prev_team_tag, prev_elapsed)
    helpers.broadcast(string.format(
        "[Records] %s is fastest to %s in %s (previous record: %s in %s)",
        team_tag, achievement,
        helpers.format_elapsed(new_elapsed),
        prev_team_tag,
        helpers.format_elapsed(prev_elapsed)
    ))
end

-- ─── Milestone Check Logic ────────────────────────────────────────────

--- Check a single (tracker, item, force, threshold) combination.
--- If the force has crossed the threshold and not yet recorded it:
---   - Mark as reached (prevents re-announcing)
---   - Update records (first/fastest)
---   - Announce as appropriate
local function check_milestone(tracker, item_name, force, threshold)
    local key = tracker.category .. ":" .. item_name

    -- Track per-team "reached" state so we only announce each crossing once
    storage.milestone_reached[force.name] = storage.milestone_reached[force.name] or {}
    storage.milestone_reached[force.name][key] = storage.milestone_reached[force.name][key] or {}
    if storage.milestone_reached[force.name][key][threshold] then return end

    storage.milestone_reached[force.name][key][threshold] = true

    -- Record key includes threshold so "first-to-produce" and "first-to-100" are separate
    local record_key = key .. "@" .. threshold
    local result = records.update(storage.milestone_records, record_key, force.name, game.tick)

    local team_tag    = helpers.team_tag(force.name)
    local achievement = build_achievement_desc(tracker, item_name, threshold)

    if result.is_first then
        announce_first(team_tag, achievement)
    elseif result.is_fastest then
        local prev = result.previous_fastest
        local new_entry = storage.milestone_records[record_key].fastest
        announce_speed_record(
            team_tag, achievement,
            new_entry.elapsed,
            helpers.team_tag(prev.team),
            prev.elapsed
        )
    end
end

--- Check all thresholds for a single (tracker, item, force).
local function check_all_thresholds(tracker, item_name, force)
    local count = tracker.get_count(force, item_name)
    if count < 1 then return end

    -- "First to produce" milestone (threshold 0 marker)
    if tracker.announce_first then
        check_milestone(tracker, item_name, force, FIRST_THRESHOLD)
    end

    -- Numeric thresholds
    for _, threshold in ipairs(tracker.thresholds) do
        if count >= threshold then
            check_milestone(tracker, item_name, force, threshold)
        end
    end
end

-- ─── Tick Handler ─────────────────────────────────────────────────────

--- Called every 300 ticks (5 seconds) from control.lua's on_nth_tick.
--- Iterates all trackers × items × occupied teams and checks thresholds.
function engine.tick()
    engine.init_storage()

    for _, tracker in ipairs(config.trackers) do
        local items = storage.milestone_items[tracker.category] or {}
        for item_name in pairs(items) do
            for _, force in pairs(game.forces) do
                -- Only check occupied team forces
                if force_utils.is_team_force(force.name) and #force.players > 0 then
                    check_all_thresholds(tracker, item_name, force)
                end
            end
        end
    end
end

return engine
