-- Multi-Team Support - scripts/team_modifiers.lua
-- Author: bits-orio
-- License: GPL-3.0-or-later
--
-- Per-team gameplay modifiers ("team modifiers"), gated behind the
-- non_competitive_enabled admin flag. MTS is competitive by default — every
-- team plays under identical rules — so modifiers are an explicit, loudly
-- announced exception for private servers with mixed-skill groups: every
-- change is broadcast, the mode is shown in the HUD and Teams GUI, and
-- record announcements are tagged while the mode is on.
--
-- Modifiers are implemented per-surface (each team owns its surfaces), which
-- is why they can differ per team at all. v1 ships peaceful biters only; the
-- storage shape and MODIFIERS list are built for more keys later.
--
-- A team that EVER had a modifier enabled is permanently marked
-- non-competitive (storage.team_noncompetitive) — removing the modifier
-- doesn't clear the mark; only disbanding the team does. Leaving
-- non-competitive mode is blocked while any marked team exists, so a
-- bad-faith admin can't briefly handicap a team and flip the server back
-- to competitive as if nothing happened.
--
-- Storage shape:
--   storage.team_modifiers[force_name]      = { peaceful = true }  -- absent keys = standard
--   storage.team_noncompetitive[force_name] = true                 -- cleared only on release
--
-- Cycle-safety: requires only leaf modules (helpers, admin_flags,
-- surface_utils), so GUI modules, records, and milestones can all require it.

local helpers       = require("scripts.helpers")
local admin_flags   = require("scripts.admin_flags")
local surface_utils = require("scripts.surface_utils")

local M = {}

-- Shown wherever the mode is surfaced (HUD tag, card lines, admin section).
M.MODE_COLOR = {1, 0.65, 0}

M.MODIFIERS = {
    {
        key     = "peaceful",
        label   = "Peaceful biters",
        short   = "peaceful",
        icon    = "[img=entity/small-biter]",
        tooltip = "Biters on this team's surfaces never attack first"
            .. " (they still defend themselves).",
    },
}

function M.is_active()
    return admin_flags.flag("non_competitive_enabled") == true
end

local function entry(force_name)
    return (storage.team_modifiers or {})[force_name]
end

function M.has(force_name, key)
    local e = entry(force_name)
    return (e and e[key]) == true
end

function M.any(force_name)
    local e = entry(force_name)
    return e ~= nil and next(e) ~= nil
end

--- True once a team has ever had a modifier enabled. Cleared only on release.
function M.is_marked(force_name)
    return (storage.team_noncompetitive or {})[force_name] == true
end

-- ─── Surface application ───────────────────────────────────────────────

--- Re-apply this team's modifier state to every surface it owns.
local function apply_team(force_name)
    local peaceful = M.has(force_name, "peaceful")
    for _, surface in ipairs(surface_utils.owned_surfaces_by_force(force_name)) do
        surface.peaceful_mode = peaceful
    end
end

--- Apply the owner team's modifiers to a freshly created surface (new planet
--- variant, platform, ...). Called from the on_surface_created path.
function M.apply_to_surface(surface, owner_force_name)
    if not (surface and surface.valid and owner_force_name) then return end
    if M.has(owner_force_name, "peaceful") then
        surface.peaceful_mode = true
    end
end

-- ─── Mutation ──────────────────────────────────────────────────────────

local function guidance()
    return "See the Teams panel or /mts-modifiers for every team's settings."
end

--- Set one modifier for one team. Admin GUI entry point. No-op (returns
--- false) when the mode is off, the force isn't a team, or nothing changes;
--- otherwise applies to the team's surfaces and broadcasts the change.
function M.set(force_name, key, enabled, admin_player)
    if not M.is_active() then return false end
    if not helpers.is_team_force(force_name) then return false end
    local def
    for _, d in ipairs(M.MODIFIERS) do
        if d.key == key then def = d; break end
    end
    if not def then return false end
    if M.has(force_name, key) == (enabled == true) then return false end

    storage.team_modifiers = storage.team_modifiers or {}
    local e = storage.team_modifiers[force_name] or {}
    e[key] = (enabled == true) or nil
    storage.team_modifiers[force_name] = next(e) and e or nil

    -- Enabling any modifier permanently marks the team non-competitive
    -- (removing the modifier later does NOT clear the mark; disband does).
    local newly_marked = enabled and not M.is_marked(force_name)
    if enabled then
        storage.team_noncompetitive = storage.team_noncompetitive or {}
        storage.team_noncompetitive[force_name] = true
    end

    apply_team(force_name)

    local who = admin_player
        and helpers.colored_name(admin_player.name, admin_player.chat_color)
        or "Admin"
    local msg = "[Admin] " .. who
        .. (enabled and " enabled " or " disabled ") .. def.label
        .. " for " .. helpers.team_tag_with_leader(force_name)
        .. " (non-competitive mode)."
    if newly_marked then
        msg = msg .. " This team is now marked non-competitive until it disbands."
    end
    helpers.broadcast(msg .. " " .. guidance())
    return true
