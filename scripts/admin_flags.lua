-- scripts/admin_flags.lua
-- Admin flag storage, buddy-limit helpers, and starter-item management.
-- No GUI; imported by gui/admin.lua which re-exports everything.

local helpers = require("scripts.helpers")

local M = {}

-- ─── Flag Definitions ──────────────────────────────────────────────────

M.FLAGS = {
    {
        key     = "landing_pen_enabled",
        label   = "Landing Pen",
        tooltip = "When enabled, new players wait in the Landing Pen before spawning into the game.",
    },
    {
        key     = "buddy_join_enabled",
        label   = "Multi-player teams",
        tooltip = "When enabled, players in the Landing Pen can request to join an existing team.",
    },
    {
        key     = "friendship_enabled",
        label   = "Allow Friendship",
        tooltip = "When enabled, players can send friend requests. Disabling breaks all existing friendships.",
    },
    {
        key     = "spectate_notifications_enabled",
        label   = "Spectate Notifications",
        tooltip = "When enabled, all players are notified when someone starts or stops spectating.",
    },
    {
        key     = "popup_text_enabled",
        label   = "Text Popups",
        tooltip = "When enabled, animated text popups appear on spawn, team join, milestones, and player death.",
    },
    {
        key     = "disable_blueprint_imports",
        label   = "Disable Blueprint Imports",
        tooltip = "When enabled, blocks importing external blueprints via chat strings, the blueprint library, and the import-string button. In-game blueprint creation (alt-shift-click, copy-paste of placed entities) still works.",
    },
}

local FLAG_DEFAULTS = {
    landing_pen_enabled             = true,
    buddy_join_enabled              = true,
    friendship_enabled              = true,
    spectate_notifications_enabled  = false,
    popup_text_enabled              = true,
    disable_blueprint_imports       = true,
}

M.BUDDY_TEAM_LIMIT_MIN     = 2
M.BUDDY_TEAM_LIMIT_MAX     = 10
local BUDDY_TEAM_LIMIT_DEFAULT = 2

-- ─── Flag API ──────────────────────────────────────────────────────────

function M.get_flags()
    storage.admin_flags = storage.admin_flags or {}
    for k, v in pairs(FLAG_DEFAULTS) do
        if storage.admin_flags[k] == nil then storage.admin_flags[k] = v end
    end
    return storage.admin_flags
end

function M.flag(key)
    return M.get_flags()[key]
end

function M.buddy_team_limit()
    local flags = M.get_flags()
    local val = flags.buddy_team_limit
    if type(val) ~= "number" or val < M.BUDDY_TEAM_LIMIT_MIN or val > M.BUDDY_TEAM_LIMIT_MAX then
        flags.buddy_team_limit = BUDDY_TEAM_LIMIT_DEFAULT
        return BUDDY_TEAM_LIMIT_DEFAULT
    end
    return val
end

function M.get_flag_label(key)
    for _, def in ipairs(M.FLAGS) do
        if def.key == key then return def.label end
    end
    return key
end

function M.get_starter_items()
    return storage.starter_items
end

-- ─── Starter Item Helpers ──────────────────────────────────────────────

--- Give specific items to all currently-spawned players.
function M.distribute_items_to_spawned(items)
    storage.spawned_players = storage.spawned_players or {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p and p.valid and p.connected and p.character then
            for _, item in pairs(items) do
                pcall(function() p.insert(item) end)
            end
        end
    end
end

--- Broadcast that an admin added entries to the starter items list.
function M.announce_starter_items_added(items, admin_player)
    if not items or #items == 0 then return end
    local parts = {}
    for _, item in ipairs(items) do
        parts[#parts + 1] = item.count .. "x " .. helpers.item_rich_name(item.name)
    end
    local who = admin_player
        and helpers.colored_name(admin_player.name, admin_player.chat_color)
        or "Admin"
    helpers.broadcast(who .. " added " .. table.concat(parts, ", ") .. " to the starter items list.")
end

--- Collect all items from a player's character inventories.
function M.collect_character_items(player)
    local items, seen = {}, {}
    if not player.character then return items end
    for _, inv_type in pairs({
        defines.inventory.character_main,
        defines.inventory.character_guns,
        defines.inventory.character_ammo,
        defines.inventory.character_armor,
    }) do
        local inv = player.get_inventory(inv_type)
        if inv then
            for i = 1, #inv do
                local stack = inv[i]
                if stack and stack.valid_for_read then
                    if seen[stack.name] then
                        seen[stack.name].count = seen[stack.name].count + stack.count
                    else
                        local entry = {name = stack.name, count = stack.count}
                        seen[stack.name] = entry
                        items[#items + 1] = entry
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end

--- Auto-populate starter items from the first spawning player's inventory.
function M.auto_populate_starter_items(player)
    if storage.starter_items then return end
    if not player.character then return end
    storage.starter_items = M.collect_character_items(player)
    if #storage.starter_items > 0 then
        log("[multi-team-support] auto-populated starter items from " .. player.name
            .. " (" .. #storage.starter_items .. " item types)")
    end
end

return M
