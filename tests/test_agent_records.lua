-- tests/test_agent_records.lua
-- Headless tests for the two record tools MTS gives AI Agent Bridge,
-- records and record_chase: counts and rows, the set_fastest_ever replay, a
-- released slot, the in-reach boundary, and records from older saves. The
-- world is tests/agent_world.lua. The manifest, sweep block and clock tools
-- are in test_agent_manifest.lua, the byte budget in test_agent_bytes.lua,
-- and player_teams in test_player_teams.lua.

local W = require("tests.agent_world")

local H = W.H
local world, finish, call = W.world, W.finish, W.call
local whole_numbers, whats, by_what, forces_of = W.whole_numbers, W.whats, W.by_what, W.forces_of

local report, check, eq = W.new_report()

local SCI0   = "science:automation-science-pack@0"
local SCI100 = "science:automation-science-pack@100"
local EXT    = "ext:expanse-cells@10"

-- ─── records: counts and rows, tech + milestone + ext ─────────────────

do
    world{teams = {[1] = {start = 0, name = "Ace"}, [2] = {start = 0, name = "Bee"},
                   [3] = {start = 2 * H, name = "Cat"}}}
    finish("milestone", SCI0,          1, H / 2,      H / 4)
    finish("tech",      "automation",  1, H,          H / 2)
    finish("milestone", SCI100,        2, 1.5 * H,    H)
    finish("milestone", SCI100,        1, 1.75 * H,   H)
    finish("tech",      "logistics",   2, 2 * H,      2 * H)
    finish("tech",      "logistics",   1, 3 * H,      H)
    finish("tech",      "electronics", 1, 4 * H,      2 * H)
    finish("tech",      "electronics", 3, 5 * H,      H)
    finish("milestone", EXT,           1, 6 * H,      3 * H)
    -- records.update leaves an empty record behind when a team with no
    -- clock finishes something; it names nobody and must count for nobody.
    storage.tech_records["never-finished"] = {}
    game.tick = 10 * H

    local r = call("records", {force = "team-1"})
    check("records: found", r.found == true)
    eq("records: names the force", r.force, "team-1")
    eq("records: label is the display name", r.label, "Team Ace")
    eq("records: kind defaults to any", r.kind, "any")
    eq("records: first counts what it holds now", r.first, 4)
    eq("records: fastest counts what it holds now", r.fastest, 3)
    eq("records: held counts each key once", r.held, 4)
    eq("records: finished counts every key it has an entry for", r.finished, 6)
    eq("records: never beat a standing time", r.set_fastest_ever, 0)
    eq("records: total is the held keys", r.total, 4)
    eq("records: all shown", r.shown, 4)
    eq("records: rows are newest first, across both tables",
        whats(r.rows), EXT .. ",electronics,automation," .. SCI0)

    local ext = by_what(r.rows, EXT)
    eq("records: an ext key is a milestone row", ext and ext.kind, "milestone")
    eq("records: holding first and fastest reads both", ext and ext.holds, "both")
    eq("records: whole hours leave as a number", ext and ext.elapsed_hours, 6)
    eq("records: online hours from the entry", ext and ext.online_hours, 3)
    local elec = by_what(r.rows, "electronics")
    eq("records: a tech row", elec and elec.kind, "tech")
    eq("records: first only", elec and elec.holds, "first")
    local sci = by_what(r.rows, SCI0)
    eq("records: a fraction leaves as a short string", sci and sci.elapsed_hours, "0.5")
    eq("records: online fraction too", sci and sci.online_hours, "0.25")
    check("records: no double leaks", whole_numbers(r))

    local tech = call("records", {force = "team-1", kind = "tech"})
    eq("records kind=tech: first", tech.first, 2)
    eq("records kind=tech: fastest", tech.fastest, 1)
    eq("records kind=tech: finished", tech.finished, 3)
    eq("records kind=tech: rows", whats(tech.rows), "electronics,automation")
    eq("records kind=tech: echoes the kind", tech.kind, "tech")

    local mile = call("records", {force = "team-1", kind = "milestone"})
    eq("records kind=milestone: held", mile.held, 2)
    eq("records kind=milestone: finished", mile.finished, 3)
    eq("records kind=milestone: rows include the ext key", whats(mile.rows), EXT .. "," .. SCI0)

    check("records: a competitive team carries no mark", r.noncompetitive == nil)
    storage.team_noncompetitive = {["team-3"] = true}   -- played with a handicap once
    local cat = call("records", {force = "Team Cat"})
    check("records: a handicapped team is marked noncompetitive", cat.noncompetitive == true)
    eq("records: a label resolves to the force", cat.force, "team-3")
    eq("records: one team's reply keeps its label", cat.label, "Team Cat")
    eq("records: took fastest only", cat.fastest, 1)
    eq("records: holds no first", cat.first, 0)
    eq("records: beat the standing time once", cat.set_fastest_ever, 1)
    eq("records: its row holds fastest", cat.rows[1] and cat.rows[1].holds, "fastest")
    eq("records: on its own clock, not game time", cat.rows[1] and cat.rows[1].elapsed_hours, 3)

    eq("records: 'team 2' resolves", call("records", {force = "team 2"}).force, "team-2")
    eq("records: limit cuts rows", #call("records", {force = "team-1", limit = 1}).rows, 1)
    eq("records: limit keeps the true total", call("records", {force = "team-1", limit = 1}).total, 4)
    eq("records: a bad limit falls back to the default",
        #call("records", {force = "team-1", limit = "lots"}).rows, 4)

    local all = call("records", {all = true, force = "team-2"})
    eq("records all: every claimed team, most held first", forces_of(all.teams), "team-1,team-2,team-3")
    eq("records all: total", all.total, 3)
    eq("records all: shown", all.shown, 3)
    eq("records all: held", all.teams[1].held, 4)
    eq("records all: finished", all.teams[1].finished, 6)
    eq("records all: first", all.teams[2].first, 2)
    eq("records all: fastest", all.teams[3].fastest, 1)
    -- The bridge prints force names as labels, so a label on every row of
    -- the table would cost bytes and tell the model nothing.
    check("records all: rows carry no label", all.teams[1].label == nil and all.teams[3].label == nil)
    check("records all: the mark rides on the row", all.teams[3].noncompetitive == true
        and all.teams[1].noncompetitive == nil)
    eq("records all: kind filter", call("records", {all = true, kind = "tech"}).teams[1].held, 2)

    local lean = call("records", {all = true, held_only = true})
    eq("records held_only: every team, most held first", forces_of(lean.teams), "team-1,team-2,team-3")
    eq("records held_only: the held count", lean.teams[1].held, 4)
    local keys = {}
    for key in pairs(lean.teams[3]) do keys[#keys + 1] = key end
    table.sort(keys)
    eq("records held_only: a row is force and held only", table.concat(keys, ","), "force,held")
    eq("records held_only: totals as the full table", lean.total, 3)
    eq("records held_only: kind filter", call("records", {all = true, held_only = true, kind = "tech"})
        .teams[1].held, 2)
    check("records held_only: means nothing without all", call("records", {force = "team-1", held_only = true})
        .rows ~= nil)
end

-- ─── set_fastest_ever: three teams, a known finishing order ────────────

do
    world{teams = {[1] = {start = 0}, [2] = {start = 4 * H}, [3] = {start = 6 * H}}}
    -- Per key, in tick order. elapsed = tick - start.
    finish("tech", "k4", 1, 3 * H)                    -- t1 3h, first
    finish("milestone", "science:x@100", 1, 5 * H)   -- t1 5h, first
    finish("tech", "k3", 2, 6 * H)                    -- t2 2h, first
    finish("tech", "k4", 2, 7 * H)                    -- t2 3h, equal: not a beat
    finish("tech", "k3", 1, 7 * H)                    -- t1 7h
    finish("milestone", "science:x@100", 2, 8 * H)   -- t2 4h, beats 5h
    finish("tech", "k3", 3, 8.5 * H)                  -- t3 2.5h, slower than 2h
    finish("milestone", "science:x@100", 3, 9 * H)   -- t3 3h, beats 4h
    finish("tech", "k1", 1, 10 * H)                   -- t1 10h, first
    finish("tech", "k5", 2, 10 * H)                   -- t2 6h, first
    finish("tech", "k5", 3, 10.5 * H)                 -- t3 4.5h, beats 6h
    finish("tech", "k1", 2, 11 * H)                   -- t2 7h, beats 10h
    finish("tech", "k1", 3, 12 * H)                   -- t3 6h, beats 7h
    game.tick = 20 * H

    local t1 = call("records", {force = "team-1"})
    local t2 = call("records", {force = "team-2"})
    local t3 = call("records", {force = "team-3"})
    eq("replay: the first finisher beats nothing", t1.set_fastest_ever, 0)
    eq("replay: beats count even after being beaten since", t2.set_fastest_ever, 2)
    eq("replay: every beat in tick order", t3.set_fastest_ever, 3)
    eq("replay: t1 still first on three", t1.first, 3)
    eq("replay: t1 kept the tie it set first", t1.fastest, 1)
    eq("replay: t2 holds fastest on one now", t2.fastest, 1)
    eq("replay: t2 finished all five", t2.finished, 5)
    eq("replay: t3 holds three fastest", t3.fastest, 3)
    eq("replay: t3 holds no first", t3.first, 0)

    local all = call("records", {all = true})
    eq("replay: all=true ties on held break by slot", forces_of(all.teams), "team-1,team-3,team-2")
end

do
    -- Same tick: the milestone poll visits teams in slot order, so the
    -- replay does too. t2 (9h) is processed first and t3 (7h) beats it.
    world{teams = {[2] = {start = 4 * H}, [3] = {start = 6 * H}}}
    finish("milestone", "science:y@200", 2, 13 * H)
    finish("milestone", "science:y@200", 3, 13 * H)
    local rec = storage.milestone_records["science:y@200"]
    eq("replay: same tick, the game's own first was the lower slot", rec.first.team, "team-2")
    eq("replay: same tick replays in slot order", call("records", {force = "team-3"}).set_fastest_ever, 1)
    eq("replay: the lower slot beat nothing", call("records", {force = "team-2"}).set_fastest_ever, 0)
end

-- ─── a released slot: the recomputed holder is the one reported ───────

do
    world{teams = {[1] = {start = 0}, [2] = {start = H / 2}, [3] = {start = 1.5 * H}}}
    finish("tech", "kx", 1, 2 * H)          -- t1 2h: first and fastest
    finish("tech", "kx", 2, 3.5 * H)        -- t2 3h
    finish("tech", "kx", 3, 4 * H)          -- t3 2.5h: slower than t1
    finish("milestone", "science:z@0", 1, 3 * H)   -- only t1
    game.tick = 5 * H
    eq("strip: before release t3 beat nothing", call("records", {force = "team-3"}).set_fastest_ever, 0)

    require("scripts.team_slots").release_team_slot("team-1")
    eq("strip: the slot is free", storage.team_pool[1], "available")
    eq("strip: first recomputed to the earliest survivor", storage.tech_records.kx.first.team, "team-2")
    eq("strip: fastest recomputed to the quickest survivor", storage.tech_records.kx.fastest.team, "team-3")
    check("strip: a key with no survivor is gone", storage.milestone_records["science:z@0"] == nil)

    local t2 = call("records", {force = "team-2"})
    eq("strip: t2 is reported first", t2.rows[1] and t2.rows[1].holds, "first")
    eq("strip: t2 first count", t2.first, 1)
    local t3 = call("records", {force = "team-3"})
    eq("strip: t3 is reported fastest", t3.rows[1] and t3.rows[1].holds, "fastest")
    eq("strip: the replay covers survivors only", t3.set_fastest_ever, 1)

    local gone = call("records", {force = "team-1"})
    check("strip: the released slot has no records", gone.found == false)
    eq("strip: and says why", gone.reason, require("scripts.agent_tools.team_lookup").UNCLAIMED)
    eq("strip: all=true leaves the free slot out", forces_of(call("records", {all = true}).teams),
        "team-2,team-3")
    eq("strip: chase sees t2 holding it", call("record_chase", {force = "team-2"}).held, 1)
end

-- ─── record_chase: the boundary, equal is out ─────────────────────────

do
    local NOW = 20 * H
    world{teams = {[1] = {start = 0}, [2] = {start = 0}, [3] = {start = NOW - 5 * H},
                   [4] = {start = NOW - 5 * H + 1}, [5] = {start = NOW - 2 * H},
                   [6] = {start = nil}}}
    finish("tech", "kb", 1, 5 * H)                       -- record 5h, t1
    finish("tech", "kb", 2, 9 * H)                       -- t2 slower, 9h
    finish("milestone", "science:x@1000", 1, 14 * H)    -- record 14h, t1
    -- A team whose clock is not running yet but which finished kb slower.
    -- The clock rule alone would call kb in reach; the entry rule must not.
    storage.tech_records.kb.entries["team-6"] = {team = "team-6", tick = 10 * H, elapsed = 7 * H}
    storage.milestone_records["science:never@100"] = {}   -- nobody finished it
    game.tick = NOW

    local t3 = call("record_chase", {force = "team-3"})
    eq("chase: clock equal to the record is out", t3.out_of_reach, 1)
    eq("chase: the other is in reach", t3.in_reach, 1)
    eq("chase: its clock", t3.elapsed_hours, 5)
    eq("chase: rows are the in-reach records", whats(t3.rows), "science:x@1000")
    eq("chase: names the holder", t3.rows[1] and t3.rows[1].holder, "team-1")
    eq("chase: the record time", t3.rows[1] and t3.rows[1].record_hours, 14)
    eq("chase: hours left before the clock passes it", t3.rows[1] and t3.rows[1].hours_left, 9)
    check("chase: a running clock is not flagged", t3.clock_started == nil)

    local t4 = call("record_chase", {force = "team-4"})
    eq("chase: one tick under the record is in", t4.in_reach, 2)
    eq("chase: closing soonest first", whats(t4.rows), "kb,science:x@1000")
    eq("chase: total is the in-reach count", t4.total, 2)

    local t2 = call("record_chase", {force = "team-2"})
    eq("chase: finished slower and clock past, both out", t2.out_of_reach, 2)
    eq("chase: nothing in reach", t2.in_reach, 0)
    eq("chase: no rows", #t2.rows, 0)

    eq("chase: the holder counts held", call("record_chase", {force = "team-1"}).held, 2)

    local t6 = call("record_chase", {force = "team-6"})
    eq("chase: a key finished slower is out even with the clock under it", t6.out_of_reach, 1)
    eq("chase: the other is in reach", t6.in_reach, 1)
    check("chase: a staged team says its clock has not started", t6.clock_started == false)
    eq("chase: and reads zero", t6.elapsed_hours, 0)

    local t5 = call("record_chase", {force = "team-5", kind = "tech"})
    eq("chase kind=tech: only research", whats(t5.rows), "kb")
    eq("chase kind=tech: hours left", t5.rows[1] and t5.rows[1].hours_left, 3)
    check("chase: no double leaks", whole_numbers(t4) and whole_numbers(t5))
end

-- ─── entries with no online_elapsed still produce rows ────────────────

do
    world{teams = {[1] = {start = 0}, [2] = {start = 0}, [3] = {start = 4.75 * H}}}
    -- A save from before entries existed: first and fastest only, no online.
    storage.tech_records["old-tech"] = {
        first   = {team = "team-1", tick = H,     elapsed = H},
        fastest = {team = "team-2", tick = 2 * H, elapsed = H / 2},
    }
    -- A save from before online time: entries, but online_elapsed nil.
    finish("milestone", "science:z@0", 1, 3 * H, nil)
    game.tick = 5 * H

    -- An entry naming a team but carrying no times: skipped, never compared.
    storage.tech_records["garbled"] = {entries = {["team-1"] = {team = "team-1"}}}

    local t1 = call("records", {force = "team-1"})
    eq("old saves: rows from both shapes", whats(t1.rows), "science:z@0,old-tech")
    eq("old saves: first from the bare record", t1.first, 2)
    eq("old saves: finished counts the backfilled entry", t1.finished, 2)
    local row = by_what(t1.rows, "old-tech")
    eq("old saves: elapsed still reported", row and row.elapsed_hours, 1)
    check("old saves: online absent, not zero", row and row.online_hours == nil)
    check("old saves: absent on an entry without it", t1.rows[1].online_hours == nil)

    local t2 = call("records", {force = "team-2"})
    eq("old saves: fastest from the bare record", t2.rows[1] and t2.rows[1].holds, "fastest")
    eq("old saves: the replay reads first and fastest", t2.set_fastest_ever, 1)

    -- Only a fastest, no first: no writer leaves this, but a read that
    -- walks first-then-fastest must not stop at the missing first.
    storage.tech_records["half"] = {fastest = {team = "team-2", tick = 4 * H, elapsed = 4 * H}}
    local half = call("records", {force = "team-2"})
    eq("half record: its finisher still counts it", half.finished, 2)
    eq("half record: and holds it", half.fastest, 2)
    storage.tech_records["half"] = nil

    local t3 = call("record_chase", {force = "team-3"})
    eq("old saves: chase reads the bare record", t3.in_reach, 2)
    eq("old saves: closing soonest", whats(t3.rows), "old-tech,science:z@0")
    eq("old saves: quarter hour left", t3.rows[1] and t3.rows[1].hours_left, "0.25")
end

-- ─── first-only milestones: first records, never fastest ──────────────

do
    -- A mod's milestone, registered and reported through the real mts-v1
    -- interface into the real milestones engine, so these are the keys the
    -- engine writes. One cell is first-only; ten cells is first and fastest.
    world{teams = {[1] = {start = 0}, [2] = {start = H}, [3] = {start = 2 * H},
                   [4] = {start = 3.5 * H}}}
    require("milestones.engine")
    local function report_cells(slot, tick, count)
        game.tick = tick
        remote.call("mts-v1", "report_milestone", "team-" .. slot, "cells", count)
    end
    remote.call("mts-v1", "register_milestone",
        {category = "cells", verb = "unlock", noun = "cell", first_threshold = 1, thresholds = {10}})
    report_cells(1, 2 * H, 1)          -- t1 2h: first to one cell
    report_cells(2, 2.5 * H, 1)        -- t2 1.5h: quicker, and not a record
    report_cells(1, 3 * H, 10)         -- t1 3h: first to ten
    report_cells(2, 3.5 * H, 10)       -- t2 2.5h: fastest to ten
    game.tick = 4 * H

    local ONE, TEN = "ext:cells@1", "ext:cells@10"
    -- Saves already hold both keys in this shape, so the format must not move.
    check("first-only: the reached mark keeps its key",
        ((storage.milestone_reached["team-1"] or {})["ext:cells"] or {})[1] == true)
    local stored = storage.milestone_records[ONE]
    eq("first-only: the engine still stores a fastest on it", stored and stored.fastest.team, "team-2")
    eq("first-only: ten cells is a record race", storage.milestone_records[TEN].fastest.team, "team-2")

    local t1 = call("records", {force = "team-1"})
    eq("first-only: its first holder holds it as first", by_what(t1.rows, ONE) and by_what(t1.rows, ONE).holds,
        "first")
    eq("first-only: t1 first on both", t1.first, 2)
    eq("first-only: t1 holds no fastest", t1.fastest, 0)

    local t2 = call("records", {force = "team-2"})
    eq("first-only: the quicker team holds nothing on it", by_what(t2.rows, ONE), nil)
    eq("first-only: t2 fastest counts ten cells only", t2.fastest, 1)
    eq("first-only: t2 held", t2.held, 1)
    eq("first-only: t2 finished both", t2.finished, 2)
    eq("first-only: beating its time breaks no record", t2.set_fastest_ever, 1)

    local all = call("records", {all = true})
    eq("first-only: all=true agrees", all.teams[2].fastest, 1)
    eq("first-only: all=true ranks by what is held", forces_of(all.teams), "team-1,team-2,team-3,team-4")
    eq("first-only: held_only agrees", call("records", {all = true, held_only = true}).teams[2].held, 1)

    -- t4's clock (0.5h) is under the first-only key's stored fastest (1.5h):
    -- a race would call it in reach, but first is already gone.
    local t4 = call("record_chase", {force = "team-4"})
    eq("first-only chase: never in reach", t4.out_of_reach, 1)
    eq("first-only chase: ten cells still is", t4.in_reach, 1)
    eq("first-only chase: rows are the race", whats(t4.rows), TEN)
    local c1 = call("record_chase", {force = "team-1"})
    eq("first-only chase: its holder holds it, and first on ten", c1.held, 2)
    eq("first-only chase: nothing out for the holder", c1.out_of_reach, 0)
    local c2 = call("record_chase", {force = "team-2"})
    eq("first-only chase: the quicker team holds ten cells only", c2.held, 1)
    eq("first-only chase: one cell is out for it", c2.out_of_reach, 1)

    -- A mod's milestone with no first threshold is a race like any other.
    remote.call("mts-v1", "register_milestone", {category = "ores", noun = "ore", thresholds = {5}})
    game.tick = 5 * H
    remote.call("mts-v1", "report_milestone", "team-1", "ores", 5)
    eq("no first threshold: first and fastest", by_what(call("records", {force = "team-1"}).rows,
        "ext:ores@5").holds, "both")
end

return report
