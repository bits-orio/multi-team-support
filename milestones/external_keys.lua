-- Multi-Team Support - milestones/external_keys.lua
-- Author: bits-orio
-- License: MIT
--
-- The keys of milestones a mod reports through mts-v1 (register_milestone,
-- report_milestone), and which of them are first-only. The engine writes
-- records under these keys and the agent tools read them back, so both take
-- the format from here and the two cannot drift apart.
--
-- A registered milestone's first_threshold is first-only: the engine
-- announces who got there first and never races the time. records.update
-- still stores a fastest for it, the same as for any record, so a reader
-- that counts fastest must ask first_only() which keys to leave out.

local M = {}

--- The per-team key in storage.milestone_reached: "ext:<category>".
function M.reached_key(category)
    return "ext:" .. category
end

--- The record key in storage.milestone_records: "ext:<category>@<threshold>".
function M.record_key(category, threshold)
    return M.reached_key(category) .. "@" .. threshold
end

--- Every first-only record key, as a set. Read from the registry, which
--- persists in storage, so a key stays first-only after its mod is removed.
function M.first_only()
    local set = {}
    for category, spec in pairs(storage.milestone_external or {}) do
        if type(spec) == "table" and spec.first_threshold ~= nil then
            set[M.record_key(category, spec.first_threshold)] = true
        end
    end
    return set
end

return M
