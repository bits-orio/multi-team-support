-- scripts/admin_flags.lua
-- Admin flag storage, buddy-limit helpers, and starter-item management.
-- No GUI; imported by gui/admin.lua which re-exports everything.

local helpers = require("scripts.helpers")

local M = {}

-- Starter-item delivery hooks, injected by control.lua. admin_flags can't
-- require remote_api directly: that would close a load-time require cycle
-- (remote_api → team_clock → spectator → gui.admin → admin_flags), which
-- Factorio rejects. The defaults make the no-override path a no-op, so MTS
-- behaves normally until/unless a consumer registers an override.
local delivery = {
    override = function() return false end,
    raise    = function(_items) end,
}
function M.set_delivery_hooks(hooks)
    delivery = hooks
end

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
        key     = "allow_blueprint_imports",
        label   = "Allow Blueprint Imports",
        tooltip = "When enabled, players can import external blueprints via chat strings, the blueprint library, and the import-string button. When disabled, those imports are blocked (in-game blueprint creation -- alt-shift-click, copy-paste of placed entities -- still works either way).",
    },
    {
        key     = "staged_start_enabled",
        label   = "Staged Start (Speedrun)",
        tooltip = "When enabled, a new team's clock does not start until the leader clicks \"Start Playing\". The team is locked out of all game actions until then, but can browse the map. Designed for speedrun servers.",
    },
    {
        key     = "color_fix_enabled",
        label   = "Readable Player Colours",
        tooltip = "When enabled, players' colours are automatically kept readable and distinct: dark colours are brightened, brown shades are shifted to a vivid orange, and clashing colours are spread apart -- on join and whenever a player changes colour.",
    },
    {
        key     = "team_alerts_enabled",
        label   = "Team Pause Alerts",
        tooltip = "When enabled, a team's members see a persistent map alert while their team is paused (by an admin, or by a mod's scripted pause such as a docking cycle). The alert clears on resume. mts-v1 pause events fire regardless of this flag.",
    },
}

local FLAG_DEFAULTS = {
    landing_pen_enabled             = true,
    buddy_join_enabled              = true,
    friendship_enabled              = true,
    spectate_notifications_enabled  = false,
    popup_text_enabled              = true,
    allow_blueprint_imports         = false,  -- imports blocked by default
    staged_start_enabled            = false,  -- opt-in; intended for speedrun servers
    color_fix_enabled               = true,   -- auto-keep player colours readable + distinct
    team_alerts_enabled             = true,   -- persistent map alert while a team is paused
}

M.BUDDY_TEAM_LIMIT_MIN     = 2
M.BUDDY_TEAM_LIMIT_MAX     = 10
local BUDDY_TEAM_LIMIT_DEFAULT = 2

-- ─── Flag API ──────────────────────────────────────────────────────────

function M.get_flags()
    storage.admin_flags = storage.admin_flags or {}
    -- Migrate the old inverted flag: "disable_blueprint_imports" became
    -- "allow_blueprint_imports" (positive wording), so flip the stored value to
    -- preserve whatever the admin had set. Idempotent.
    local f = storage.admin_flags
    if f.disable_blueprint_imports ~= nil and f.allow_blueprint_imports == nil then
        f.allow_blueprint_imports = not f.disable_blueprint_imports
        f.disable_blueprint_imports = nil
    end
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

--- Fill the equipment grid of the armor `entry` was just inserted as. Finds
--- the first same-named stack with an empty grid (the fresh insert; a worn
--- armor the player already loaded keeps its equipment), then re-creates the
--- captured layout. Each put is pcall'd so one equipment name removed by a
--- mod change doesn't void the rest of the grid.
local function restore_grid_equipment(player, entry)
    for _, inv_type in pairs({
        defines.inventory.character_armor,
        defines.inventory.character_main,
    }) do
        local inv = player.get_inventory(inv_type)
        if inv then
            for i = 1, #inv do
                local stack = inv[i]
                if stack and stack.valid_for_read and stack.name == entry.name
                   and stack.grid and #stack.grid.equipment == 0 then
                    for _, eq in pairs(entry.grid) do
                        pcall(function()
                            local placed = stack.grid.put{
                                name     = eq.name,
                                position = eq.position,
                                quality  = eq.quality,
                            }
                            if placed and eq.energy then placed.energy = eq.energy end
                        end)
                    end
                    return
                end
            end
        end
    end
end

--- Insert one starter-item entry into a player, restoring armor equipment
--- when the entry carries a captured grid. The engine insert gets a clean
--- {name, count} table -- entry tables can carry extra fields (grid) that
--- ItemStackIdentification would reject.
function M.insert_starter_item(player, item)
    pcall(function()
        player.insert{name = item.name, count = item.count}
        if item.grid then restore_grid_equipment(player, item) end
    end)
end

--- Give specific items to all currently-spawned players. When a delivery
--- override is registered (e.g. Brave New MTS, whose teams have no player
--- character), hand the items to the consumer via on_starter_items_added
--- instead of inserting them into player inventories.
function M.distribute_items_to_spawned(items)
    if delivery.override() then
        -- Keep the mts-v1 event payload shape stable ({name, count} only):
        -- consumers insert these into chests, where a grid is meaningless.
        local clean = {}
        for i, item in ipairs(items) do
            clean[i] = {name = item.name, count = item.count}
        end
        delivery.raise(clean)
        return
    end
    storage.spawned_players = storage.spawned_players or {}
    for idx in pairs(storage.spawned_players) do
        local p = game.get_player(idx)
        if p and p.valid and p.connected and p.character then
            for _, item in pairs(items) do
                M.insert_starter_item(p, item)
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

--- Serialize an armor stack's equipment grid into a storage-safe table, or
--- nil when the stack has no grid / an empty one. Captures name, position,
--- quality, and stored energy per equipment so a granted copy comes out
--- loaded the same way (e.g. faster-start's pre-filled power armor).
local function serialize_grid(stack)
    local grid = stack.grid
    if not grid then return nil end
    local out = {}
    for _, eq in pairs(grid.equipment) do
        out[#out + 1] = {
            name     = eq.name,
            position = {x = eq.position.x, y = eq.position.y},
            quality  = eq.quality and eq.quality.name or nil,
            energy   = eq.energy > 0 and eq.energy or nil,
        }
    end
    if #out == 0 then return nil end
    return out
end

--- Collect all items from a player's character inventories. Entries are
--- {name, count} plus an optional `grid` (equipment layout) captured from
--- the first stack of that name that carries one.
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
                        if not seen[stack.name].grid then
                            seen[stack.name].grid = serialize_grid(stack)
                        end
                    else
                        local entry = {
                            name  = stack.name,
                            count = stack.count,
                            grid  = serialize_grid(stack),
                        }
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

--- Auto-populate starter items from the first spawning player's inventory. This
--- captures the map's default loadout into the admin list. Under a delivery
--- override (e.g. Brave New MTS) the same capture is what pre-populates the list
--- that then gets routed to team logistic chests instead of player inventories
--- (the spawning character is emptied separately, in on_player_created).
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
