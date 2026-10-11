-- tests/mock_factorio.lua
-- A synthetic Factorio runtime for headless testing of the reaper.
--
-- Models the one thing that makes team membership subtle: a player who is
-- spectating is moved OFF their own force, so force.players under-reports the
-- team. The mock reproduces that faithfully so the tests can catch a regression
-- that only shows up in-game.

local M = {}

M.TICKS_PER_HOUR = 60 * 60 * 60
M.TICKS_PER_DAY  = M.TICKS_PER_HOUR * 24

local function make_player(spec, index)
    local player = {
        index       = index,
        name        = spec.name or ("player" .. index),
        valid       = true,
        connected   = spec.connected or false,
        last_online = spec.last_online,
        online_time = spec.online_time or 0,
        admin       = spec.admin or false,
        chat_color  = spec.chat_color or {r = 1, g = 1, b = 1},
        printed     = {},
    }
    -- A spectating player physically sits on the spectator force.
    player.force = {name = spec.spectating_from and "spectator" or spec.team}
    player.real_team = spec.team
    player.spectating = spec.spectating_from ~= nil
    function player.print(msg) player.printed[#player.printed + 1] = msg end
    return player
end

local function make_force(name, surfaces)
    local force = {name = name, valid = true, players = {}, charted = {},
                   technologies = {}, platforms = {}}
    -- What team_slots' claim and release call on a force. No-ops: the tests
    -- that run them assert on MTS storage, not on engine diplomacy.
    function force.reset() end
    function force.set_cease_fire(_other, _value) end
    function force.set_friend(_other, _value) end
    function force.is_space_platforms_unlocked() return false end
    function force.unlock_space_platforms() end
    local function key(surface, chunk) return surface.name .. ":" .. chunk.x .. ":" .. chunk.y end
    function force.is_chunk_charted(surface, chunk) return force.charted[key(surface, chunk)] == true end
    function force.chart(surface, area)
        for chunk in surface.get_chunks() do
            if chunk.area[1][1] >= area[1][1] and chunk.area[2][1] <= area[2][1]
               and chunk.area[1][2] >= area[1][2] and chunk.area[2][2] <= area[2][2] then
                force.charted[key(surface, chunk)] = true
            end
        end
    end
    function force.get_item_production_statistics(surface)
        -- Engine statistics are per (force, surface) and know NOTHING about
        -- MTS's ownership map. `produced_by` is the engine-level fact; `owner`
        -- is MTS's storage-level fact. retire_team_surface clears the latter
        -- before the async delete, and the former must survive that.
        if surface.produced_by ~= name then return {input_counts = {}} end
        return {input_counts = surface.production or {}}
    end
    return force
end

local function make_surface(name, owner, spec)
    local surface = {
        name = name, valid = true, owner = owner, produced_by = owner,
        production = spec.production or {},
        entities   = spec.entities or 0,
        ghosts     = spec.ghosts or 0,
    }
    -- A small grid of generated chunks, so chart sync has something to walk.
    local side = spec.chunk_side or 2
    function surface.get_chunks()
        local list, i = {}, 0
        for cx = 0, side - 1 do for cy = 0, side - 1 do
            list[#list + 1] = {x = cx, y = cy,
                area = {{cx * 32, cy * 32}, {cx * 32 + 32, cy * 32 + 32}}}
        end end
        return function() i = i + 1; return list[i] end
    end
    surface.index = spec.index or 0
    function surface.count_entities_filtered(filter)
        if filter.type == "entity-ghost" then return surface.ghosts end
        return surface.entities + surface.ghosts
    end
    return surface
end

--- Build the world. See tests/test_reaper.lua for the spec shape.
function M.build(spec)
    local tick      = spec.tick or (M.TICKS_PER_DAY * 30)
    local max_teams = spec.max_teams or 8

    _G.storage = {
        team_pool            = {},
        team_slot_generation = {},
        team_names           = {},
        spectator_real_force = {},
        team_online_ticks    = {},
    }

    local forces   = {spectator = make_force("spectator", {})}
    local surfaces = {}
    local players  = {}
    local next_index = 0

    for slot = 1, max_teams do
        local name = "team-" .. slot
        forces[name] = make_force(name, {})
        storage.team_pool[slot] = "available"
        storage.team_slot_generation[slot] = 0
    end

    for slot, team in pairs(spec.teams or {}) do
        local force_name = "team-" .. slot
        storage.team_pool[slot] = team.occupied == false and "available" or "occupied"
        storage.team_slot_generation[slot] = team.generation or 0
        storage.team_online_ticks[force_name] = team.online_ticks or 0
        if team.display_name then storage.team_names[force_name] = team.display_name end

        for i, surface_spec in ipairs(team.surfaces or {}) do
            local sname = force_name .. "-s" .. i
            surface_spec.index = slot * 100 + i
            surfaces[sname] = make_surface(sname, force_name, surface_spec)
        end

        for _, member_spec in ipairs(team.members or {}) do
            next_index = next_index + 1
            member_spec.team = force_name
            local player = make_player(member_spec, next_index)
            players[next_index] = player
            if member_spec.spectating_from then
                storage.spectator_real_force[next_index] = force_name
            end
        end
    end

    -- force.players reflects PHYSICAL force membership, so a spectator is
    -- absent from their own team. This is the trap the reaper must avoid.
    for _, player in pairs(players) do
        local force = forces[player.force.name]
        if force then force.players[#force.players + 1] = player end
    end

    for _, surface_spec in ipairs(spec.orphan_surfaces or {}) do
        surfaces[surface_spec.name] =
            make_surface(surface_spec.name, surface_spec.owner, surface_spec)
    end

    _G.game = {
        tick     = tick,
        forces   = forces,
        surfaces = surfaces,
        players  = players,
        printed  = {},
        connected_players = (function()
            local out = {}
            for _, p in pairs(players) do
                if p.connected then out[#out + 1] = p end
            end
            return out
        end)(),
    }
    -- An index or a name, as LuaGameScript.get_player takes; nil when unknown.
    function game.get_player(id)
        if type(id) == "string" then
            for _, p in pairs(players) do
                if p.name == id then return p end
            end
            return nil
        end
        return players[id]
    end
    function game.print(msg) game.printed[#game.printed + 1] = msg end

    _G.prototypes = {item = {}}
    for _, name in ipairs(spec.items or {}) do prototypes.item[name] = {name = name} end

    _G.log = function(_msg) end
    _G.commands = {registered = {}}
    function commands.add_command(name, help, fn)
        commands.registered[name] = {help = help, fn = fn}
    end
    _G.helpers = {files = {}, table_to_json = M.to_json}
    function helpers.write_file(name, data, _append, _for_player)
        helpers.files[name] = data
    end

    M.spec = spec
    return {forces = forces, players = players, surfaces = surfaces}
end

--- A prototype set rich enough to run the REAL gui/stats/discovery.lua.
--- spec.labs    = { {inputs = {"a","b"}}, ... }
--- spec.recipes = { name = {enabled=bool, unlocked_by="tech", products={{type,name}},
---                          main_product="name"} }
--- spec.techs   = { name = {prereqs = {"other"}} }
--- spec.ores    = { name = {"item-name"} }
--- Items are inferred from every name mentioned, so a science pack that no
--- recipe produces still exists as an item -- which is exactly the situation
--- that put space-science-pack ahead of automation-science-pack on SeaBlock.
function M.install_prototypes(spec)
    local items, order = {}, 0
    local function item(name)
        if items[name] then return end
        order = order + 1
        items[name] = {name = name, hidden = false, hidden_in_factoriopedia = false,
                       parameter = false, order = string.format("%03d", order),
                       group = {order = "a"}}
    end

    local entity = {}
    for i, lab in ipairs(spec.labs or {}) do
        entity["lab" .. i] = {type = "lab", lab_inputs = lab.inputs}
        for _, name in ipairs(lab.inputs) do item(name) end
    end
    for ore, products in pairs(spec.ores or {}) do
        local list = {}
        for _, name in ipairs(products) do
            list[#list + 1] = {type = "item", name = name}
            item(name)
        end
        entity[ore] = {type = "resource", mineable_properties = {products = list}}
    end

    local recipe = {}
    for name, def in pairs(spec.recipes or {}) do
        local products = {}
        for _, p in ipairs(def.products) do
            products[#products + 1] = {type = p.type or "item", name = p.name}
            if (p.type or "item") == "item" then item(p.name) end
        end
        recipe[name] = {enabled = def.enabled == true, products = products,
                        main_product = def.main_product and {name = def.main_product} or nil}
    end

    local technology = {}
    for name, def in pairs(spec.techs or {}) do
        local prereqs = {}
        for _, p in ipairs(def.prereqs or {}) do prereqs[p] = true end
        local effects = {}
        for _, r in ipairs(def.unlocks or {}) do
            effects[#effects + 1] = {type = "unlock-recipe", recipe = r}
        end
        technology[name] = {prerequisites = prereqs, effects = effects}
    end

    _G.prototypes = {item = items, fluid = {}, recipe = recipe,
                     entity = entity, technology = technology}
end

--- Register stubs for every MTS module the reaper requires, so the real
--- reaper code loads without pulling in the whole mod.
--- opts.real_discovery keeps gui.stats.discovery UNSTUBBED, so a test can
--- exercise the actual unlock-depth sort that chooses the progress marker.
function M.install_stubs(opts)
    opts = opts or {}
    package.loaded["scripts.helpers"] = {
        team_slot = function(name)
            local n = tostring(name):match("^team%-(%d+)$")
            return n and tonumber(n) or nil
        end,
        display_name = function(force_name)
            return (storage.team_names or {})[force_name] or force_name
        end,
        team_tag = function(force_name) return "[" .. force_name .. "]" end,
        team_tag_with_leader = function(force_name) return "[" .. force_name .. "]" end,
        broadcast = function(msg) game.print(msg) end,
        is_team_force = function(name)
            return tostring(name):match("^team%-%d+$") ~= nil
        end,
        WHITE = {r = 1, g = 1, b = 1},
        ls_join = function(items, sep)
            local out = {""}
            for i, item in ipairs(items) do
                if i > 1 then out[#out + 1] = sep end
                out[#out + 1] = item
            end
            return out
        end,
        colored_name = function(name, _color) return name end,
        fmt_span = function(ticks)
            local m = math.floor(ticks / 3600)
            local h = math.floor(m / 60); m = m % 60
            local d = math.floor(h / 24); h = h % 24
            if d >= 1 then return h > 0 and (d .. "d " .. h .. "h") or (d .. "d") end
            if h >= 1 then return h .. "h " .. m .. "m" end
            if m >= 1 then return m .. "m" end
            return "<1m"
        end,
    }

    package.loaded["scripts.force_utils"] = {
        max_teams = function() return M.spec.max_teams or 8 end,
        is_team_force = function(name)
            return tostring(name):match("^team%-%d+$") ~= nil
        end,
        cleanup_force_surfaces = function(force_name)
            storage.cleaned = storage.cleaned or {}
            storage.cleaned[#storage.cleaned + 1] = force_name
        end,
        release_team_slot = function(force_name)
            local slot = tonumber(tostring(force_name):match("(%d+)$"))
            storage.team_pool[slot] = "available"
            storage.team_slot_generation[slot] =
                (storage.team_slot_generation[slot] or 0) + 1
        end,
    }

    package.loaded["scripts.surface_utils"] = {
        get_owner = function(surface) return surface and surface.owner or nil end,
        owned_surfaces_by_force = function(force_name)
            local out = {}
            for _, surface in pairs(game.surfaces) do
                if surface.valid and surface.owner == force_name then
                    out[#out + 1] = surface
                end
            end
            return out
        end,
    }

    package.loaded["scripts.team_clock"] = {
        online_ticks = function(force_name)
            return (storage.team_online_ticks or {})[force_name] or 0
        end,
    }

    package.loaded["scripts.spectator"] = {
        get_effective_force = function(player)
            return (storage.spectator_real_force or {})[player.index]
                or player.force.name
        end,
        is_spectating = function(player)
            return (storage.spectator_real_force or {})[player.index] ~= nil
        end,
        exit = function(player)
            local real = storage.spectator_real_force[player.index]
            if real then player.force = {name = real}; end
            storage.spectator_real_force[player.index] = nil
        end,
        exit_all_for_force = function(force_name)
            for index, real in pairs(storage.spectator_real_force or {}) do
                if real == force_name then
                    local player = game.get_player(index)
                    if player then
                        player.force = {name = force_name}
                        game.forces[force_name].players[#game.forces[force_name].players + 1] = player
                    end
                    storage.spectator_real_force[index] = nil
                end
            end
        end,
    }

    if opts.real_discovery then
        package.loaded["gui.stats.discovery"] = nil
    else
    package.loaded["gui.stats.discovery"] = {
        proto_lists = function()
            local science = {}
            for _, name in ipairs(M.spec.science or {}) do
                science[#science + 1] = {name = name}
            end
            return {science = science, ores = {}, plates = {}}
        end,
        -- Default true: the simple mock's science list is assumed makeable.
        -- spec.unmakeable = {["space-pack"] = true} models a lab input that no
        -- recipe produces, without needing the full prototype set.
        has_known_producer = function(name)
            return (M.spec.unmakeable or {})[name] ~= true
        end,
    }
    end

    package.loaded["gui.landing_pen"] = {
        return_to_pen = function(player)
            storage.penned = storage.penned or {}
            storage.penned[player.index] = true
        end,
        update_pen_gui_all = function() end,
    }

    package.loaded["gui.teams"] = {update_all = function() end}
end

-- ─── Agent tools: JSON, the engine's seams, live players ──────────────

local function is_array(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return n > 0
end

local function json_string(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        return string.format("\\u%04x", c:byte())
    end) .. '"'
end

--- A compact JSON writer standing in for helpers.table_to_json. Integers
--- print bare; any other number prints at 17 significant digits, so a double
--- that leaks into a reply shows up as the long run of digits the engine
--- sends. Anything that is not plain data refuses, as the engine would.
function M.to_json(v)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
        return string.format("%.17g", v)
    end
    if t == "string" then return json_string(v) end
    if t ~= "table" then error("cannot encode a " .. t .. " as JSON", 0) end
    local parts = {}
    if next(v) == nil then return "[]" end
    if is_array(v) then
        for i = 1, #v do parts[i] = M.to_json(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local value = v[k]
        if value == nil then value = v[tonumber(k)] end
        parts[#parts + 1] = json_string(k) .. ":" .. M.to_json(value)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

--- What crosses remote.call: a copy, and plain data only.
function M.copy(v)
    local t = type(v)
    if t == "function" or t == "userdata" or t == "thread" then
        error("remote.call cannot carry a " .. t, 0)
    end
    if t ~= "table" then return v end
    local out = {}
    for k, value in pairs(v) do out[M.copy(k)] = M.copy(value) end
    return out
end

M.make_force = make_force

--- script, defines, remote and settings: the seams remote_api, the event
--- modules and team_slots touch at load and at call time.
function M.install_engine(opts)
    opts = opts or {}
    _G.defines = {events = {
        on_player_changed_force = "on_player_changed_force",
        on_player_promoted      = "on_player_promoted",
        on_player_demoted       = "on_player_demoted",
        on_player_died          = "on_player_died",
        on_pre_player_removed   = "on_pre_player_removed",
    }}
    local next_id = 1000
    _G.script = {handlers = {}, raised = {}}
    function script.generate_event_name() next_id = next_id + 1; return next_id end
    function script.raise_event(id, payload) script.raised[#script.raised + 1] = {id = id, data = payload} end
    function script.on_event(id, fn) script.handlers[id] = fn end
    _G.remote = {interfaces = {}, impl = {}}
    function remote.add_interface(name, functions)
        if remote.impl[name] then error("interface " .. name .. " already exists", 0) end
        remote.impl[name] = functions
        remote.interfaces[name] = {}
        for fn in pairs(functions) do remote.interfaces[name][fn] = true end
    end
    function remote.remove_interface(name)
        remote.impl[name], remote.interfaces[name] = nil, nil
        return true
    end
    function remote.call(iface, fn, ...)
        local f = remote.impl[iface] and remote.impl[iface][fn]
        if not f then error("unknown interface or function: " .. tostring(iface) .. "." .. tostring(fn), 0) end
        return M.copy(f(table.unpack(M.copy({...}))))
    end
    _G.settings = {startup = {mts_max_teams = {value = opts.max_teams or 8}}}
end

--- Moves a player between forces the way the engine does: the force.players
--- lists follow, and on_player_changed_force fires synchronously, inside the
--- assignment, carrying the OLD force.
local function change_force(player, state, new)
    if type(new) == "string" then new = game.forces[new] end
    local old = state.force
    if old == new then return end
    if old then
        for i, p in ipairs(old.players) do
            if p == player then table.remove(old.players, i); break end
        end
    end
    state.force = new
    new.players[#new.players + 1] = player
    local handler = script and script.handlers[defines.events.on_player_changed_force]
    if handler then
        handler({name = defines.events.on_player_changed_force, tick = game.tick,
                 player_index = player.index, force = old})
    end
end

--- A player whose `force` is a real mock force and whose force assignment
--- behaves like LuaPlayer's (see change_force). Appended to game.players.
function M.add_live_player(spec)
    local index = #game.players + 1
    local state = {}
    -- chat_color and color: what team_slots' leave and the team tags read.
    local player = {index = index, name = spec.name or ("player" .. index), valid = true,
                    connected = spec.connected or false, printed = {},
                    chat_color = {r = 1, g = 1, b = 1}, color = {r = 1, g = 1, b = 1}}
    function player.print(msg) player.printed[#player.printed + 1] = msg end
    setmetatable(player, {
        __index = function(_, key) if key == "force" then return state.force end end,
        __newindex = function(t, key, value)
            if key == "force" then change_force(t, state, value) else rawset(t, key, value) end
        end,
    })
    game.players[index] = player
    local force = game.forces[spec.force or "spectator"]
    state.force = force
    force.players[#force.players + 1] = player
    return player
end

--- Drop every reaper module so the next test re-requires it against fresh
--- stubs and a fresh world.
function M.reset_modules()
    for name in pairs(package.loaded) do
        if tostring(name):match("^scripts%.reaper") or name == "scripts.reaper"
           or name == "scripts.team_teardown"
           or name == "gui.stats.discovery"      -- caches depths at module scope
           or name == "gui.cleanup.state"
           or name == "scripts.activity"
           or name == "gui.teams_data" then
            package.loaded[name] = nil
        end
    end
end

return M
