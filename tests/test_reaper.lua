-- tests/test_reaper.lua
-- Headless behaviour tests for the inactive-team reaper.

local mock = require("tests.mock_factorio")

local DAY  = mock.TICKS_PER_DAY
local HOUR = mock.TICKS_PER_HOUR
local NOW  = 30 * DAY

local report = {passed = 0, failed = 0, failures = {}}

local function check(name, ok, detail)
    if ok then
        report.passed = report.passed + 1
    else
        report.failed = report.failed + 1
        report.failures[#report.failures + 1] = name .. (detail and ("  -> " .. detail) or "")
    end
end

local function eq(name, actual, expected)
    check(name, actual == expected,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

--- Fresh world + freshly required reaper modules.
local function setup(spec)
    spec.tick    = spec.tick or NOW
    spec.science = spec.science or {"red-pack", "green-pack"}
    spec.items   = spec.items or {"red-pack", "green-pack"}
    mock.reset_modules()
    mock.build(spec)
    mock.install_stubs()
    local mods = {
        config   = require("scripts.reaper.config"),
        markers  = require("scripts.reaper.markers"),
        members  = require("scripts.reaper.members"),
        scan     = require("scripts.reaper.scan"),
        journal  = require("scripts.reaper.journal"),
        execute  = require("scripts.reaper.execute"),
        teardown = require("scripts.team_teardown"),
        reaper   = require("scripts.reaper"),
    }
    mods.markers.resolve()
    return mods
end

local function member(opts)
    return {
        name        = opts.name or "p",
        connected   = opts.connected or false,
        last_online = opts.last_online,
        online_time = opts.online_time or HOUR,
        spectating_from = opts.spectating_from,
    }
end

local function team(opts)
    return {
        occupied     = opts.occupied,
        generation   = opts.generation,
        online_ticks = opts.online_ticks or HOUR,
        display_name = opts.display_name,
        members      = opts.members or {},
        surfaces     = opts.surfaces or {{production = opts.production or {}}},
    }
end

local function row_for(result, slot)
    for _, row in ipairs(result.rows) do
        if row.slot == slot then return row end
    end
end

-- ─── markers ───────────────────────────────────────────────────────────

do
    local m = setup{science = {"angels-token-bio", "red-pack", "green-pack"},
                    items   = {"angels-token-bio", "red-pack", "green-pack"},
                    teams   = {}}
    eq("markers: tier1 is first by discovery order", m.markers.tier1(), "angels-token-bio")
    eq("markers: tier2 is second", m.markers.tier2(), "red-pack")
    check("markers: ready when prototype exists", m.markers.ready())

    m.markers.set_override("tier1", "red-pack")
    eq("markers: override wins", m.markers.tier1(), "red-pack")
    check("markers: override flagged", m.markers.is_override("tier1"))
    m.markers.set_override("tier1", nil)
    eq("markers: clearing override restores discovery", m.markers.tier1(), "angels-token-bio")

    check("markers: rejects override of unknown item",
        m.markers.set_override("tier1", "no-such-item") == false)
end

do
    local m = setup{science = {}, items = {}, teams = {}}
    check("markers: not ready without science packs", m.markers.ready() == false)
    local result = m.scan.run{}
    check("scan: refuses to run without markers", result.ready == false)
    eq("scan: returns no rows when blocked", #result.rows, 0)
end

do
    -- The catastrophic case: a marker naming a prototype this modpack lacks
    -- reads as zero production for every team.
    local m = setup{science = {"ghost-pack"}, items = {}, teams = {}}
    check("markers: not ready when prototype missing", m.markers.ready() == false)
end

-- ─── membership ────────────────────────────────────────────────────────

do
    local m = setup{teams = {
        [1] = team{members = {member{name = "spec", connected = true,
                                     spectating_from = "team-2"}}},
        [2] = team{members = {}},
    }}
    local buckets = m.members.by_force()
    eq("members: spectator counted on their real team", #(buckets["team-1"] or {}), 1)
    eq("members: spectator absent from force.players", #game.forces["team-1"].players, 0)
    check("members: spectator counts as connected",
        m.members.any_connected(buckets["team-1"]))
end

do
    local m = setup{teams = {[1] = team{members = {
        member{name = "old", last_online = NOW - 10 * DAY},
        member{name = "new", last_online = NOW - 2 * DAY},
    }}}}
    local buckets = m.members.by_force()
    eq("members: last_seen is the most recent member",
        m.members.last_seen_tick(buckets["team-1"]), NOW - 2 * DAY)
end

-- ─── the rule ──────────────────────────────────────────────────────────

do
    local m = setup{teams = {
        -- 1: gone 2 days, produced nothing -> the target case
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        -- 2: gone 2 days but produced tier-1 -> keep
        [2] = team{members = {member{last_online = NOW - 2 * DAY}},
                   production = {["red-pack"] = 5}},
        -- 3: gone half a day -> keep
        [3] = team{members = {member{last_online = NOW - HOUR * 12}}},
        -- 4: somebody online -> keep
        [4] = team{members = {member{connected = true}}},
        -- 5: only member is spectating another team -> keep
        [5] = team{members = {member{connected = true, spectating_from = "team-1"}}},
        -- 6: occupied slot with nobody on it -> skip, never reap
        [6] = team{members = {}},
        -- 7: member never recorded online -> skip, never reap
        [7] = team{members = {member{last_online = nil}}},
        -- 8: two members, one back recently -> keep (all must be offline)
        [8] = team{members = {member{last_online = NOW - 10 * DAY},
                              member{last_online = NOW - HOUR * 2}}},
    }}
    local result = m.scan.run{}
    eq("rule: offline + no tier1 reaps",        row_for(result, 1).verdict, "reap")
    eq("rule: tier1 production keeps",          row_for(result, 2).verdict, "keep")
    eq("rule: inside the window keeps",         row_for(result, 3).verdict, "keep")
    eq("rule: connected member keeps",          row_for(result, 4).verdict, "keep")
    eq("rule: spectating member keeps",         row_for(result, 5).verdict, "keep")
    eq("rule: empty slot is skipped",           row_for(result, 6).verdict, "skip")
    eq("rule: empty slot reason",               row_for(result, 6).reason,  "no-members")
    eq("rule: never-seen member is skipped",    row_for(result, 7).verdict, "skip")
    eq("rule: one recent member keeps the team", row_for(result, 8).verdict, "keep")
    eq("rule: reapable count", #m.scan.reapable(result), 1)
end

do
    local m = setup{teams = {[1] = team{members = {
        member{last_online = NOW - 10 * DAY}, member{last_online = NOW - 2 * DAY},
    }}}}
    eq("rule: all members offline reaps",
        row_for(m.scan.run{}, 1).verdict, "reap")
end

do
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 3}}, {production = {["red-pack"] = 4}}},
    }}}
    local row = row_for(m.scan.run{}, 1)
    eq("production: summed across owned surfaces", row.tier1, 7)
    eq("production: team kept when any surface produced", row.verdict, "keep")
