-- Multi-Team Support - friendship.lua
-- Author: bits-orio
-- License: MIT
--
-- Friend toggle logic extracted from surfaces_gui.lua.
-- Mutual friendship semantics: both sides must agree before it
-- activates; either side can break it immediately.

local spectator     = require("spectator")
local helpers       = require("helpers")
local surface_utils = require("surface_utils")

local friendship = {}

-- ─── State Query ──────────────────────────────────────────────────────

--- Determine friendship checkbox state between viewer and target.
--- Returns: label_text, label_color, tooltip, checked
-- Friendship checkbox states:
-- State                     | Label            | Color  | Checked | Tooltip
-- No intents                | "request friend" | blue   | no      | "Send friend request to X"
-- I requested, they haven't | "request pending"| yellow | yes     | "Withdraw friend request to X"
-- They requested, I haven't | "request pending"| yellow | no      | "Accept friend request from X"
-- Mutual active             | "friends"        | green  | yes     | "Break friendship with X"
function friendship.get_state(viewer_force_name, target_force_name, viewer_force, target_force, owner)
    local intents      = storage.friend_intents or {}
    local my_intent    = intents[viewer_force_name]
        and intents[viewer_force_name][target_force_name] or false
    local their_intent = intents[target_force_name]
        and intents[target_force_name][viewer_force_name] or false
    local is_mutual    = viewer_force.get_friend(target_force)

    if is_mutual then
        return "friends", {0, 1, 0}, "Break friendship with " .. owner, true
    elseif my_intent then
        return "request pending", {1, 0.8, 0}, "Withdraw friend request to " .. owner, true
    elseif their_intent then
        return "request pending", {1, 0.8, 0}, "Accept friend request from " .. owner, false
    else
        return "request friend", {0.4, 0.7, 1}, "Send friend request to " .. owner, false
    end
end

-- ─── Internal Helpers ─────────────────────────────────────────────────

--- Activate mutual friendship between two forces.
local function activate(viewer_force, target_force)
    viewer_force.set_friend(target_force, true)
    target_force.set_friend(viewer_force, true)
    spectator.on_friend_changed(viewer_force, target_force, true)
    spectator.on_friend_changed(target_force, viewer_force, true)
    surface_utils.update_visibility(viewer_force, target_force, true)
end

--- Break mutual friendship between two forces.
local function break_mutual(viewer_force_name, target_force_name, viewer_force, target_force)
    storage.friend_intents[target_force_name] = storage.friend_intents[target_force_name] or {}
    storage.friend_intents[target_force_name][viewer_force_name] = nil

    viewer_force.set_friend(target_force, false)
    target_force.set_friend(viewer_force, false)
    spectator.on_friend_changed(viewer_force, target_force, false)
    spectator.on_friend_changed(target_force, viewer_force, false)
    surface_utils.update_visibility(viewer_force, target_force, false)
end

-- ─── Toggle Handler ───────────────────────────────────────────────────

--- Handle friend checkbox toggle.
--- Broadcasts the result message. Returns true if GUIs need refresh.
function friendship.on_toggle(event)
    local element = event.element
    if not element or not element.valid then return end
    if not (element.tags and element.tags.sb_friend_toggle) then return end

    local player = game.get_player(event.player_index)
    if not player then return end

    local target_force = game.forces[element.tags.sb_target_force]
    if not target_force then return end

    local viewer_force_name = spectator.get_effective_force(player)
    local viewer_force      = game.forces[viewer_force_name]
    if not viewer_force then return end

    local target_force_name = target_force.name
    local target_name       = helpers.display_name(target_force_name)
    local viewer_tag        = helpers.colored_name(player.name, player.chat_color)
    local target_tag        = helpers.colored_name(target_name, helpers.force_color(target_force))

    storage.friend_intents = storage.friend_intents or {}
    storage.friend_intents[viewer_force_name] = storage.friend_intents[viewer_force_name] or {}

    local msg

    if element.state then
        -- Record this side's intent
        storage.friend_intents[viewer_force_name][target_force_name] = true

        local reverse = storage.friend_intents[target_force_name]
            and storage.friend_intents[target_force_name][viewer_force_name]

        if reverse then
            activate(viewer_force, target_force)
            msg = viewer_tag .. " and " .. target_tag
                .. " are now [color=0,1,0]friends[/color]"
        else
            msg = viewer_tag .. " wants to friend " .. target_tag
                .. " [color=1,0.8,0](pending)[/color]"
        end
    else
        -- Remove this side's intent
        storage.friend_intents[viewer_force_name][target_force_name] = nil

        if viewer_force.get_friend(target_force) then
            break_mutual(viewer_force_name, target_force_name, viewer_force, target_force)
            msg = viewer_tag .. " and " .. target_tag .. " are no longer friends"
        else
            msg = viewer_tag .. " withdrew friend request to " .. target_tag
        end
    end

    helpers.broadcast(msg)
    return true
end

--- Break all existing friendships and clear all intents.
--- Called when the friendship admin flag is disabled mid-session.
function friendship.break_all()
    storage.friend_intents = storage.friend_intents or {}
    local broken = {}
    for _, force_a in pairs(game.forces) do
        if force_a.name:find("^player%-") then
            for _, force_b in pairs(game.forces) do
                if force_b.name:find("^player%-") and force_a.index < force_b.index then
                    if force_a.get_friend(force_b) or force_b.get_friend(force_a) then
                        force_a.set_friend(force_b, false)
                        force_b.set_friend(force_a, false)
                        spectator.on_friend_changed(force_a, force_b, false)
                        spectator.on_friend_changed(force_b, force_a, false)
                        surface_utils.update_visibility(force_a, force_b, false)
                        broken[#broken + 1] = helpers.display_name(force_a.name)
                            .. " & " .. helpers.display_name(force_b.name)
                    end
                end
            end
        end
    end
    storage.friend_intents = {}
    if #broken > 0 then
        helpers.broadcast("[Admin] All friendships have been dissolved.")
    end
end

return friendship
