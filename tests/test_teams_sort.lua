-- Run from the mod root: lua tests/test_teams_sort.lua
-- Real sorting, membership, activity and display-name helpers; only the
-- engine and spectator state are mocked.
package.loaded["scripts.spectator"] = {
    get_effective_force = function(p) return p.real_team or p.force.name end,
}
storage = {}
game = {tick = 1000, players = {}, get_player = function(i) return game.players[i] end}
local sorting = require("gui.teams_sort")
local passed = 0
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
    passed = passed + 1
end
local function order(ids, mode, own)
    local forces = {}
    for _, id in ipairs(ids) do forces[#forces + 1] = {name = "team-" .. id} end
    sorting.sort(forces, own and ("team-" .. own), mode or "name")
    local names = {}
    for _, force in ipairs(forces) do names[#names + 1] = force.name end
    return table.concat(names, ",")
end
local p1, p2 = {index = 1}, {index = 2}
eq(sorting.get_mode(p1), "name") -- old saves without a preference table
sorting.set_mode(p1, "recent_online")
eq(sorting.get_mode(p1), "recent_online")
eq(sorting.get_mode(p2), "name")
sorting.set_mode(p1, "invalid")
eq(sorting.get_mode(p1), "recent_online")
sorting.set_mode(p1, "name")
eq(sorting.get_mode(p1), "name")

eq(order({13, 10, 2, 1}), "team-1,team-2,team-10,team-13")
eq(order({13, 10, 2, 1}, "name", 13), "team-13,team-1,team-2,team-10")
eq(order({13}, "name", 13), "team-13")
eq(order({}), "")
storage.team_names = {["team-13"] = "Alpha 10", ["team-10"] = "alpha 2",
                      ["team-2"] = "Zulu", ["team-1"] = "Beta"}
eq(order({13, 10, 2, 1}), "team-10,team-13,team-1,team-2")
storage.team_names = {["team-13"] = "Team 002", ["team-10"] = "team 2",
                      ["team-2"] = "Team 02", ["team-1"] = "Team 10"}
eq(order({13, 10, 2, 1}), "team-2,team-10,team-13,team-1")
storage.team_names = {}

local function member(team, connected, last_online, real_team)
    local i = #game.players + 1
    game.players[i] = {index = i, name = "p" .. i, valid = true,
        force = {name = team}, real_team = real_team,
        connected = connected, last_online = last_online}
    storage.spectator_real_force = storage.spectator_real_force or {}
    storage.spectator_real_force[i] = real_team
    return i
end
member("team-1", false, 100)
member("team-2", false, 200)
local stamped = member("team-10", false, 50)
storage.player_last_seen = {[stamped] = 500}
member("spectator", true, 0, "team-13") -- online while watching another team
eq(order({1, 2, 10, 13, 3}, "recent_online"), "team-13,team-10,team-2,team-1,team-3")
eq(order({1, 2, 10, 13, 3}, "recent_online", 3), "team-3,team-13,team-10,team-2,team-1")
member("team-2", false, 750) -- use most recent member, not first member
eq(order({1, 2, 10, 13}, "recent_online"), "team-13,team-2,team-10,team-1")
member("team-10", true, 0)
eq(order({13, 10}, "recent_online"), "team-10,team-13") -- tie by natural name
member("team-1", false, 1000) -- disconnected on the current tick
eq(order({1, 10}, "recent_online"), "team-10,team-1") -- online still comes first
member("team-4", false, 0)
eq(order({3, 4}, "recent_online"), "team-4,team-3") -- zero is known, nil is unknown
eq(order({3, 10, 2}, "name"), "team-2,team-3,team-10") -- name ignores activity

-- Exercise the actual panel builder and selection handler with GUI elements
-- represented as tables. Keep the real checkbox, filtering and sorting code.
for _, module in ipairs({"gui.admin", "gui.landing_pen", "gui.follow_cam",
                         "gui.friendship", "scripts.team_modifiers"}) do
    package.loaded[module] = {}
end
package.loaded["gui.nav"] = {on_click = function() end}
package.loaded["scripts.team_modifiers"].is_active = function() return false end
local spectator = package.loaded["scripts.spectator"]
spectator.get_target = function() return nil end
local cards = {}
package.loaded["gui.team_card"] = {
    build_team_card = function(_, force) cards[#cards + 1] = force.name end,
}
local function element(spec)
    local el = spec or {}
    el.valid, el.style, el.children = true, {}, {}
    el.add = function(child)
        child = element(child)
        el.children[#el.children + 1] = child
        if child.name then el[child.name] = child end
        return child
    end
    return el
end
local helpers = require("scripts.helpers")
helpers.reuse_or_create_frame = function(player, name)
    local frame = element()
    player.gui.screen[name] = frame
    cards = {}
    return frame
end
helpers.add_title_bar = function(frame) return frame.add{type = "flow"} end
local panel = require("gui.teams")
game.forces = {}
for _, id in ipairs({1, 2, 10, 13, 3}) do game.forces["team-" .. id] = {name = "team-" .. id} end
storage.team_pool = {[1] = "occupied", [2] = "occupied", [3] = "occupied",
                     [10] = "occupied", [13] = "occupied"}
local viewer = game.players[1]
viewer.gui = {screen = {}}
storage.teams_sort_mode = nil
local function dropdown()
    local controls = viewer.gui.screen.sb_platforms_frame.children[2]
    eq(controls.children[#controls.children].sb_show_offline_toggle ~= nil, true)
    return controls.sb_teams_sort
end
panel.build_gui(viewer)
eq(dropdown().selected_index, 1)
eq(table.concat(cards, ","), "team-1,team-10,team-13") -- own + online
helpers.toggle_show_offline(viewer)
panel.build_gui(viewer)
eq(table.concat(cards, ","), "team-1,team-2,team-3,team-10,team-13")
local select = dropdown()
select.selected_index = 2
eq(panel.on_gui_selection_state_changed{element = select, player_index = 1}, true)
eq(dropdown().selected_index, 2)
eq(table.concat(cards, ","), "team-1,team-10,team-13,team-2,team-3")
eq(sorting.get_mode(p2), "name")
panel.build_gui(viewer) -- preference survives a rebuild
eq(dropdown().selected_index, 2)
eq(panel.on_gui_selection_state_changed{element = {valid = false}}, false)
eq(panel.on_gui_selection_state_changed{element = {valid = true, name = "other"}}, false)

-- Verify the central event dispatcher routes the dropdown before admin UI.
for _, module in ipairs({"events.helpers", "gui.team_settings", "gui.research",
    "gui.welcome", "gui.stats", "gui.awards", "scripts.force_utils",
    "scripts.blueprint_lock", "gui.hud_clock", "scripts.chat_channel", "gui.cleanup"}) do
    package.loaded[module] = {}
end
local callbacks = {}
defines = {events = setmetatable({}, {__index = function(_, name) return name end})}
script = {on_event = function(event, fn) callbacks[event] = fn end}
require("events.gui_state").register()
select = dropdown()
select.selected_index = 1
callbacks.on_gui_selection_state_changed{element = select, player_index = 1}
eq(dropdown().selected_index, 1)
eq(table.concat(cards, ","), "team-1,team-2,team-3,team-10,team-13")
print(passed .. " team sorting and GUI checks passed")
return {passed = passed, failed = 0, failures = {}}
