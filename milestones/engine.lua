-- Multi-Team Support - milestones/engine.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Generic milestone tracking engine. Polls production counters and
-- announces first/fastest records when teams cross configured thresholds.
--
-- Polled every 300 ticks (5 seconds) via on_nth_tick in control.lua.
-- Uses the shared records module for first/fastest logic.

local records     = require("scripts.records")
local helpers     = require("scripts.helpers")
local force_utils = require("scripts.force_utils")
local config      = require("milestones.config")
local pop_text    = require("scripts.pop_text")
local remote_api  = require("scripts.remote_api")

--- Strip Factorio rich-text tags (e.g. "[item=foo]" -> "foo") so milestone text
--- reads cleanly in Discord, which can't render them.
local function plain(s)
    return (s:gsub("%[%a+=([%w%-_./]+)%]", "%1"))
end

local engine = {}

-- Special threshold marker for "first to produce" (count >= 1).
-- Stored under this key in milestone_records and milestone_reached.
local FIRST_THRESHOLD = 0

-- Reset on every load (module-local). engine.tick re-discovers once per session if this is
-- still false, so trackers added to config since the save's last on_init / on_configuration_-
-- changed are picked up on a plain reload (storage.milestone_items persists, so a new tracker
-- would otherwise stay invisible until a config change).
local discovered_this_session = false

-- ─── Storage Initialization ───────────────────────────────────────────

function engine.init_storage()
    storage.milestone_records  = storage.milestone_records  or {}
    storage.milestone_reached  = storage.milestone_reached  or {}
    storage.milestone_items    = storage.milestone_items    or {}
    storage.milestone_external = storage.milestone_external or {}
end

--- Build a short two-line popup string for the milestone overlay.
---   is_first + first-threshold  → "First!\n[item=X]"
---   is_first + count-threshold  → "First!\n100x [item=X]"
---   fastest  + any threshold    → "New record!\n[same]"
local function build_popup(label, item_name, threshold)
    local item_tag = helpers.item_rich_name(item_name)
    if threshold == FIRST_THRESHOLD then
        return label .. "\n" .. item_tag
    end
    return label .. "\n" .. threshold .. "x " .. item_tag
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
    discovered_this_session = true
end

-- ─── Announcement Helpers ─────────────────────────────────────────────

--- Build the description of what was achieved.
---   first threshold + science → "produce their first [item=automation-science-pack]"
---   100 threshold + landfill  → "produce 100 [item=landfill]"
local function build_achievement_desc(tracker, item_name, threshold)
    if threshold == FIRST_THRESHOLD then
        return "produce their first " .. helpers.item_rich_name(item_name)
    end
    return string.format("produce %d %s", threshold, helpers.item_rich_name(item_name))
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
--- Returns true if a new milestone was recorded, false if already reached.
local function check_milestone(tracker, item_name, force, threshold)
    local key = tracker.category .. ":" .. item_name

    -- Track per-team "reached" state so we only announce each crossing once
    storage.milestone_reached[force.name] = storage.milestone_reached[force.name] or {}
    storage.milestone_reached[force.name][key] = storage.milestone_reached[force.name][key] or {}
    if storage.milestone_reached[force.name][key][threshold] then return false end

    storage.milestone_reached[force.name][key][threshold] = true

    -- Record key includes threshold so "first-to-produce" and "first-to-100" are separate
    local record_key = key .. "@" .. threshold
    local result = records.update(storage.milestone_records, record_key, force.name, game.tick)

    local team_tag    = helpers.team_tag(force.name)
    local achievement = build_achievement_desc(tracker, item_name, threshold)
    local team_name   = (storage.team_names or {})[force.name] or force.name

    if result.is_first then
        announce_first(team_tag, achievement)
        pop_text.milestone(force, build_popup("First!", item_name, threshold))
        remote_api.emit_to_bridge("mts.milestone_first", {
            team        = team_name,
            achievement = plain(achievement),
            text        = string.format("%s was the first to %s", team_name, plain(achievement)),
        })
    elseif result.is_fastest then
        local prev = result.previous_fastest
        local new_entry = storage.milestone_records[record_key].fastest
        announce_speed_record(
            team_tag, achievement,
            new_entry.elapsed,
            helpers.team_tag(prev.team),
            prev.elapsed
        )
        pop_text.milestone(force, build_popup("New record!", item_name, threshold))
        local prev_team = (storage.team_names or {})[prev.team] or prev.team
        remote_api.emit_to_bridge("mts.milestone_record", {
            team             = team_name,
            achievement      = plain(achievement),
            elapsed          = new_entry.elapsed,
            previous_team    = prev_team,
            previous_elapsed = prev.elapsed,
            text             = string.format(
                "%s is now fastest to %s in %s (previous: %s in %s)",
                team_name, plain(achievement),
                helpers.format_elapsed(new_entry.elapsed),
                prev_team, helpers.format_elapsed(prev.elapsed)
            ),
        })
    end
    return true
end

--- Check all thresholds for a single (tracker, item, force).
--- Returns true if any milestone was newly recorded.
local function check_all_thresholds(tracker, item_name, force)
    local count = tracker.get_count(force, item_name)
    if count < 1 then return false end

    local changed = false

    -- "First to produce" milestone (threshold 0 marker)
    if tracker.announce_first then
        if check_milestone(tracker, item_name, force, FIRST_THRESHOLD) then
            changed = true
        end
    end

    -- Numeric thresholds
    for _, threshold in ipairs(tracker.thresholds) do
        if count >= threshold then
            if check_milestone(tracker, item_name, force, threshold) then
                changed = true
            end
        end
    end

    return changed
