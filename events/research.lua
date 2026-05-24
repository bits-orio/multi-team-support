-- events/research.lua
-- on_research_finished and research queue change events

local tech_records = require("scripts.tech_records")
local force_utils  = require("scripts.force_utils")
local research_gui = require("gui.research")
local teams_gui    = require("gui.teams")
local awards_gui   = require("gui.awards")
local remote_api   = require("scripts.remote_api")

local M = {}

function M.register()
    script.on_event(defines.events.on_research_finished, function(event)
        local records_changed = tech_records.on_research_finished(event)
        force_utils.sync_quality_all_forces()
        research_gui.update_all()
        teams_gui.update_all()
        if records_changed then awards_gui.update_all() end

        -- Announce team research to the Open Discord Bridge (team-aware, replaces the
        -- bridge's team-less baseline research event, which we disable on init).
        local research = event.research
        if research and research.valid and research.force.name:find("^team%-") then
            local team = (storage.team_names or {})[research.force.name] or research.force.name
            remote_api.emit_to_bridge("mts.research_finished", {
                team  = team,
                tech  = research.name,
                level = research.level,
                -- The "[mts → 🔬]" tag emoji comes from BRIDGE_LABELS in remote_api.lua.
                -- Code-pill the tech name (Discord inline-code). Renders in plain mode
                -- (embed:false); inside the embed:true ANSI block the backticks show literally.
                text  = string.format("%s researched `%s`", team, research.name),
            })
        end
    end)

    local function on_queue_changed() teams_gui.update_all() end
    script.on_event(defines.events.on_research_queued,    on_queue_changed)
    script.on_event(defines.events.on_research_cancelled, on_queue_changed)
    script.on_event(defines.events.on_research_moved,     on_queue_changed)
    script.on_event(defines.events.on_research_started,   on_queue_changed)
end

return M
