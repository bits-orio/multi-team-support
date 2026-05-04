-- Multi-Team Support - debug.lua
-- Author: bits-orio
-- License: MIT
--
-- Admin-only debug task engine. Runs a queue of scheduled one-shot
-- actions across future ticks. Powers the /mts-debug console command.
--
-- Tasks are persisted in storage.debug.tasks and survive save/load.
-- Action functions are dispatched by string key (storing function refs
-- in storage is forbidden in Factorio).

local M = {}

local function ensure_storage()
    storage.debug = storage.debug or { next_id = 1, tasks = {} }
end

function M.init_storage() ensure_storage() end

-- ─── Action Implementations ───────────────────────────────────────────
-- All actions take an `args` table. Errors are caught and logged so a
-- bad task can't break the tick loop.

local actions = {}

--- Research a technology recursively on a force.
--- args = { force = "team-N", tech = "automation" }
function actions.research_force(args)
    local force = game.forces[args.force]
    if not (force and force.valid) then return end
    local tech = force.technologies[args.tech]
    if not (tech and tech.valid) then return end
    tech:research_recursive()
end

-- ─── Public Scheduling API ────────────────────────────────────────────

--- Schedule research_recursive of `tech` on each force in `force_names`,
--- spaced `delay_ticks` apart. Returns the task id.
function M.schedule_research(force_names, tech, delay_ticks)
    ensure_storage()
    local base = game.tick + 1
    local actions_list = {}
    for i, fname in ipairs(force_names) do
        actions_list[#actions_list + 1] = {
            tick = base + (i - 1) * (delay_ticks or 0),
            fn   = "research_force",
            args = { force = fname, tech = tech },
        }
    end
    local id = storage.debug.next_id
    storage.debug.next_id = id + 1
    storage.debug.tasks[id] = {
        kind    = "research",
        label   = string.format("research %s × %d (delay %d)",
                                tech, #force_names, delay_ticks or 0),
        actions = actions_list,
    }
    return id
end

function M.stop(id)
    ensure_storage()
    if storage.debug.tasks[id] then
        storage.debug.tasks[id] = nil
        return true
    end
    return false
end

function M.stop_all()
    ensure_storage()
    local n = 0
    for _ in pairs(storage.debug.tasks) do n = n + 1 end
    storage.debug.tasks = {}
    return n
end

function M.list()
    ensure_storage()
    local rows = {}
    for id, task in pairs(storage.debug.tasks) do
        rows[#rows + 1] = {
            id     = id,
            kind   = task.kind,
            label  = task.label,
            detail = (#task.actions) .. " action(s) queued",
        }
    end
    table.sort(rows, function(a, b) return a.id < b.id end)
    return rows
end

-- ─── Tick Driver ──────────────────────────────────────────────────────
-- Registered unconditionally in control.lua. Cheap early-return when
-- the queue is empty.

function M.tick()
    if not (storage.debug and next(storage.debug.tasks)) then return end
    local now = game.tick
    for id, task in pairs(storage.debug.tasks) do
        local i = 1
        while i <= #task.actions do
            local a = task.actions[i]
            if a.tick <= now then
                local ok, err = pcall(actions[a.fn], a.args)
                if not ok then log("[mts-debug] " .. tostring(err)) end
                table.remove(task.actions, i)
            else
                i = i + 1
            end
        end
        if #task.actions == 0 then storage.debug.tasks[id] = nil end
    end
end

return M