end

-- ─── Tick Handler ─────────────────────────────────────────────────────

--- Called every 300 ticks (5 seconds) from control.lua's on_nth_tick.
--- Iterates all trackers × items × occupied teams and checks thresholds.
--- Returns true if any new milestone was recorded this tick (so the caller
--- can refresh dependent GUIs without re-polling storage).
function engine.tick()
    engine.init_storage()
    -- Self-heal discovery after a plain reload (on_init / on_configuration_changed didn't run),
    -- so trackers added to config.lua since this save's last config change start tracking.
    if not discovered_this_session then
        engine.discover_items()
    end

    local changed = false
    for _, tracker in ipairs(config.trackers) do
        local items = storage.milestone_items[tracker.category] or {}
        for item_name in pairs(items) do
            for _, force in pairs(game.forces) do
                if force_utils.is_team_force(force.name) and #force.players > 0 then
                    if check_all_thresholds(tracker, item_name, force) then
                        changed = true
                    end
                end
            end
        end
    end
    return changed
end

-- ─── External (consumer-reported) milestones ──────────────────────────
-- A mod reports a per-team counter (e.g. Expanse cells unlocked) via
-- remote.call("mts-v1","report_milestone",...); we announce first/fastest using the same
-- records + broadcast + Discord machinery as the built-in trackers. The registry is
-- persisted; reporting is event-driven (no polling). remote_api requires this module, not
-- the reverse, so the interface entries are injected at the bottom.

local function build_external_achievement(spec, threshold, first_only)
    local verb = spec.verb or "reach"
    if first_only then
        return verb .. " their first " .. spec.noun
    end
    return string.format("%s %d %s", verb, threshold, spec.noun .. "s")
end

-- first_only: announce first-to-reach only (no speed record). Used for the smallest
-- threshold, where a "fastest" race isn't wanted (e.g. the very first unlock).
local function check_external(spec, force, threshold, first_only)
    local key = "ext:" .. spec.category
    storage.milestone_reached[force.name] = storage.milestone_reached[force.name] or {}
    storage.milestone_reached[force.name][key] = storage.milestone_reached[force.name][key] or {}
    if storage.milestone_reached[force.name][key][threshold] then return end
    storage.milestone_reached[force.name][key][threshold] = true

    local record_key   = key .. "@" .. threshold
    local result       = records.update(storage.milestone_records, record_key, force.name, game.tick)
    local team_tag     = helpers.team_tag(force.name)
    local team_name    = (storage.team_names or {})[force.name] or force.name
    local achievement  = build_external_achievement(spec, threshold, first_only)
    local popup_detail = first_only and spec.noun or (threshold .. " " .. spec.noun .. "s")

    if result.is_first then
        announce_first(team_tag, achievement)
        pop_text.milestone(force, "First!\n" .. popup_detail)
        remote_api.emit_to_bridge("mts.milestone_first", {
            team        = team_name,
            achievement = achievement,
            text        = string.format("%s was the first to %s", team_name, achievement),
        })
    elseif not first_only and result.is_fastest then
        local prev      = result.previous_fastest
        local new_entry = storage.milestone_records[record_key].fastest
        announce_speed_record(team_tag, achievement, new_entry.elapsed,
            helpers.team_tag(prev.team), prev.elapsed)
        pop_text.milestone(force, "New record!\n" .. popup_detail)
        local prev_team = (storage.team_names or {})[prev.team] or prev.team
        remote_api.emit_to_bridge("mts.milestone_record", {
            team             = team_name,
            achievement      = achievement,
            elapsed          = new_entry.elapsed,
            previous_team    = prev_team,
            previous_elapsed = prev.elapsed,
            text             = string.format(
                "%s is now fastest to %s in %s (previous: %s in %s)",
                team_name, achievement, helpers.format_elapsed(new_entry.elapsed),
                prev_team, helpers.format_elapsed(prev.elapsed)),
        })
    end
end

--- Register a consumer milestone. spec = { category, verb, noun, first_threshold, thresholds }.
--- first_threshold (optional) gets a first-to-reach announcement only; each entry in
--- thresholds gets both first AND fastest.
function engine.register_external(spec)
    if type(spec) ~= "table" or type(spec.category) ~= "string" then return end
    engine.init_storage()
    storage.milestone_external[spec.category] = {
        category        = spec.category,
        verb            = spec.verb or "reach",
        noun            = spec.noun or spec.category,
        first_threshold = type(spec.first_threshold) == "number" and spec.first_threshold or nil,
        thresholds      = spec.thresholds or {},
    }
end

--- Report a team's current value for a registered consumer milestone.
function engine.report_external(force_name, category, count)
    if type(count) ~= "number" then return end
    engine.init_storage()
    local spec = storage.milestone_external[category]
    if not spec then return end
    -- Guard force_name before indexing game.forces with it: a non-string key
    -- (LuaForce/number/table) errors otherwise (AT-1). is_team_force is now
    -- type-safe, so this rejects bad input without crashing.
    if not force_utils.is_team_force(force_name) then return end
    local force = game.forces[force_name]
    if not (force and force.valid) then return end

    if spec.first_threshold and count >= spec.first_threshold then
        check_external(spec, force, spec.first_threshold, true)
    end
    for _, threshold in ipairs(spec.thresholds) do
        if count >= threshold then
            check_external(spec, force, threshold, false)
        end
    end
end

remote_api.register_milestone_impl = engine.register_external
remote_api.report_milestone_impl   = engine.report_external

return engine
