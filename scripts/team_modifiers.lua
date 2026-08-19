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

-- Each def carries plain label/short/tooltip strings AND ls_* LocalisedString
-- twins (locale/en/modifiers.cfg): unconverted GUI slices still render the
-- plain fields; converted ones use ls_*. The final locale sweep folds the
-- plain fields away. icon is language-neutral rich text — no twin needed.
M.MODIFIERS = {
    {
        key     = "peaceful",
        label   = "Peaceful biters",
        short   = "peaceful",
        icon    = "[img=entity/small-biter]",
        tooltip = "Biters on this team's surfaces never attack first"
            .. " (they still defend themselves).",
        ls_label   = {"mts-gui.modifier-peaceful"},
        ls_short   = {"mts-gui.modifier-peaceful-short"},
        ls_tooltip = {"mts-tip.modifier-peaceful"},
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

--- LocalisedString twin of guidance() (dual API: the plain version stays
--- until the last consumer of the string display helpers migrates).
local function ls_guidance()
    return {"mts-chat.modifiers-guidance"}
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
        or {"mts-chat.admin-actor"}
    local tag = helpers.team_tag_with_leader(force_name)
    local msg = {"", enabled
        and {"mts-chat.modifier-enabled", who, def.ls_label, tag}
        or {"mts-chat.modifier-disabled", who, def.ls_label, tag}}
    if newly_marked then
        msg[#msg + 1] = " "
        msg[#msg + 1] = {"mts-chat.modifier-marked"}
    end
    msg[#msg + 1] = " "
    msg[#msg + 1] = ls_guidance()
    helpers.broadcast(msg)
    return true
end

--- Sorted team tags (with leader) of every marked team, or nil when none.
local function marked_team_tags()
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
    return parts
end

--- Blocks disabling non-competitive mode while any MARKED team exists:
--- returns a reason string naming those teams, or nil when disabling is
--- fine (the mode was enabled by accident and no team ever got a
--- modifier). Marked teams block even with their modifiers since removed —
--- the only way back to competitive is disbanding them.
function M.disable_blocked_reason()
    local parts = marked_team_tags()
    if not parts then return nil end
    local plural = #parts > 1
    return "Cannot return to competitive mode: " .. table.concat(parts, ", ")
        .. (plural and " have" or " has")
        .. " played with team modifiers and " .. (plural and "are" or "is")
        .. " marked non-competitive. The mark clears only when the team disbands."
end

--- LocalisedString twin of disable_blocked_reason (dual API; the has/have
--- and is/are branches live in the locale value, keyed on the team count).
function M.ls_disable_blocked_reason()
    local parts = marked_team_tags()
    if not parts then return nil end
    return {"mts-chat.cannot-return-competitive", table.concat(parts, ", "), #parts}
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
    helpers.broadcast({"mts-chat.modifiers-reverted"})
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
-- Each string helper below has an ls_ LocalisedString twin (dual API):
-- consumers outside this module still take the plain string and migrate
-- slice by slice; the final locale sweep folds the plain versions away.

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

--- LocalisedString twin of describe.
function M.ls_describe(force_name)
    local e = entry(force_name)
    if not (e and next(e)) then return nil end
    local out = {""}
    for _, def in ipairs(M.MODIFIERS) do
        if e[def.key] then
            if #out > 1 then out[#out + 1] = ", " end
            out[#out + 1] = def.ls_label
        end
    end
    return out
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

--- LocalisedString twin of hud_tag: caption, tooltip — or nil when the
--- mode is off.
function M.ls_hud_tag(force_name)
    if not M.is_active() then return nil end
    local caption = {"", {"mts-gui.hud-noncompetitive"}}
    for _, def in ipairs(M.MODIFIERS) do
        if M.has(force_name, def.key) then
            caption[#caption + 1] = " · "
            caption[#caption + 1] = def.ls_short
        end
    end
    local mine = M.ls_describe(force_name) or {"mts-gui.standard-settings"}
    return caption, {"mts-tip.hud-modifiers", mine, ls_guidance()}
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

--- LocalisedString twin of card_line: caption, tooltip — or nil when the
--- team is standard (or the mode is off).
function M.ls_card_line(force_name)
    if not M.is_active() then return nil end
    local e = entry(force_name)
    if not (e and next(e)) then return nil end
    local caps, tips = {""}, {""}
    for _, def in ipairs(M.MODIFIERS) do
        if e[def.key] then
            if #caps > 1 then caps[#caps + 1] = "   " end
            caps[#caps + 1] = def.icon
            caps[#caps + 1] = " "
            caps[#caps + 1] = def.ls_label
            tips[#tips + 1] = def.ls_tooltip
            tips[#tips + 1] = "\n"
        end
    end
    tips[#tips + 1] = {"mts-tip.card-modifier-suffix"}
    return caps, tips
end

--- Orange badge shown next to a marked team's name (admin GUI,
--- /mts-modifiers), or nil for unmarked teams.
function M.marked_badge(force_name)
    if not M.is_marked(force_name) then return nil end
    return "[color=1,0.65,0][non-competitive][/color]"
end

--- LocalisedString twin of marked_badge.
function M.ls_marked_badge(force_name)
    if not M.is_marked(force_name) then return nil end
    return {"mts-gui.marked-badge"}
end

--- Prefix for record/milestone broadcasts: tagged while the mode is on, so
--- awards earned under uneven rules carry a visible asterisk.
function M.records_tag()
    return M.is_active() and "[Records | non-competitive]" or "[Records]"
end

--- LocalisedString twin of records_tag.
function M.ls_records_tag()
    return M.is_active() and {"mts-chat.records-tag-noncompetitive"}
        or {"mts-chat.records-tag"}
end

--- Chat notice for players joining a non-competitive server.
function M.print_mode_notice(player)
    if not M.is_active() then return end
    player.print({"mts-chat.mode-notice", ls_guidance()})
end

return M