end

do
    local m = setup{
        teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}},
        orphan_surfaces = {{name = "other", owner = "team-2",
                            production = {["red-pack"] = 999}}},
    }
    local row = row_for(m.scan.run{}, 1)
    eq("production: ignores surfaces owned by another force", row.tier1, 0)
    eq("production: still reaped", row.verdict, "reap")
end

do
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{entities = 40, ghosts = 900}},
    }}}
    local row = row_for(m.scan.run{full = true}, 1)
    eq("entities: ghosts excluded from the count", row.entities, 40)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    m.config.set_number("offline_days", 5)
    eq("config: raising the window spares the team",
        row_for(m.scan.run{}, 1).verdict, "keep")
    m.config.set_number("offline_days", 1)
    eq("config: lowering it takes the team again",
        row_for(m.scan.run{}, 1).verdict, "reap")
    eq("config: value is clamped to bounds", m.config.set_number("offline_days", 900), 60)
end

-- ─── journal ───────────────────────────────────────────────────────────

do
    local m = setup{teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{connected = true}}},
    }}
    local result = m.scan.run{}
    eq("journal: cycle counts flagged teams", m.journal.record_cycle(result.rows), 1)
    eq("journal: verdict stored per slot", m.journal.verdict_for(1).verdict, "reap")
    check("journal: standing reap resolves", m.journal.standing_reap(1, "team-1") ~= nil)

    storage.team_slot_generation[1] = 7
    check("journal: recycled slot invalidates the verdict",
        m.journal.standing_reap(1, "team-1") == nil)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    m.journal.record_cycle(m.scan.run{}.rows)
    local player = game.get_player(1)
    check("journal: return is recorded", m.journal.note_return(player, "team-1", 1))
    eq("journal: resurrection counted", m.journal.stats().resurrections, 1)
    eq("journal: verdict flipped to keep", m.journal.verdict_for(1).verdict, "keep")
    eq("journal: second return is not double counted",
        m.journal.note_return(player, "team-1", 1), false)
end

do
    local m = setup{teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{last_online = NOW - HOUR}}},
    }}
    m.journal.record_cycle(m.scan.run{}.rows)
    m.journal.note_manual_disband("team-1", 1, "admin")
    m.journal.note_manual_disband("team-2", 2, "admin")
    eq("journal: agreement counted",    m.journal.stats().agreements, 1)
    eq("journal: disagreement counted", m.journal.stats().disagreements, 1)
end

