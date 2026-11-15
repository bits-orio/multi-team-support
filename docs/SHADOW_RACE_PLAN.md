# Shadow Race: design

Status: built and tested on the rig, not yet released. The player-facing
name is Shadow Race: a recorded run is a shadow, and a team chases another
team's shadow or the shadow of one of its members' earlier runs.

Shadow Race records a timeline of every team's run and lets a player race a
recorded run: their own earlier runs or another team's. The HUD shows, at
equal elapsed time, how far ahead or behind the player's team is.

## Terms

- **Run**: one team's play from the moment its clock starts to the release of
  its slot. One run per incarnation (see CONTEXT.md).
- **Live run**: the run of a team that holds a slot now.
- **Archived run**: a run kept after its slot was released.
- **Shadow**: the run a team is chasing. The code calls it the rival.
- **Mark**: a milestone on a run's timeline, with the elapsed time it happened.
- **Score**: the run's continuous progress number.
- **Gap**: the time between two runs, shown as "3:10 ahead" or "3:10 behind".

## What MTS does today (read from the code)

- A restart is a leave followed by a new claim. The last member leaving
  disbands the team, deletes its surfaces and releases the slot. The new
  claim takes the lowest free slot, which can be a different `team-N`.
- Releasing a slot strips the team from every record and deletes its research
  ticks (`team_slots.wipe_slot_state`). Nothing about a finished run survives
  today, so Shadow Race keeps its own archive.
- A slot is reused by other people, so an archived run belongs to players,
  not to a force name.
- The team clock (`storage.team_clock_start`) starts at the claim, or at
  Start Playing under Staged Start. Records use it. Shadow Race uses it too,
  so splits match the Awards times.
- Vanilla and Space Age team surfaces share one seed per planet, so a
  restarted team gets the same terrain. Not yet checked for MTS Dimension
  Warp, VoidBlock and Platformer starts. This matters only for the later
  ghost engineer and ghost factory.

## Decisions

| Topic | Decision |
|---|---|
| Ownership | A player's previous runs are the archived runs they were a member of at any point. |
| Departed teams | Their archived runs stay raceable and appear in standings, labelled "previous run of <leader>". |
| Clock | The Records clock: server time since the team's clock started. |
| Announcements | Notable marks only. The splits window lists every mark. |
| Upcoming panel | The shadow's next few marks, each with a live countdown. |
| Retention | Per player: the last 3 runs plus the player's pinned run. A run is deleted once no member retains it. The whole archive holds at most 200 runs; over that, the oldest unpinned runs go first. |
| Pinned run | Chosen by the player, never computed. A player can pin any of their last 3 runs; it then stays kept after it leaves the last 3. Pinning another run replaces it. The pin belongs to the player, so it survives restarts. |
| Rival is per team | A team has one rival. Any member can change it, and it changes for every member. |
| Rival memory | A new team starts with its leader's pinned run as rival. Without a pin it starts with the rival the leader's previous team had. |
| Hiding timings | Not offered. The Awards and research panels already show every team's times. |
| Admin option | One admin flag, on by default, in the existing admin flags panel. It controls what players see. Recording always runs. |
| Individual HUD | A second admin flag lets each player hide and show the race HUD for themselves. |

## Score

Score is the science a run has put into research:

    score = sum over finished research of (units x packs per unit)
          + the same for the research in progress x its progress

Measured on the rig (Factorio 2.1.23, headless, real labs):

- `force.research_progress` moves continuously and matched the packs the labs
  consumed (2490 expected, 2500 counted).
- A trigger technology has 1 unit and no ingredients, so it adds 0 to the
  score. Trigger technologies are marks.
- In `on_research_finished` for an infinite technology, `level` and
  `research_unit_count` already describe the next level (finishing a 2000
  unit level reported 4000). The cost of the level that finished is therefore
  captured when the research starts.
- Cancelling research keeps its progress in `saved_progress`. The recorded
  score never goes down; it holds its value until the team passes it again.
- Research granted by script adds nothing, the same rule Records use.

The score comes from two engine events and one property read per team per
sample. It never reads production statistics.

## Recording

A run holds:

- `points`: pairs of (elapsed seconds, score). One point at every finished
  research, plus a periodic sample while research is in progress. Between
  points the score is interpolated.
