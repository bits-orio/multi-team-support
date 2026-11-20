-- tests/test_shadow_race.lua
-- Headless tests for Shadow Race's recording core: the timeline arithmetic
-- (shadow_race/timeline.lua), the recorder's points and marks, and the
-- archive's retention and pinning through the real team_slots release.

local W = require("tests.agent_world")
local mock = W.mock
local world = W.world

local report, check, eq = W.new_report()

local timeline = require("shadow_race.timeline")

-- ─── timeline: pure arithmetic ────────────────────────────────────────

do
    --            t=100 s=10, t=200 s=30, stall to t=400, t=500 s=50
    local run = { 100, 10, 200, 30, 400, 30, 500, 50 }
    eq("timeline: no score before the first point", timeline.score_at(run, 50), 0)
    eq("timeline: score on a point", timeline.score_at(run, 200), 30)
    eq("timeline: score between points", timeline.score_at(run, 150), 20)
    eq("timeline: score holds through a stall", timeline.score_at(run, 300), 30)
    eq("timeline: score after the last point", timeline.score_at(run, 900), 50)
    eq("timeline: zero is reached at the start", timeline.time_at(run, 0), 0)
    eq("timeline: time of a score between points", timeline.time_at(run, 20), 150)
    eq("timeline: a stalled score is reached when it was first hit", timeline.time_at(run, 30), 200)
    eq("timeline: time past the stall", timeline.time_at(run, 40), 450)
    check("timeline: a score never reached has no time", timeline.time_at(run, 51) == nil)
    check("timeline: an empty run reaches nothing", timeline.time_at({}, 1) == nil)
    local t, s = timeline.last(run)
    eq("timeline: last time", t, 500)
    eq("timeline: last score", s, 50)

    -- A is at score 20 at t=100; the rival got there at t=150: 50 ahead.
    eq("gap: ahead of a run that got here later", timeline.gap({ 100, 20 }, 100, 20, run), 50)
    -- A is at score 20 at t=250; the rival was there at 150: 100 behind.
    eq("gap: behind a run that got here sooner", timeline.gap({ 250, 20 }, 250, 20, run), -100)
    -- A stalls at 20: the gap keeps growing with A's clock.
    eq("gap: standing still loses time", timeline.gap({ 250, 20 }, 400, 20, run), -250)
    -- A passed the archived rival's final 50 at t=300; the rival took 500.
    eq("gap: past the end of an archived run", timeline.gap({ 300, 50, 600, 80 }, 700, 80, run), 200)
    check("gap: and that split is final", select(2, timeline.gap({ 300, 50, 600, 80 }, 700, 80, run)) == true)
    -- A reaches the archived run's last score, 50, at t=520: 20 slower, for good.
    eq("gap: reaching an archived run's last score fixes the split",
        timeline.gap({ 520, 50 }, 900, 50, run), -20)
    check("gap: final from that moment", select(2, timeline.gap({ 520, 50 }, 900, 50, run)) == true)
    check("gap: a split mid-run is not final", select(2, timeline.gap({ 250, 20 }, 250, 20, run)) == nil)
    -- A live rival standing on A's score is level, not final.
    eq("gap: level with a live rival on the same score",
        timeline.gap({ 520, 50 }, 900, 50, run, 950, 50), 0)
    -- A live rival younger than A: at its t=120 it has 10; A had 10 at t=60.
    eq("gap: ahead of a younger live team",
        timeline.gap({ 60, 10, 300, 40 }, 300, 40, { 100, 10 }, 120, 10), 60)
    -- The same team still on 10 later: A's lead grows with the rival's clock.
    eq("gap: a stalled live rival falls further back",
        timeline.gap({ 60, 10, 300, 40 }, 500, 40, { 100, 10 }, 320, 10), 260)
    -- The rival sat on 30 from t=200 to t=400.
    eq("gap: level while the rival stood on this score", timeline.gap({ 300, 30 }, 300, 30, run), 0)
    eq("gap: behind once the rival moved on", timeline.gap({ 300, 30 }, 425, 30, run), -25)
    -- The rival had no science until t=100.
    eq("gap: level before the rival's first science", timeline.gap({}, 50, 0, run), 0)
    eq("gap: behind after it", timeline.gap({}, 130, 0, run), -30)
    eq("timeline: when a stalled score was left", timeline.time_left(run, 30), 400)
    check("timeline: the final score is never left", timeline.time_left(run, 50) == nil)
    -- Between samples a live run is further on than its last point. A has
    -- 10 recorded at t=100 and stands at 60 at t=300: it crossed the
    -- archived run's last score, 50, at t=260, against the run's 500.
    eq("gap: a score reached since the last sample has a time",
        timeline.gap({ 100, 10 }, 300, 60, run), 240)
    -- A live rival with 10 recorded at t=100, now on 50 at t=300, passed
    -- A's 30 at its t=200. A is at t=250: 50 behind.
    eq("gap: a live rival's progress since its last sample counts",
        timeline.gap({ 250, 30 }, 250, 30, { 100, 10 }, 300, 50), -50)
    check("gap: nothing to compare before any science", timeline.gap({}, 50, 0, {}, 40, 0) == nil)

    local ahead, key = timeline.mark_gap({ a = 10, b = 50 }, { a = 30, b = 90, c = 100 })
    eq("mark gap: taken from the latest shared mark", ahead, 40)
    eq("mark gap: and names it", key, "b")
    check("mark gap: none without a shared mark", timeline.mark_gap({ a = 1 }, { b = 2 }) == nil)