do
    local m = setup{teams = {}}
    m.config.set_number("history_limit", 50)
    for i = 1, 80 do m.journal.append("test", {n = i}) end
    eq("journal: history is bounded", #storage.reaper_history, 50)
    eq("journal: oldest entries dropped first", storage.reaper_history[1].n, 31)
end

-- ─── teardown ──────────────────────────────────────────────────────────

do
    local m = setup{teams = {[1] = team{members = {
        member{name = "away", last_online = NOW - 2 * DAY},
        member{name = "here", connected = true},
    }}}}
    local ok, tag = m.teardown.teardown("team-1", {inactive = true})
    check("teardown: succeeds", ok, tostring(tag))
    eq("teardown: slot released", storage.team_pool[1], "available")
    eq("teardown: generation bumped", storage.team_slot_generation[1], 1)
    check("teardown: surfaces cleaned", (storage.cleaned or {})[1] == "team-1")
    check("teardown: offline member gets a queued notice",
        (storage.reaper_notice or {})[1] == true)
    check("teardown: online member is sent to the pen",
        (storage.penned or {})[2] == true)
    eq("teardown: online member told once", #game.get_player(2).printed, 1)
end

do
    local m = setup{teams = {[1] = team{occupied = false, members = {}}}}
    local ok, reason = m.teardown.teardown("team-1", {})
    check("teardown: refuses an unoccupied slot", ok == false)
    eq("teardown: reason is freed", reason, m.teardown.FREED)
end

do
    local m = setup{teams = {[1] = team{generation = 3,
        members = {member{last_online = NOW - 2 * DAY}}}}}
    local ok, reason = m.teardown.teardown("team-1", {expected_generation = 2})
    check("teardown: refuses a recycled slot", ok == false)
    eq("teardown: reason is recycled", reason, m.teardown.RECYCLED)
    eq("teardown: slot untouched", storage.team_pool[1], "occupied")
end

do
    local m = setup{teams = {[1] = team{members = {
        member{name = "spec", connected = true, spectating_from = "team-1"}}}}}
    local ok = m.teardown.teardown("team-1", {inactive = true})
    check("teardown: reaches a spectating member", ok)
    check("teardown: spectating member penned", (storage.penned or {})[1] == true)
end

do
    -- Spectating when the server went down: offline on the spectator force,
    -- still the team's member. The scan judges them on when they were last
    -- online, like any member, and never reads the team as empty.
    local m = setup{teams = {
        [1] = team{members = {member{name = "gone", last_online = NOW - 2 * DAY,
                                     spectating_from = "team-2"}}},
        [2] = team{members = {member{name = "back", last_online = NOW - HOUR,
                                     spectating_from = "team-1"}}},
    }}
    local result = m.scan.run{}
    eq("rule: an offline spectating member long gone reaps", row_for(result, 1).verdict, "reap")
    eq("rule: one online an hour ago keeps", row_for(result, 2).verdict, "keep")
end

do
    local m = setup{teams = {[1] = team{members = {
        member{name = "spec", last_online = NOW - 2 * DAY, spectating_from = "team-2"}}}}}
    storage.spawned_players = {[1] = true}
    local ok = m.teardown.teardown("team-1", {inactive = true})
    check("teardown: reaches an offline spectating member", ok)
    eq("teardown: they end on the spectator force", game.get_player(1).force.name, "spectator")
    eq("teardown: no longer watching for the team", storage.spectator_real_force[1], nil)
    check("teardown: they land in the pen when they reconnect", storage.spawned_players[1] == nil)
    check("teardown: and are told why then", (storage.reaper_notice or {})[1] == true)
    check("teardown: not sent to the pen while offline", (storage.penned or {})[1] == nil)
end

-- ─── staged execution ──────────────────────────────────────────────────

do
    local m = setup{teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{last_online = NOW - 3 * DAY}}},
        [3] = team{members = {member{last_online = NOW - 4 * DAY}}},
    }}
    local result = m.scan.run{}
    local entries = m.execute.entries_from_rows(m.scan.reapable(result))
    eq("execute: three teams queued", #entries, 3)
    check("execute: enqueue accepted", m.execute.enqueue(entries, {source = "manual"}))
    check("execute: reports running", m.execute.is_running())
    m.execute.tick()
    eq("execute: nothing is torn down inside the warning window", storage.team_pool[1], "occupied")
    game.tick = game.tick + m.execute.WARNING_TICKS

    local drained = 0
    for _ = 1, 10 do
        if not m.execute.is_running() then break end
        m.execute.tick()
        drained = drained + 1
    end
    check("execute: queue drains", m.execute.is_running() == false)
    eq("execute: one tick call per team, no trailing tick", drained, 3)
    eq("execute: all slots freed",
        (storage.team_pool[1] .. storage.team_pool[2] .. storage.team_pool[3]),
        "availableavailableavailable")
    local function count(key)
        local n = 0
        for _, msg in ipairs(game.printed) do if msg[1] == key then n = n + 1 end end
        return n
    end
    eq("execute: one line per team as it starts",  count("mts-chat.disbanding-team"), 3)
    eq("execute: exactly one closing summary",     count("mts-chat.teams-disbanded-bulk"), 1)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    local result = m.scan.run{}
    m.journal.record_cycle(result.rows)
    local entries = m.execute.entries_from_rows(m.scan.reapable(result))
    m.execute.enqueue(entries, {source = "auto", recheck = true})

    -- The player comes back after the verdict was written.
    game.get_player(1).connected = true
    game.tick = game.tick + m.execute.WARNING_TICKS
    m.execute.tick()
    eq("execute: returning player is not destroyed", storage.team_pool[1], "occupied")
    eq("execute: return recorded as a resurrection", m.journal.stats().resurrections, 1)
end

do
    local m = setup{teams = {[1] = team{generation = 0,
        members = {member{last_online = NOW - 2 * DAY}}}}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    storage.team_slot_generation[1] = 9        -- recycled before the queue drained
    m.execute.enqueue(entries, {source = "manual"})
    game.tick = game.tick + m.execute.WARNING_TICKS
    m.execute.tick()
    eq("execute: recycled slot survives", storage.team_pool[1], "occupied")
end

do
    local m = setup{teams = {}}
    check("execute: empty selection is rejected", m.execute.enqueue({}, {}) == false)
end

-- ─── facade: arming, reminders, join ───────────────────────────────────

do
    local m = setup{teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{connected = true}}},
    }}
    local result = m.reaper.run_cycle{}
    eq("facade: shadow cycle flags without destroying", result.flagged, 1)
    eq("facade: shadow leaves the slot alone", storage.team_pool[1], "occupied")
    check("facade: shadow queues nothing", m.execute.is_running() == false)
    eq("facade: badge counts standing reaps", m.reaper.badge_count(), 1)
end

do
    local m = setup{max_teams = 4, teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{last_online = NOW - 3 * DAY}}},
    }}
    m.config.set_flag("auto_disband_enabled", true)
    local result = m.reaper.run_cycle{}
    eq("facade: armed cycle enqueues the flagged set", result.enqueued, 2)
    check("facade: armed cycle starts the queue", m.execute.is_running())
    game.tick = game.tick + m.execute.WARNING_TICKS
    for _ = 1, 5 do
        if not m.execute.is_running() then break end
        m.execute.tick()
    end
    eq("facade: armed cycle frees slot 1", storage.team_pool[1], "available")
    eq("facade: armed cycle frees slot 2", storage.team_pool[2], "available")
    eq("facade: execution is journalled", m.journal.stats().executed, 2)
