-- Multi-Team Support - shadow_race/score.lua
-- Author: bits-orio
-- License: MIT
--
-- A run's score: the science it has put into research. Each finished
-- research adds units x packs per unit; the research in progress adds the
-- same times its progress. Read from research events and one property, never
-- from production statistics.
--
-- Measured on 2.1.23 (docs/SHADOW_RACE_PLAN.md):
--   * a trigger technology has no ingredients, so it costs 0;
--   * in on_research_finished an infinite technology already reports the
--     NEXT level's unit count, so the cost of the level that finished is the
--     one noted while it was the current research.

local M = {}

local function packs_per_unit(ingredients)
    local packs = 0
    for _, ingredient in pairs(ingredients) do packs = packs + ingredient.amount end
    return packs
end

--- What the technology's current level costs, in science packs.
function M.cost(tech)
    return tech.research_unit_count * packs_per_unit(tech.research_unit_ingredients)
end

--- What a prototype's level `level` costs. Used to rebuild a run from the
--- research ticks of a save older than the recorder.
function M.prototype_cost(proto, level)
    local units = proto.research_unit_count
    local formula = proto.research_unit_count_formula
    if formula then
        local ok, value = pcall(helpers.evaluate_expression, formula, { L = level, l = level })
        if ok and type(value) == "number" then units = value end
    end
    return (units or 0) * packs_per_unit(proto.research_unit_ingredients)
end

--- Remember the research in progress and what it costs.
function M.note_current(run, tech)
    if tech and tech.valid then
        run.cur_name, run.cur_cost = tech.name, M.cost(tech)
    else
        run.cur_name, run.cur_cost = nil, nil
    end
end

--- The cost of a research that just finished. The noted cost when it was
--- the current research; otherwise read back from the prototype, one level
--- down for a technology that still has levels to go.
function M.finished_cost(run, tech)
    if run.cur_name == tech.name and run.cur_cost then return run.cur_cost end
    if tech.researched then return M.cost(tech) end
    return M.prototype_cost(tech.prototype, tech.level - 1)
end

--- The run's score right now: finished research plus the progress of the
--- current one. Never below what was already recorded, so a cancelled
--- research does not move a run backwards.
function M.live(run, force)
    local score = run.base
    local tech = force.current_research
    if tech then score = score + force.research_progress * M.cost(tech) end
    if score < run.score then return run.score end
    return score
end

return M
