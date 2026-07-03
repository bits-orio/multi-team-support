-- Multi-Team Support - scripts/buddy_store.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Low-level store for pending buddy requests. Deliberately dependency-free (no
-- require of force_utils/team_slots/pen_gui) so both the buddy-request GUI and
-- team_slots can call it without a circular require — force_utils requires
-- team_slots, so anything team_slots pulls in must not lead back to force_utils.
--
-- A request is keyed by the REQUESTER's player index and its value is the
-- TEAM's force name (not a leader player index) — that is what lets ANY online
-- member of the team accept it. The Accept/Reject dialog is a per-requester
-- screen frame (sb_buddy_req_<requester_index>) shown to every online member,
-- so several pending requests coexist and are torn down individually.
--
-- Storage:
--   storage.buddy_requests[requester_index] = force_name  -- pending request

local buddy_store = {}

local FRAME_PREFIX = "sb_buddy_req_"

--- Screen-frame name for one requester's Accept/Reject dialog.
function buddy_store.frame_name(requester_index)
    return FRAME_PREFIX .. requester_index
end

--- The team a pen player is currently requesting to join, or nil.
function buddy_store.request_of(requester_index)
    return (storage.buddy_requests or {})[requester_index]
end

--- Record a pending request (requester -> team force name).
function buddy_store.set(requester_index, force_name)
    storage.buddy_requests = storage.buddy_requests or {}
    storage.buddy_requests[requester_index] = force_name
end

--- Destroy one requester's Accept/Reject frame on every connected player's
--- screen (members hold these frames; the requester never does).
function buddy_store.destroy_frames(requester_index)
    local fname = buddy_store.frame_name(requester_index)
    for _, p in pairs(game.connected_players) do
        local f = p.gui.screen[fname]
        if f then f.destroy() end
    end
end

--- Drop one request and tear down its frames.
function buddy_store.clear(requester_index)
    if storage.buddy_requests then storage.buddy_requests[requester_index] = nil end
    buddy_store.destroy_frames(requester_index)
end

--- Cancel every request addressed to a team (its slot is being released, so the
--- requests can no longer be accepted there). Returns the affected requester
--- indices so the caller can notify them / refresh their pen GUI.
function buddy_store.clear_for_team(force_name)
    local affected = {}
    if not storage.buddy_requests then return affected end
    for req_idx, fn in pairs(storage.buddy_requests) do
        if fn == force_name then
            affected[#affected + 1] = req_idx
            storage.buddy_requests[req_idx] = nil
            buddy_store.destroy_frames(req_idx)
        end
    end
    return affected
end

--- Destroy every buddy-request frame on one player's screen, whichever
--- requester they belong to (used when a member returns to the pen / is
--- removed, so they stop holding accept dialogs for their old team).
function buddy_store.destroy_all_frames_for(player)
    if not (player and player.valid) then return end
    for _, child in pairs(player.gui.screen.children) do
        if child.name and child.name:find("^" .. FRAME_PREFIX) then child.destroy() end
    end
end

--- The team a player really belongs to, seeing through a temporary spectator
--- force (a member remote-viewing another surface is on the "spectator" force
--- but still a member of their team). Mirrors spectator.get_effective_force as a
--- pure storage read so this module stays dependency-free.
function buddy_store.team_of(player)
    return (storage.spectator_real_force or {})[player.index] or player.force.name
end

--- Count online members of a team, INCLUDING any who are currently spectating
--- (force.connected_players would miss them). Used to decide whether a team is
--- joinable and to deliver Accept dialogs.
function buddy_store.online_member_count(force_name)
    local n = 0
    for _, p in pairs(game.connected_players) do
        if buddy_store.team_of(p) == force_name then n = n + 1 end
    end
    return n
end

--- Drop every pending request and tear down all buddy frames. Called from
--- on_configuration_changed so a save upgraded mid-request can't strand a
--- requester on a stale entry (the old model stored a leader player index as the
--- value; the new model stores a force name). Pending requests are ephemeral, so
--- clearing them on a mod update is safe.
function buddy_store.reset()
    for _, p in pairs(game.connected_players) do
        buddy_store.destroy_all_frames_for(p)
    end
    storage.buddy_requests = {}
end

return buddy_store