end

do
    local m = setup{teams = {[1] = team{members = {member{connected = true}}}}}
    m.config.set_flag("auto_disband_enabled", true)
    local result = m.reaper.run_cycle{}
    eq("facade: armed cycle with nothing flagged queues nothing", result.enqueued, nil)
    check("facade: queue stays idle", m.execute.is_running() == false)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    m.config.set_number("cycle_hours", 6)
    m.reaper.run_cycle{}
    local cycles = m.journal.stats().cycles

    game.tick = NOW + 3 * HOUR
    m.reaper.heartbeat()
    eq("facade: heartbeat waits for the interval", m.journal.stats().cycles, cycles)

    game.tick = NOW + 7 * HOUR
    m.reaper.heartbeat()
    eq("facade: heartbeat runs once due", m.journal.stats().cycles, cycles + 1)
end

do
    local m = setup{max_teams = 10, teams = {
        [1] = team{members = {member{connected = true}}},
        [2] = team{members = {member{connected = true}}},
    }}
    eq("facade: free slots counted", m.reaper.free_slots(), 8)
end

do
    local m = setup{teams = {[1] = team{members = {
        member{name = "back", last_online = NOW - 2 * DAY}}}}}
    m.reaper.run_cycle{}
    local player = game.get_player(1)
    player.force = {name = "team-1"}
    m.reaper.on_player_joined(player)
    eq("facade: join records the resurrection", m.journal.stats().resurrections, 1)
    eq("facade: badge drops after the return", m.reaper.badge_count(), 0)
end

do
    local m = setup{teams = {[1] = team{members = {member{name = "ret"}}}}}
    storage.reaper_notice = {[1] = true}
    local player = game.get_player(1)
    m.reaper.on_player_joined(player)
    eq("facade: disband notice delivered once", #player.printed, 1)
    check("facade: notice cleared", storage.reaper_notice[1] == nil)
    m.reaper.on_player_joined(player)
    eq("facade: notice not repeated", #player.printed, 1)
end

do
    local m = setup{max_teams = 3, teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{name = "admin1", connected = true, admin = true}}},
    }}
    game.players[2].admin = true
    m.reaper.run_cycle{}
    local admin = game.get_player(2)
    local before = #admin.printed
    m.config.set_number("slot_pressure_min", 2)
    m.reaper.on_team_changed()
    check("facade: slot pressure warns once", #admin.printed > before)
    local after = #admin.printed
    m.reaper.on_team_changed()
    eq("facade: slot pressure does not repeat", #admin.printed, after)
end

do
    -- A save whose mod files changed without a version bump never fires
    -- on_configuration_changed, so nothing calls resolve() at load.
    mock.reset_modules()
    mock.build{tick = NOW, science = {"red-pack", "green-pack"},
               items = {"red-pack", "green-pack"},
               teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    mock.install_stubs()
    local markers = require("scripts.reaper.markers")
    local scan    = require("scripts.reaper.scan")
    check("markers: resolve happens lazily on first use", markers.ready())
    eq("markers: lazy resolve picks tier1", markers.tier1(), "red-pack")
    eq("markers: scan works without an explicit resolve",
        row_for(scan.run{}, 1).verdict, "reap")
end

-- ─── marker resolution against the REAL discovery module ───────────────
-- These exercise gui/stats/discovery.lua itself, not the stub. The stub
-- hands markers a pre-ordered list, which is precisely why the shipped
-- suite was blind to the SeaBlock failure: space-science-pack has no
-- producing recipe there, scored depth 0, and led the science list.

local function setup_real_discovery(protos)
    mock.reset_modules()
    mock.build{tick = NOW, teams = {}}
    mock.install_prototypes(protos)
    mock.install_stubs{real_discovery = true}
    return {
        discovery = require("gui.stats.discovery"),
        markers   = require("scripts.reaper.markers"),
        scan      = require("scripts.reaper.scan"),
        config    = require("scripts.reaper.config"),
    }
end

-- SeaBlock in miniature: a lab accepts a pack that nothing can make.
local SEABLOCK_SHAPE = {
    labs = {{inputs = {"space-pack", "red-pack", "green-pack"}}},
    recipes = {
        ["red-pack"]   = {enabled = true,  products = {{name = "red-pack"}}},
        ["green-pack"] = {enabled = false, products = {{name = "green-pack"}}},
    },
    techs = {
        root  = {unlocks = {}},
        mid   = {prereqs = {"root"}, unlocks = {}},
        later = {prereqs = {"mid"},  unlocks = {"green-pack"}},
    },
}

do
    local m = setup_real_discovery(SEABLOCK_SHAPE)
    check("discovery: an unmakeable lab input has no known producer",
        m.discovery.has_known_producer("space-pack") == false)
    check("discovery: a craftable pack has a known producer",
        m.discovery.has_known_producer("red-pack"))

    local science = m.discovery.proto_lists().science
    eq("discovery: unmakeable pack does NOT lead the science list",
        science[1] and science[1].name, "red-pack")
    eq("discovery: it sorts last instead", science[#science].name, "space-pack")

    m.markers.resolve()
    eq("markers: tier1 skips the unmakeable pack", m.markers.tier1(), "red-pack")
    eq("markers: tier2 is the next real one",      m.markers.tier2(), "green-pack")
    check("markers: ready on a modpack like this", m.markers.ready())
end

do
    -- Every science pack unmakeable: the feature must switch itself off
    -- rather than read zero for the whole server and condemn it.
    local m = setup_real_discovery{
        labs = {{inputs = {"space-pack"}}},
        recipes = {["something-else"] = {enabled = true, products = {{name = "gear"}}}},
    }
    m.markers.resolve()
    check("markers: refuses when no science pack is makeable",
        m.markers.ready() == false)
    eq("markers: nothing is pinned", m.markers.tier1(), nil)
    local result = m.scan.run{}
    check("scan: refuses to run rather than flag everything", result.ready == false)
end

do
    -- The pin must survive a configuration change that reorders discovery.
    local m = setup_real_discovery(SEABLOCK_SHAPE)
    m.markers.resolve()
    eq("markers: pinned before the change", m.markers.tier1(), "red-pack")
    m.config.set_flag("auto_disband_enabled", true)

    -- A mod update adds a pack available from the start and pushes the old
    -- tier 1 behind a technology, so discovery genuinely leads with something
    -- else than the pinned marker.
    mock.install_prototypes{
        labs = {{inputs = {"aaa-pack", "red-pack", "green-pack"}}},
        recipes = {
            ["aaa-pack"]   = {enabled = true,  products = {{name = "aaa-pack"}}},
            ["red-pack"]   = {enabled = false, products = {{name = "red-pack"}}},
            ["green-pack"] = {enabled = false, products = {{name = "green-pack"}}},
        },
        techs = {
            root  = {unlocks = {}},
            mid   = {prereqs = {"root"}, unlocks = {}},
            later = {prereqs = {"mid"},  unlocks = {"red-pack", "green-pack"}},
        },
    }
    package.loaded["gui.stats.discovery"] = nil
    package.loaded["scripts.reaper.markers"] = nil
    local markers2 = require("scripts.reaper.markers")
    markers2.resolve()
    eq("markers: the pin is NOT silently repointed", markers2.tier1(), "red-pack")
    check("markers: a shift disarms auto disband",
        m.config.value("auto_disband_enabled") == false)
    check("markers: and blocks until an admin looks", markers2.ready() == false)
end

-- ─── production survives a retired surface ─────────────────────────────

do
    -- mts-dimension-warp retires a team's surface on every warp, and Factorio
    -- discards that surface's production statistics permanently.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 500}}},
    }}}
    eq("retired: team is kept while its surface exists",
        row_for(m.scan.run{}, 1).verdict, "keep")

    local surface = game.surfaces["team-1-s1"]
    m.scan.accrue_from_surface(surface)          -- on_pre_surface_deleted
    game.surfaces["team-1-s1"] = nil             -- engine drops the statistics

    local row = row_for(m.scan.run{full = true}, 1)
    eq("retired: banked production still counts", row.tier1, 500)
    eq("retired: team is NOT condemned after a warp", row.verdict, "keep")
end

do
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 500}}},
    }}}
    m.scan.accrue_from_surface(game.surfaces["team-1-s1"])
    m.scan.clear_retired("team-1")
    game.surfaces["team-1-s1"].production = {}   -- new team, fresh statistics
    eq("retired: a released slot's bank does not follow the force name",
        row_for(m.scan.run{full = true}, 1).verdict, "reap")
