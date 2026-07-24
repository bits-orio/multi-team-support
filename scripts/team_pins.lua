-- scripts/team_pins.lua
-- Auto map-pins between teammates (2.1 LuaPlayer::add_pin) plus the manual
-- Pin/Unpin button on the teams GUI (gui/team_card.lua).
--
-- Design (docs/FACTORIO_21_PLAN.md Phase 6):
--   * on every TEAM JOIN, the joiner and each current member get mutual pins.
--     Offline members included -- a pin can be created for a disconnected
--     player and is simply there when they return; that is creation, not
--     resurrection.
--   * a natively DISMISSED pin is never re-created automatically -- the GUI
--     button is the manual re-pin path;
--   * on team leave, every pin between the leaver and that team dies, both
--     directions;
--   * spectate hops are excluded at the dispatch site (remote_api's
--     on_player_changed_force adapter, after its is_spectator_hop return) so
--     pins never churn on a spectate round-trip;
--   * stateless: pin state is always read live from get_pins() (matched by
--     pin.player), never stored -- native dismissal is respected for free.
--   * pin create/dismiss is deliberately NOT bridged to Discord.
-- Gated by the team_pins_enabled admin flag (auto-pins and buttons alike).

local admin_flags = require("scripts.admin_flags")

local M = {}

-- First valid pin owned by `owner` that targets `target`. A pin whose target
-- player was removed from the game reads player=nil and is simply skipped --
-- it dies with the engine's own bookkeeping, not ours.
local function find_pin(owner, target)
    local ok, pins = pcall(function() return owner.get_pins() end)
    if not (ok and pins) then return nil end
    for _, pin in pairs(pins) do
        if pin.valid then
            local pok, tp = pcall(function() return pin.player end)
            if pok and tp and tp == target then return pin end
        end
    end
    return nil
end

function M.is_pinned(owner, target)
    return find_pin(owner, target) ~= nil
end

function M.pin(owner, target)
    if find_pin(owner, target) then return end
    pcall(function() owner.add_pin{ player = target, label = target.name } end)
end

function M.unpin(owner, target)
    local pin = find_pin(owner, target)
    if pin then pcall(function() pin.destroy() end) end
end

function M.toggle(owner, target)
    if not (owner and owner.valid and target and target.valid) then return end
    if find_pin(owner, target) then M.unpin(owner, target) else M.pin(owner, target) end
end

--- Team-join funnel: mutual pins between the joiner and every current member.
function M.on_team_joined(player)
    if not admin_flags.flag("team_pins_enabled") then return end
    if not (player and player.valid) then return end
    for _, mate in pairs(player.force.players) do
        if mate.valid and mate.index ~= player.index then
            M.pin(player, mate)
            M.pin(mate, player)
        end
    end
end

--- Team-leave funnel: remove every pin between the leaver and the team they
--- left. Runs regardless of the flag -- existing pins are cleaned up even if
--- an admin disabled the feature mid-game.
function M.on_team_left(player, old_force_name)
    if not (player and player.valid) then return end
    local force = game.forces[old_force_name]
    if not (force and force.valid) then return end
    for _, mate in pairs(force.players) do
        if mate.valid and mate.index ~= player.index then
            M.unpin(player, mate)
            M.unpin(mate, player)
        end
    end
end

return M