- `marks`: (key, elapsed seconds), in order. Keys:
  - `tech:<name>` for every finished technology
  - `pack:<item>` for the first of each science pack the labs accept
  - `rocket` for the first rocket
  - `planet:<base planet>` for the first arrival on each planet. The planet
    a run starts on is its home and is never an arrival.
- `leader`, `members`, the team name at the end, and the start tick.

Everything is derived from prototypes, so it follows the installed mods.
**Notable** marks are `pack`, `rocket` and `planet` marks, plus technologies
that unlock a science pack recipe, a space location or the rocket silo.

Recording needs no setup and does not depend on the run finishing. A run is
usable as a rival from its first point.

Size, measured on the rig: a run with 600 samples and 250 marks, about 40
hours of play, is about 14 KB. A sample is taken every 5 minutes.

### Lifecycle

| Moment | What happens |
|---|---|
| Team clock starts | A live run opens. |
| Player joins or leaves | The run's member list is updated. |
| Slot released | The run is archived, before MTS wipes the slot. A run with no score and no marks is dropped. Retention then runs for each member. |
| Player removed from the game | They leave every member list; runs nobody retains are deleted. |
| MTS updated on an existing save | Each live team's run is rebuilt from `tech_research_ticks` and the pack records MTS already holds. Technologies a team held when its clock started are skipped, as script grants. |
| Admin turns the feature off | The button, the picker and every race HUD go away. Recording continues, so no run ever has a hole. |
| Admin turns it on again | The button returns, and every team is chasing what it chased before. |

## Gap

For the team's run A at elapsed time `t` and shadow B:

1. Take A's score now. B held that score from the moment it reached it until
   it moved on. Before that stretch A is ahead by the time left until B got
   there; inside it the two are level; after it A is behind by the time
   since B moved on.
2. If B never reached that score (an archived run that ended, or a live team
   younger than A), the roles swap: take B's last score and find when A
   reached it. Against a live B, A is ahead by B's clock minus that time.
   Against an archived B the split is B's time to its last score minus A's,
   and it is final: it cannot change again.
3. While both scores are 0 (before the first lab research), the gap comes
   from the last mark both runs share, like a speedrun split.

Each lookup is a binary search in the shadow's points, so the once-a-second
update does not grow with the factory and barely with the length of the run.

## Choosing a shadow

Every member of a team sees one small clock button inside the team clock
chip. It opens the Shadow Race window. A team that is chasing nothing sees
nothing else.

The shadow belongs to the team. Any member can set or change it, the team is
told who changed it, and every member's display follows. Whether a member
can hide the display for themselves is a second admin flag, in the manner of
the individual chat flag. With it on, each member can hide the display and
show it again from the window, and the choice is remembered per player. With
it off, the display is the same for the whole team.

The window is the standings and the picker in one list:

- The team's place: "Your team is 4 of 9", among every run it can be
  compared with.
- The pace line: science per minute for the team and its shadow, over the
  last 10 minutes and the last hour of the team's clock.
- **Auto-chase**: always the nearest run ahead. Passing it tells the team and
  moves the target to the next one up. With nothing ahead the display reads
  "Ahead of every shadow". At the start of a run nothing is ahead yet (the
  team is level with every run, or has nothing to compare), so the target
  is the run whose first mark comes latest: the first one the team meets.
- Every other team playing now, every kept run of the team's members, and
  the nearest runs of teams that have left (8 ahead, 4 behind), ranked by
  their split against the team right now. Each has a Chase button; a
  player's own last 3 runs have a Pin button.

A run the team has gone beyond is ranked below the team. Its split is the
time the team took to its last score against the time it took, and is shown
as final.

Switching shadow resets nothing. Every split is computed from the two
timelines on demand. "Stop chasing" clears the team's shadow.

## While chasing

- **Split line** under the team clock: "3:10 behind · Team Red", refreshed
  once a second on the existing HUD pass.
- **Splits window**: every mark of the team's run beside the shadow's,
  in the order of the race. It is the report and the "what comes next"
  panel in one. A decided mark shows both times and the split; a lost one
  (the team's clock passed the shadow's time for it) says so; the next
  five still open count down on the team's clock. The list shows five rows
  and scrolls, and moves itself to the first open mark whenever the race
  moves on. It is there from the moment the team's clock starts and
  stays until the player closes it; the Shadow Race window brings it
  back, and the choice is remembered per player. It never goes away on
  its own: a team that has passed every run keeps the splits against the
  last one, and a team chasing nothing sees its own times.