end

do
    -- "Could not measure" must never read as "produced nothing". A team whose
    -- surfaces have gone (or whose statistics calls fail) is handed to an admin.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {},
    }}}
    local row = row_for(m.scan.run{full = true}, 1)
    eq("unmeasurable: a team with no readable surface is skipped", row.verdict, "skip")
    eq("unmeasurable: and says why", row.reason, "unmeasurable")
end

do
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {}}},
    }}}
    local row = row_for(m.scan.run{full = true}, 1)
    eq("measurable: a real zero reading still reaps", row.verdict, "reap")
    check("measurable: flagged as measured", row.measured)
end

do
    -- offline_days can only be read back inside its bounds, whatever a stale or
    -- hand-edited save holds. Zero would reap every team the instant it left.
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 60}}}}}
    storage.reaper_config = {offline_days = 0}
    eq("config: an out-of-range window is clamped on read",
        m.config.value("offline_days"), 1)
    eq("config: so a just-left team is not reaped",
        row_for(m.scan.run{}, 1).verdict, "keep")
end

do
    local m = setup{science = {"red-pack", "green-pack"},
                    items = {"red-pack", "green-pack", "rock"},
                    unmakeable = {["rock"] = true},
                    teams = {}}
    check("markers: an override nothing can produce is rejected",
        m.markers.set_override("tier1", "rock") == false)
    check("markers: a producible override is accepted",
        m.markers.set_override("tier1", "green-pack"))
end

do
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 10}}},
    }}}
    local surface = game.surfaces["team-1-s1"]
    m.scan.accrue_from_surface(surface)
    m.scan.accrue_from_surface(surface)
    eq("retired: banking is additive per deletion, not idempotent",
        ((storage.reaper_produced["team-1"] or {}).totals or {})["red-pack"], 20)
end

do
    -- THE warp path. retire_team_surface strips MTS ownership and THEN calls
    -- the async delete, so on_pre_surface_deleted can no longer attribute the
    -- surface. The event path must bank nothing; the hook path must bank.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 500}}},
    }}}
    local surface = game.surfaces["team-1-s1"]
    surface.owner = nil                         -- ownership already unwound
    check("warp: event path cannot attribute an unwound surface",
        m.scan.accrue_from_surface(surface) == false)
    check("warp: nothing banked by the event", storage.reaper_produced == nil
        or storage.reaper_produced["team-1"] == nil)

    check("warp: hook path banks with an explicit owner",
        m.scan.bank_surface("team-1", surface))
    game.surfaces["team-1-s1"] = nil
    eq("warp: team survives on banked production",
        row_for(m.scan.run{full = true}, 1).verdict, "keep")
end

