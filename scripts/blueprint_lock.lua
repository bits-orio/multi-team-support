-- scripts/blueprint_lock.lua
-- Disable external blueprint imports (string paste, library, import-string
-- button) on the Default permission group while leaving in-game blueprint
-- creation (alt-shift-click, copy-paste of placed entities) untouched.
--
-- Mechanism: Factorio's permissions API. The input_action types covered
-- below fire ONLY when an external import is being confirmed:
--   - import_blueprint_string: the "Import string" popup confirm path
--     (toolbar button and the dialog that opens on chat paste).
--   - import_blueprint: confirm of a blueprint-record import (e.g. from
--     the library) into the cursor / inventory.
--   - import_blueprints_filtered: same as import_blueprint but for the
--     filtered variant used when a filter is set on the import.
--   - open_blueprint_library_gui: opens the personal/server blueprint
--     library.
-- Creating blueprints from world entities uses different actions and is
-- unaffected.
--
-- Toggleable at runtime via the admin flag "disable_blueprint_imports".

local admin_flags = require("scripts.admin_flags")

local M = {}

local BLOCKED_ACTIONS = {
    defines.input_action.import_blueprint_string,
    defines.input_action.import_blueprint,
    defines.input_action.import_blueprints_filtered,
    defines.input_action.open_blueprint_library_gui,
}

function M.apply()
    local default = game.permissions.get_group("Default")
    if not default then return end
    local block = admin_flags.flag("disable_blueprint_imports") and true or false
    for _, action in ipairs(BLOCKED_ACTIONS) do
        default.set_allows_action(action, not block)
    end
end

return M
