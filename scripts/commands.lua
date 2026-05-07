-- scripts/commands.lua
-- Facade: delegates to sub-modules and calls each register() at startup.

local cmd_team  = require("scripts.commands.team")
local cmd_admin = require("scripts.commands.admin")
local cmd_debug = require("scripts.commands.debug_cmd")

local M = {}

function M.register()
    cmd_team.register()
    cmd_admin.register()
    cmd_debug.register()
end

return M