do
    -- THE teardown path. cleanup_force_surfaces deletes asynchronously, so its
    -- pre-delete events land AFTER release_team_slot freed the slot. A bank
    -- written then would be inherited by the next team on the slot.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 500}}},
    }}}
    local surface = game.surfaces["team-1-s1"]
    storage.team_pool[1] = "available"          -- slot already released
    storage.team_slot_generation[1] = 1
    check("teardown: no banking for an unoccupied slot",
        m.scan.bank_surface("team-1", surface) == false)
end

do
    -- A bank written under an older generation is invisible to the new team.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {["red-pack"] = 500}}},
    }}}
    m.scan.bank_surface("team-1", game.surfaces["team-1-s1"])
    storage.team_slot_generation[1] = 7         -- slot recycled since
    game.surfaces["team-1-s1"].production = {}
    eq("teardown: a stale-generation bank is not read",
        row_for(m.scan.run{full = true}, 1).tier1, 0)
end

do
    -- Returning a tier to "auto" after a shift must actually unblock it.
    local m = setup_real_discovery(SEABLOCK_SHAPE)
    m.markers.resolve()
    storage.reaper_markers.tier1 = "green-pack"     -- pretend an old pin
    m.markers.resolve()
    check("markers: shift detected against the old pin", m.markers.ready() == false)
    m.markers.set_override("tier1", nil)             -- "auto": trust discovery now
    eq("markers: auto re-pins from discovery", m.markers.tier1(), "red-pack")
    check("markers: and clears the block", m.markers.ready())
end

-- ─── drain-time re-judgement ───────────────────────────────────────────

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    eq("judge_force: agrees with the full scan", m.scan.judge_force("team-1"), "reap")
    game.get_player(1).connected = true
    eq("judge_force: sees a live return", m.scan.judge_force("team-1"), "keep")
end

do
    -- A queue persisted in the save can resume with a verdict of any age. The
    -- drain re-derives it rather than trusting the snapshot.
    local m = setup{teams = {[1] = team{
        members  = {member{last_online = NOW - 2 * DAY}},
        surfaces = {{production = {}}},
    }}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "auto", recheck = true})
    -- The team got going again before the queue reached it.
    game.surfaces["team-1-s1"].production["red-pack"] = 1
    game.tick = game.tick + m.execute.WARNING_TICKS
    m.execute.tick()
    eq("drain: a team that started producing survives", storage.team_pool[1], "occupied")
end

do
    local m = setup{teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{last_online = NOW - 2 * DAY}}},
    }}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "auto"})
    eq("cancel: drops the pending remainder", m.execute.cancel(), 2)
    check("cancel: queue is gone", m.execute.is_running() == false)
    eq("cancel: nothing to cancel returns zero", m.execute.cancel(), 0)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "manual"})
    eq("cancel: source filter spares another source's sweep",
        m.execute.cancel("auto"), 0)
    check("cancel: manual sweep still running", m.execute.is_running())
end

-- ─── cleanup selection carries the slot generation ─────────────────────