end

-- ─── recorder and archive through the real release ────────────────────

--- A technology as the research events hand it over.
local function tech(force_name, name, units, packs, opts)
    opts = opts or {}
    local ingredients = {}
    for i = 1, packs do ingredients[i] = { name = "pack-" .. i, amount = 1 } end
    return {
        valid = true, name = name, force = game.forces[force_name],
        research_unit_count = units, research_unit_ingredients = ingredients,
        researched = opts.researched ~= false, level = opts.level or 1,
        prototype = { level = 1, research_unit_count = units, research_unit_ingredients = ingredients },
    }
end

do
    world{max_teams = 4, tick = 1000}
    require("events.player_force").register()
    local team_slots = require("scripts.team_slots")
    local recorder   = require("shadow_race.recorder")
    local archive    = require("shadow_race.archive")
    local ann = mock.add_live_player{name = "Ann"}
    local bob = mock.add_live_player{name = "Bob"}

    --- One whole run for `player`: claim, research worth `units`, leave.
    local function play_run(player, units)
        local force_name = team_slots.claim_team_slot(player)
        recorder.open(force_name, game.tick)
        recorder.add_member(force_name, player.index)
        if units > 0 then
            game.tick = game.tick + 600
            recorder.on_research_finished{ research = tech(force_name, "automation", units, 1) }
        end
        game.tick = game.tick + 600
        team_slots.remove_from_team(player)
        return force_name
    end

    -- A live run: points, marks, script grants.
    local force_name = team_slots.claim_team_slot(ann)
    local run = recorder.open(force_name, game.tick)
    recorder.add_member(force_name, ann.index)
    recorder.add_member(force_name, bob.index)
    game.tick = 1600
    recorder.on_research_finished{ research = tech(force_name, "gifted", 500, 1), by_script = true }
    eq("recorder: a script grant adds no score", run.score, 0)
    recorder.on_research_finished{ research = tech(force_name, "automation", 10, 1) }
    eq("recorder: units times packs", run.score, 10)
    eq("recorder: the point is on the team's clock", run.points[1], 600)
    eq("recorder: a finished technology is a mark", run.marks["tech:automation"], 600)
    game.tick = 2200
    recorder.on_research_finished{ research = tech(force_name, "logistics", 20, 2) }
    eq("recorder: two packs per unit count double", run.score, 50)
    -- An infinite level: the event already describes the next level, so the
    -- cost comes from what was noted while it was current.
    local endless = tech(force_name, "endless", 100, 1, { researched = false })
    recorder.on_research_started{ research = endless }
    endless.research_unit_count, endless.level = 200, 2
    game.tick = 2800
    recorder.on_research_finished{ research = endless }
    eq("recorder: an infinite level costs what it cost, not the next one", run.score, 150)
    check("recorder: a level with more to go is not a mark", run.marks["tech:endless"] == nil)
    recorder.arrive(force_name, "nauvis")
    check("recorder: the planet a run starts on is not an arrival", run.marks["planet:nauvis"] == nil)
    recorder.arrive(force_name, "vulcanus")
    recorder.arrive(force_name, "nauvis")
    eq("recorder: another planet is", run.marks["planet:vulcanus"], 1800)
    check("recorder: and coming home never is", run.marks["planet:nauvis"] == nil)
    recorder.mark(force_name, "rocket")
    game.tick = 3400
    recorder.mark(force_name, "rocket")
    eq("recorder: only the first of a mark counts", run.marks.rocket, 1800)

    -- Release: the run goes to both members.
    team_slots.remove_from_team(ann)
    check("archive: the live run is gone", recorder.run_of(force_name) == nil)
    local anns = archive.runs_of(ann.index)
    eq("archive: the leader keeps the run", #anns.recent, 1)
    eq("archive: a member who was on the team keeps it too", #archive.runs_of(bob.index).recent, 1)
    local first = anns.recent[1]
    eq("archive: the run remembers its leader", first.leader, "Ann")
    eq("archive: and its length", first.ended, 2400)
    eq("archive: and its score", first.score, 150)
    local last_t = first.points[#first.points - 1]
    eq("archive: the timeline runs to the end of the run", last_t, 2400)

    -- A run with nothing in it is not kept.
    play_run(ann, 0)
    eq("archive: an empty run is dropped", #archive.runs_of(ann.index).recent, 1)

    -- Retention: the last three, plus the pin.
    check("pin: a recent run can be pinned", archive.pin(ann.index, first.id))
    check("pin: someone else's run cannot", not archive.pin(ann.index, 9999))
    play_run(ann, 20); play_run(ann, 30); play_run(ann, 40)
    local now = archive.runs_of(ann.index)
    eq("retention: three recent runs", #now.recent, 3)
    eq("retention: newest first", now.recent[1].score, 40)
    eq("retention: the pinned run outlives the recent list", now.pinned and now.pinned.id, first.id)
    check("retention: Bob still has the shared run", archive.runs_of(bob.index).recent[1].id == first.id)
    check("pin: a run that left the recent list cannot be pinned again",
        not (archive.unpin(ann.index) or archive.pin(ann.index, first.id)))

    -- A pin moves to another recent run; the old one goes once nobody keeps it.
    local newest = archive.runs_of(ann.index).recent[1]
    check("pin: moves to another recent run", archive.pin(ann.index, newest.id))
    archive.forget_player(bob.index)
    check("retention: a run nobody keeps is deleted", storage.shadow_race.runs[first.id] == nil)
    archive.forget_player(ann.index)
    check("retention: a removed player keeps nothing", next(storage.shadow_race.runs) == nil)
end

-- ─── rivals, standings and auto-chase with two teams ──────────────────

do
    world{max_teams = 4, tick = 1000}
    require("events.player_force").register()
    local team_slots = require("scripts.team_slots")
    local recorder   = require("shadow_race.recorder")
    local archive    = require("shadow_race.archive")
    local rivals     = require("shadow_race.rivals")
    local standings  = require("shadow_race.standings")
    local hooks      = require("shadow_race.hooks")
    local ann = mock.add_live_player{name = "Ann"}
    local bob = mock.add_live_player{name = "Bob"}

    --- Claim a team the way the game does: the clock event opens the run.
    local function claim(player)
        local force_name = team_slots.claim_team_slot(player)
        hooks.on_clock_started{ force_name = force_name, start_tick = game.tick }
        hooks.on_player_joined{ force_name = force_name, player_index = player.index }
        return force_name
    end
    local function research(force_name, name, units)
        recorder.on_research_finished{ research = tech(force_name, name, units, 1) }
    end

    local ann_team = claim(ann)
    game.tick = 1600
    research(ann_team, "automation", 10)         -- Ann: 10 at 0:10
    game.tick = 2200
    local bob_team = claim(bob)                  -- Bob starts 20 s later
    check("rivals: a new team chases nothing", rivals.standing(bob_team) == nil)
    check("rivals: a team cannot chase itself",
        not rivals.set(bob_team, { kind = "team", force = bob_team, start = 2200 }))
    check("rivals: chase a team playing now",
        rivals.set(bob_team, { kind = "team", force = ann_team, start = 1000 }))
    check("rivals: the wrong start names nobody",
        not rivals.set(bob_team, { kind = "team", force = ann_team, start = 999 }))

    -- Bob, 300 ticks in with no science; Ann had none until her tick 600.
    game.tick = 2500
    eq("rivals: level before the shadow's first science", rivals.standing(bob_team).gap, 0)
    game.tick = 3100                             -- Bob at 900, Ann left zero at 600
    eq("rivals: behind once the shadow moved on", rivals.standing(bob_team).gap, -300)

    local rows, place, total = standings.rows(bob_team, bob.index)
    eq("standings: one run to chase", #rows, 1)
    eq("standings: second behind it", place, 2)
    eq("standings: of two", total, 2)
    check("standings: it is marked as the team's shadow", rows[1].current == true)
    check("standings: a team playing now is not a recording", rows[1].recorded == false)

    -- Ann leaves: Bob's shadow becomes her archived run without a gap.
    team_slots.remove_from_team(ann)
    local choice = rivals.choice_of(bob_team)
    eq("rivals: a released team's chasers follow its archived run", choice and choice.kind, "run")
    eq("rivals: still the same split", rivals.standing(bob_team).gap, -300)
    check("standings: an archived run is a recording",
        standings.rows(bob_team, bob.index)[1].recorded == true)

    -- Auto-chase picks the nearest run ahead, and lets go once it is passed.
    check("auto: can be chosen", rivals.set(bob_team, { kind = "auto" }))
    check("auto: nothing passed on the first look", standings.retarget(bob_team) == nil)
    eq("auto: targets the run ahead", rivals.choice_of(bob_team).target.id, choice.id)
    game.tick = 3400
    research(bob_team, "automation", 10)
    research(bob_team, "logistics", 20)           -- Bob: 30, past Ann's 10
    local passed = standings.retarget(bob_team)
    eq("auto: says which run was passed", passed and passed.id, choice.id)
    check("auto: nothing left ahead", rivals.choice_of(bob_team).target == nil)
    local leading = rivals.standing(bob_team)
    check("auto: the team leads every shadow", leading and leading.auto == true and leading.label == nil)
    rows, place = standings.rows(bob_team, bob.index)
    eq("standings: first once the run is passed", place, 1)
    check("standings: the passed run's split is final", rows[1].final == true)
    -- Bob reached Ann's 10 at his 1200; Ann at her 600: 600 slower, for good.
    eq("standings: and it is the time to its last score", rows[1].gap, -600)

    -- A pinned run is what the player's next team chases from the start.
    local ann_run = archive.runs_of(ann.index).recent[1]
    check("pin: Ann pins her run", rivals.pin(ann.index, ann_run.id))
    game.tick = 4000
    local again = claim(ann)
    local start = rivals.choice_of(again)
    eq("rivals: a new team starts on its leader's pinned run", start and start.id, ann_run.id)

    -- Without a pin, the next team takes up what the last one chased.
    team_slots.remove_from_team(bob)              -- Bob's team chased auto
    game.tick = 5000
    local bobs_next = claim(bob)
    eq("rivals: a new team takes up its leader's last choice",
        (rivals.choice_of(bobs_next) or {}).kind, "auto")

    -- The whole archive is capped: the oldest unpinned runs go first.
    local s = storage.shadow_race
    for id = 1000, 1000 + archive.MAX_RUNS + 4 do
        s.runs[id] = { id = id, members = {}, marks = {}, points = { 10, 1 }, score = 1, ended = 10 }
        s.kept[5000 + id] = { recent = { id } }
    end
    archive.pin(ann.index, ann_run.id)   -- any change to what is kept runs the collector
    local total = 0
    for _ in pairs(s.runs) do total = total + 1 end
    eq("cap: the archive holds no more than its cap", total, archive.MAX_RUNS)
    check("cap: a pinned run outlives older unpinned ones", s.runs[ann_run.id] ~= nil)
    check("cap: the newest run is kept", s.runs[1000 + archive.MAX_RUNS + 4] ~= nil)

    -- A player's own display switch.
    check("hud: shown by default", not rivals.is_hidden(bob.index))
    rivals.set_hidden(bob.index, true)
    check("hud: hidden for the player who asked", rivals.is_hidden(bob.index))
    check("hud: and only for them", not rivals.is_hidden(ann.index))

    -- The splits window is the player's to open.
    check("splits window: closed by default", not rivals.wants_splits(bob.index))
    rivals.set_splits(bob.index, true)
    check("splits window: open for the player who opened it", rivals.wants_splits(bob.index))
    check("splits window: and only for them", not rivals.wants_splits(ann.index))
    rivals.set_splits(bob.index, false)
    check("splits window: closed again on request", not rivals.wants_splits(bob.index))
end

-- ─── splits: the two runs' marks as one list ──────────────────────────

do
    local splits = require("shadow_race.splits")
    local mine  = { marks = { ["tech:a"] = 600, ["tech:c"] = 4000, ["tech:mine-only"] = 900 } }
    local rival = { marks = { ["tech:a"] = 1200, ["tech:b"] = 1800, ["tech:c"] = 3000, ["rocket"] = 9000 } }
    local rows = splits.rows(mine, rival)
    local order = {}
    for i, row in ipairs(rows) do order[i] = row.key end
    eq("splits: every mark of both runs, in the order of the race",
        table.concat(order, " "), "tech:mine-only tech:a tech:b tech:c rocket")
    eq("splits: a shared mark carries both times", rows[2].theirs - rows[2].mine, 600)

    -- At 2000 on the team's clock: b is lost (the shadow had it at 1800),
    -- c is the team's already, the rocket is the next one open.
    check("splits: a mark the shadow passed is no longer open", not splits.is_open(rows[3], 2000))
    eq("splits: the first open mark", rows[splits.next_index(rows, 2000)].key, "rocket")
    eq("splits: before the shadow's time the mark is still open", rows[splits.next_index(rows, 1500)].key, "tech:b")
    check("splits: nothing open once the clock is past every mark", splits.next_index(rows, 9000) == nil)

    local gained, lost = splits.swings(rows)
    check("splits: no stretch gained here", gained == nil)
    eq("splits: the stretch that lost the most", lost and lost.change, -1600)

    local text = splits.export(mine, rival, 5400, "Team 01", "ann (2:30)")
    local lines = {}
    for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
    eq("export: the team's line has its clock", lines[2], "you\tTeam 01\t0:01:30.00")
    eq("export: a shared mark, ahead reads minus", lines[7], "tech:a\t0:00:10.00\t0:00:20.00\t-0:00:10.00")
    eq("export: a lost mark has no time of the team's", lines[8], "tech:b\t\t0:00:30.00\t")
    eq("export: behind reads plus", lines[9], "tech:c\t0:01:06.67\t0:00:50.00\t+0:00:16.67")
end

return report
