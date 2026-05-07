-- events/research.lua
-- on_research_finished and research queue change events

local tech_records = require("scripts.tech_records")
local force_utils  = require("scripts.force_utils")
local research_gui = require("gui.research")
local teams_gui    = require("gui.teams")
local awards_gui   = require("gui.awards")

local M = {}

function M.register()
    script.on_event(defines.events.on_research_finished, function(event)
        local records_changed = tech_records.on_research_finished(event)
        force_utils.sync_quality_all_forces()
        research_gui.update_all()
        teams_gui.update_all()
        if records_changed then awards_gui.update_all() end
    end)

    local function on_queue_changed() teams_gui.update_all() end
    script.on_event(defines.events.on_research_queued,    on_queue_changed)
    script.on_event(defines.events.on_research_cancelled, on_queue_changed)
    script.on_event(defines.events.on_research_moved,     on_queue_changed)
    script.on_event(defines.events.on_research_started,   on_queue_changed)
end

return M