do
    local m = setup{teams = {[1] = team{generation = 4,
        members = {member{last_online = NOW - 2 * DAY}}}}}
    local cleanup_state = require("gui.cleanup.state")
    local player = {index = 1}
    local rows = m.scan.run{full = true}.rows

    cleanup_state.preselect(player, rows)
    eq("selection: preselects the flagged team", #cleanup_state.selected_rows(player, rows), 1)

    storage.team_slot_generation[1] = 5          -- slot recycled by a new team
    local fresh = m.scan.run{full = true}.rows
    eq("selection: a recycled slot drops out of the selection",
        #cleanup_state.selected_rows(player, fresh), 0)
end

do
    local m = setup{teams = {[1] = team{members = {member{connected = true}}}}}
    local cleanup_state = require("gui.cleanup.state")
    local player = {index = 1}
    local rows = m.scan.run{full = true}.rows
    cleanup_state.set(player, "team-1", rows[1].generation)
    eq("selection: an online team is never returned even when ticked",
        #cleanup_state.selected_rows(player, rows), 0)
end

-- ─── shared "last online" definition ───────────────────────────────────

do
    mock.reset_modules()
    mock.build{tick = NOW, teams = {[1] = team{members = {
        member{name = "a", last_online = NOW - 3 * DAY},
        member{name = "b", connected = true},
    }}}}
    mock.install_stubs()
    local activity = require("scripts.activity")
    local a, b = game.get_player(1), game.get_player(2)
    eq("activity: a connected member reads as now", activity.last_online_tick(b), NOW)
    eq("activity: the engine's last_online is the fallback",
        activity.last_online_tick(a), NOW - 3 * DAY)
    storage.player_last_seen = {[1] = NOW - DAY}
    eq("activity: MTS's own leave stamp is preferred",
        activity.last_online_tick(a), NOW - DAY)
    eq("activity: offline_ticks", activity.offline_ticks(a), DAY)
    check("activity: under an hour is fresh", activity.age_color(HOUR - 1) == activity.COLOR_FRESH)
    check("activity: under a day is stale",   activity.age_color(DAY - 1)  == activity.COLOR_STALE)
    check("activity: a day is dead",          activity.age_color(DAY)      == activity.COLOR_DEAD)
end

do
    -- The card's own formatter and per-member helper, run for real.
    mock.reset_modules()
    mock.build{tick = NOW, teams = {[1] = team{members = {
        member{name = "gone",  last_online = NOW - (2 * DAY + 5 * HOUR), online_time = 48 * HOUR},
        member{name = "here",  connected = true, online_time = 35 * 3600},
        member{name = "never", last_online = nil, online_time = 0},
    }}}}
    mock.install_stubs()
    local td = require("gui.teams_data")
    eq("ago: days and hours",    td.fmt_ago(2 * DAY + 5 * HOUR), "2d 5h ago")
    eq("ago: whole days",        td.fmt_ago(3 * DAY), "3d ago")
    eq("ago: hours and minutes", td.fmt_ago(4 * HOUR + 7 * 3600), "4h 7m ago")
    eq("ago: under a minute",    td.fmt_ago(1800), "just now")

    local gone = td.ls_member_activity(game.get_player(1))
    eq("member: offline caption is the ago string", gone.caption[1], "mts-gui.ago-days-hours")
    eq("member: days", gone.caption[2], 2)
    eq("member: hours", gone.caption[3], 5)
    check("member: coloured dead after two days", gone.color == require("scripts.activity").COLOR_DEAD)
    eq("tooltip: is the rich member card", gone.tooltip[1], "mts-tip.member-card")
    eq("tooltip: offline status names the last-seen key",
        gone.tooltip[3][3][1], "mts-tip.member-status-offline")
    eq("tooltip: status line is wrapped in the age colour",
        gone.tooltip[3][2], "[color=#ff6666]")
    eq("member: 48 hours reads as whole hours", gone.played_caption[3][1], "time-symbol-hours-short")
    eq("member: hour count", gone.played_caption[3][2], 48)
    eq("member: offline row separates with a dot", gone.played_caption[2], " · ")

    local here = td.ls_member_activity(game.get_player(2))
    check("member: connected member has no ago caption", here.caption == nil)
    eq("tooltip: online status", here.tooltip[3][3][1], "mts-tip.member-status-online")
    eq("tooltip: online status is green", here.tooltip[3][2], "[color=#66ff66]")
    eq("member: but shows playtime in minutes under an hour",
        here.played_caption[3][1], "time-symbol-minutes-short")
    eq("member: minute count", here.played_caption[3][2], 35)
    eq("member: online row uses a plain space", here.played_caption[2], " ")

    local never = td.ls_member_activity(game.get_player(3))
    eq("member: never-seen caption", never.caption[1], "mts-tip.seen-never")
    eq("tooltip: never-seen status", never.tooltip[3][3][1], "mts-tip.member-status-never")
    eq("member: zero playtime reads under a minute",
        never.played_caption[3][1], "mts-gui.playtime-under-minute")
end

-- ─── day spans, next-check countdown, sort keys ────────────────────────

do
    -- The real formatter, not the stub: scripts/helpers.lua is a leaf.
    package.loaded["scripts.helpers"] = nil
    local real = require("scripts.helpers")
    eq("span: days and hours",      real.fmt_span(4 * DAY + 7 * HOUR + 10 * 3600), "4d 7h")
    eq("span: whole days",          real.fmt_span(2 * DAY), "2d")
    eq("span: hours and minutes",   real.fmt_span(7 * HOUR + 10 * 3600), "7h 10m")
    eq("span: minutes",             real.fmt_span(26 * 3600), "26m")
    eq("span: under a minute",      real.fmt_span(59 * 60), "<1m")
    mock.install_stubs()
end

do
    local m = setup{teams = {}}
    m.config.set_number("cycle_hours", 6)
    storage.reaper_last_run = NOW
    local hb = m.config.HEARTBEAT_TICKS
    local next_run = m.reaper.next_run_tick()
    eq("countdown: next run sits on a heartbeat boundary", next_run % hb, 0)
    check("countdown: not before the interval elapses", next_run >= NOW + 6 * HOUR)
    check("countdown: and not a whole heartbeat late", next_run < NOW + 6 * HOUR + hb)
    game.tick = NOW + 20 * HOUR                       -- long overdue
    eq("countdown: overdue resolves to the next boundary, not the past",
        m.reaper.next_run_tick(), math.ceil((game.tick + 1) / hb) * hb)
end

do
    local cleanup_state = require("gui.cleanup.state")
    check("sort: tier2 is a sortable column", cleanup_state.SORT_KEYS.tier2 == true)
end

-- ─── spectator chart sync ──────────────────────────────────────────────

do
    -- The measured failure: the team has its spawn charted, the spectator
    -- force has nothing, every link and flag is fine.
    mock.reset_modules()
    mock.build{tick = NOW, max_teams = 16,
        teams = {[15] = team{members = {member{last_online = NOW - 5 * DAY}},
        surfaces = {{chunk_side = 3}}}}}
    mock.install_stubs()
    package.loaded["scripts.chart_sync"] = nil
    local chart_sync = require("scripts.chart_sync")
    local team15  = game.forces["team-15"]
    local spec    = game.forces["spectator"]
    local surface = game.surfaces["team-15-s1"]
    team15.chart(surface, {{0, 0}, {64, 64}})          -- the team charted a 2x2 corner
    check("sync: precondition, team sees its spawn", team15.is_chunk_charted(surface, {x = 0, y = 0}))
    check("sync: precondition, spectator does not",  spec.is_chunk_charted(surface, {x = 0, y = 0}) == false)

    eq("sync: pushes exactly the chunks the team has and the viewer lacks",
        chart_sync.push_chart(team15, spec, surface), 4)
    check("sync: spectator now sees spawn", spec.is_chunk_charted(surface, {x = 0, y = 0}))
    check("sync: never reveals what the team itself has not charted",
        spec.is_chunk_charted(surface, {x = 2, y = 2}) == false)
    eq("sync: a second push has nothing to do", chart_sync.push_chart(team15, spec, surface), 0)
    eq("sync: invalid inputs are a no-op", chart_sync.push_chart(nil, spec, surface), 0)
end

do
    mock.reset_modules()
    mock.build{tick = NOW, teams = {
        [1] = team{members = {member{name = "viewer", connected = true}}, surfaces = {{}}},
        [2] = team{members = {}, surfaces = {{}}},
    }}
    mock.install_stubs()
    package.loaded["scripts.chart_sync"] = nil
    local chart_sync = require("scripts.chart_sync")
    local viewer = game.get_player(1)
    viewer.surface = game.surfaces["team-2-s1"]        -- looking at team 2
    storage.spectating_target = {[1] = "team-2"}
    local viewed = chart_sync.viewed_surfaces()
    check("viewed: the surface under a spectator is protected", viewed[game.surfaces["team-2-s1"].index])
    check("viewed: the spectator's own home surface is not", viewed[game.surfaces["team-1-s1"].index] == nil)
    storage.spectating_target = {}
    check("viewed: nobody spectating, nothing protected", next(chart_sync.viewed_surfaces()) == nil)
end

-- ─── offline gradient ──────────────────────────────────────────────────

do
    mock.reset_modules()
    mock.build{tick = NOW, teams = {}}
    mock.install_stubs()
    local activity = require("scripts.activity")
    local W = DAY
    local function near(a, b)
        for i = 1, 3 do if math.abs(a[i] - b[i]) > 1e-9 then return false end end
        return true
    end
    check("gradient: zero is green",             near(activity.age_gradient(0, W), activity.COLOR_FRESH))
    check("gradient: one window is yellow",      near(activity.age_gradient(W, W), activity.COLOR_STALE))
    check("gradient: four windows is red",       near(activity.age_gradient(4 * W, W), activity.COLOR_DEAD))
    check("gradient: beyond stays red",          near(activity.age_gradient(30 * W, W), activity.COLOR_DEAD))
    check("gradient: no window reads unknown",   activity.age_gradient(W, nil) == activity.COLOR_UNKNOWN)

    -- Redder and less green, monotonically, all the way across.
    local prev = activity.age_gradient(0, W)
    local monotone = true
    for step = 1, 40 do
        local c = activity.age_gradient(step * W / 10, W)
        if c[1] < prev[1] - 1e-9 or c[2] > prev[2] + 1e-9 then monotone = false end
        prev = c
    end
    check("gradient: red never falls and green never rises", monotone)
    local half = activity.age_gradient(W / 2, W)
    check("gradient: half a window sits between green and yellow",
        half[1] > activity.COLOR_FRESH[1] and half[1] < activity.COLOR_STALE[1])
end

-- ─── bulk disband countdown ────────────────────────────────────────────

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "manual"})
    local start = game.tick
    while game.tick < start + m.execute.WARNING_TICKS do
        m.execute.tick()
        game.tick = game.tick + m.execute.DRAIN_INTERVAL
    end
    local seen = {}
    for _, msg in ipairs(game.printed) do
        if msg[1] == "mts-chat.bulk-disband-in"        then seen[#seen + 1] = msg[3] end
        if msg[1] == "mts-chat.bulk-disband-countdown" then seen[#seen + 1] = msg[2] end
    end
    eq("countdown: six announcements",                    #seen, 6)
    eq("countdown: in order",                             table.concat(seen, ","), "60,30,10,3,2,1")
    eq("countdown: nothing torn down during the warning", storage.team_pool[1], "occupied")
    m.execute.tick()
    eq("countdown: teardown begins at the start tick",    storage.team_pool[1], "available")
end

do
    -- A queue resumed from a save with most of its window already gone says
    -- one thing, not six.
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "manual"})
    game.tick = game.tick + m.execute.WARNING_TICKS - 2 * 60      -- two seconds left
    m.execute.tick()
    local n, last = 0, nil
    for _, msg in ipairs(game.printed) do
        if msg[1] == "mts-chat.bulk-disband-countdown" then n = n + 1; last = msg[2] end
        if msg[1] == "mts-chat.bulk-disband-in" then n = n + 1 end
    end
    eq("countdown: a jump collapses to one announcement", n, 1)
    eq("countdown: and it is the current one",           last, 2)
end

do
    local m = setup{teams = {[1] = team{members = {member{last_online = NOW - 2 * DAY}}}}}
    local entries = m.execute.entries_from_rows(m.scan.reapable(m.scan.run{}))
    m.execute.enqueue(entries, {source = "manual"})
    m.execute.cancel()
    local cancelled = false
    for _, msg in ipairs(game.printed) do
        if msg[1] == "mts-chat.bulk-disband-cancelled" then cancelled = (msg[2] == 1) end
    end
    check("cancel: everyone hears it, with the count", cancelled)
end

-- ─── armed cycle offers an intervention ────────────────────────────────

do
    local m = setup{max_teams = 4, teams = {
        [1] = team{members = {member{last_online = NOW - 2 * DAY}}},
        [2] = team{members = {member{last_online = NOW - 3 * DAY}}},
        [3] = team{members = {member{connected = true}}},
    }}
    local got
    m.reaper.set_intervention_hook(function(rows) got = rows end)

    m.reaper.run_cycle{}
    check("intervene: shadow mode never prompts", got == nil)

    m.config.set_flag("auto_disband_enabled", true)
    m.reaper.run_cycle{}
    check("intervene: armed cycle hands the flagged rows to the prompt", got ~= nil)
    eq("intervene: exactly the teams about to go", #got, 2)
    check("intervene: the sweep is queued but waiting", m.execute.is_running()
        and storage.team_pool[1] == "occupied")

    eq("intervene: Stop cancels the auto sweep", m.execute.cancel("auto"), 2)
    check("intervene: nothing was removed", storage.team_pool[1] == "occupied"
        and storage.team_pool[2] == "occupied")
end

return report