- **Export**: the splits window puts the list as tab-separated text in a
  selected box, for Ctrl+C. The game gives a mod no way to write the
  clipboard itself.
- **Announcements**, to the team's members, when the shadow's timeline
  reaches a notable mark at the team's elapsed time. For a live shadow
  behind the team's clock, the announcement fires when it happens.

## Module shape

A folder `shadow_race/` at the repo root, like `milestones/`. It reads MTS
through a narrow seam so it can be split out later:

- The mts-v1 events: clock started, player joined.
- Engine events: research started, research finished, rocket launched,
  player changed surface.
- One call from `team_slots.release_team_slot`, before the wipe, for the
  leader and team name.
- One call from the science milestone check for `pack` marks.
- The existing 60 tick HUD pass, the 18000 tick pass for samples, and the
  admin flags table.

MTS fans these out from its existing registrations, because Factorio keeps
one handler per event per mod.

    shadow_race/timeline.lua    pure: score at time, time at score, gap
    shadow_race/score.lua       research cost and progress
    shadow_race/recorder.lua    live runs: points and marks
    shadow_race/archive.lua     archiving, retention, the cap, rebuild
    shadow_race/marks.lua       notable marks, their order and labels
    shadow_race/compare.lua     gap and pace between a live run and another
    shadow_race/rivals.lua      the team's shadow, pins, per-player display
    shadow_race/standings.lua   ranking every run, auto-chase target
    shadow_race/announcer.lua   mark playback and passing messages
    shadow_race/hooks.lua       the calls MTS makes into the module
    shadow_race/gui/chip.lua     button and split line in the clock chip
    shadow_race/gui/picker.lua   the Shadow Race window
    shadow_race/splits.lua       the two runs' marks as one list, and as text
    shadow_race/gui/splits.lua   the splits window: report, countdowns, export
    shadow_race/gui/frames.lua   shared window parts
    locale/*/shadow-race.cfg

All state lives under `storage.shadow_race`. A run is plain data (numbers and
strings), which is what the later export code needs. Passing messages go
through one function, which is where an Open Discord Bridge post attaches.
Position tracks for a ghost engineer fit as another array on the run.

## Performance

Measured on the rig (Factorio 2.1.23, one client, synthetic load of 20
racing teams with 3000-point runs and 200 to 400 archived runs):

| Work | When | Cost |
|---|---|---|
| Sample every live run | every 5 minutes | 0.02 ms for 20 teams |
| Announcer pass, including one auto-chase turn | every second | 0.045 ms for 20 racing teams |
| Rank one team against the archive (auto-chase) | one racing team per second, in turn | 0.56 ms at 219 runs, 1.24 ms at 419 |
| Rank for one open window | every 5 seconds per open window | 1.26 ms at 219 runs |
| Team clock chip with split line and panel | every second per player | 0.027 ms |

What these led to: the archive cap of 200 runs, auto-chase ranking one team
per second instead of all at once, open windows refreshing every 5 seconds
on staggered seconds, and the sorted mark list kept per run.

Recording always runs, also with the admin flag off. With the flag off there
is no HUD pass work and no GUI.

## Tests

- `tests/test_shadow_race.lua`: the timeline arithmetic, the recorder, the
  archive with retention, pins and the cap, and two teams with rivals,
  standings and auto-chase, through the real `team_slots`.
- Headless load and 600 ticks on base and Space Age (`dev/run-tests.sh`).
- A multiplayer join (`dev/run-mp.sh`).
- By hand in a client on base and Space Age: claim, research, leave, claim
  again, chase, pin, auto-chase and passing, the countdown panel, the
  announcement, the report, a planet arrival.

## Left for later

- **Best segments**: the fastest time across a player's runs for each
  stretch between fixed score checkpoints. With at most four kept runs per
  player it adds little yet; it fits as one more computed shadow.
- A ghost engineer and a ghost factory, export and import of a run as a
  text code, and overtakes posted through Open Discord Bridge.
- Two real teams chasing each other on one server has unit tests only; the
  rig has one client.