end

--- Blocks disabling non-competitive mode while any MARKED team exists:
--- returns a reason string naming those teams, or nil when disabling is
--- fine (the mode was enabled by accident and no team ever got a
--- modifier). Marked teams block even with their modifiers since removed —
--- the only way back to competitive is disbanding them.
function M.disable_blocked_reason()
    local marked = storage.team_noncompetitive
    if not (marked and next(marked)) then return nil end
    local names = {}
    for force_name in pairs(marked) do
        names[#names + 1] = force_name
    end
    table.sort(names)
    local parts = {}
    for _, force_name in ipairs(names) do
        parts[#parts + 1] = helpers.team_tag_with_leader(force_name)
    end
    local plural = #parts > 1
    return "Cannot return to competitive mode: " .. table.concat(parts, ", ")
        .. (plural and " have" or " has")
        .. " played with team modifiers and " .. (plural and "are" or "is")
        .. " marked non-competitive. The mark clears only when the team disbands."
end

--- Remove every team's modifiers and restore standard settings. Called when
--- the admin turns non-competitive mode off — normally a no-op, since the
--- disable is blocked while any modifier is active (disable_blocked_reason);
--- kept as a belt-and-braces cleanup should the two ever disagree.
function M.revert_all()
    if not storage.team_modifiers or not next(storage.team_modifiers) then
        storage.team_modifiers = nil
        return
    end
    local names = {}
    for force_name in pairs(storage.team_modifiers) do
        names[#names + 1] = force_name
    end
    storage.team_modifiers = nil
    storage.team_noncompetitive = nil
    for _, force_name in ipairs(names) do
        apply_team(force_name)   -- entry gone -> reverts to standard
    end
    helpers.broadcast(
        "All team modifiers removed — every team is back on standard settings.")
end

--- Drop a released slot's modifiers, non-competitive mark, and surface
--- state, so a future team reusing the slot never inherits an old handicap.
--- Disbanding is the ONE path that clears the mark.
function M.on_release(force_name)
    if storage.team_noncompetitive then
        storage.team_noncompetitive[force_name] = nil
    end
    if not entry(force_name) then return end
    storage.team_modifiers[force_name] = nil
    apply_team(force_name)
end

-- ─── Display helpers ───────────────────────────────────────────────────

--- One-line description of a team's modifiers ("Peaceful biters", comma-
--- separated when more exist), or nil when the team is standard.
function M.describe(force_name)
    local e = entry(force_name)
    if not (e and next(e)) then return nil end
    local parts = {}
    for _, def in ipairs(M.MODIFIERS) do
        if e[def.key] then parts[#parts + 1] = def.label end
    end
    return table.concat(parts, ", ")
end

--- HUD tag under the top-bar clock: "non-competitive", with the team's own
--- modifiers appended ("non-competitive · peaceful") so an asymmetry is
--- visible at a glance. nil when the mode is off.
function M.hud_tag(force_name)
    if not M.is_active() then return nil end
    local caption = "non-competitive"
    local shorts  = {}
    for _, def in ipairs(M.MODIFIERS) do
        if M.has(force_name, def.key) then shorts[#shorts + 1] = def.short end
    end
    if #shorts > 0 then
        caption = caption .. " · " .. table.concat(shorts, " · ")
    end
    local mine = M.describe(force_name) or "standard settings"
    return caption,
        "This server allows per-team modifiers.\nThis team: " .. mine
            .. "\n" .. guidance()
end

--- Modifier line for a Teams GUI card, or nil when the team is standard
--- (or the mode is off).
function M.card_line(force_name)
    if not M.is_active() then return nil end
    local e = entry(force_name)
    if not (e and next(e)) then return nil end
    local caps, tips = {}, {}
    for _, def in ipairs(M.MODIFIERS) do
        if e[def.key] then
            caps[#caps + 1] = def.icon .. " " .. def.label
            tips[#tips + 1] = def.tooltip
        end
    end
    return table.concat(caps, "   "),
        table.concat(tips, "\n") .. "\n(non-competitive team modifier)"
end

--- Orange badge shown next to a marked team's name (admin GUI,
--- /mts-modifiers), or nil for unmarked teams.
function M.marked_badge(force_name)
    if not M.is_marked(force_name) then return nil end
    return "[color=1,0.65,0][non-competitive][/color]"
end

--- Prefix for record/milestone broadcasts: tagged while the mode is on, so
--- awards earned under uneven rules carry a visible asterisk.
function M.records_tag()
    return M.is_active() and "[Records | non-competitive]" or "[Records]"
end

--- Chat notice for players joining a non-competitive server.
function M.print_mode_notice(player)
    if not M.is_active() then return end
    player.print("[color=1,0.65,0]This server is running in NON-COMPETITIVE"
        .. " mode — teams may play under different settings. " .. guidance()
        .. "[/color]")
end

return M
