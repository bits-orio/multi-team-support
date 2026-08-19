export const meta = {
  name: 'mts-locale-convert-a',
  description: 'Convert scripts/events/commands/milestones to locale keys (workflow A of the MTS localization)',
  phases: [{ title: 'Convert', detail: '8 slice agents, disjoint file ownership' }],
}

const REPO = '/home/shobhitg/src/multi-team-support'

const REPORT_SCHEMA = {
  type: 'object',
  required: ['slice', 'dispositions', 'dual_api', 'deferred', 'missed_strings', 'checker_output', 'observations'],
  properties: {
    slice: { type: 'string' },
    dispositions: {
      type: 'object',
      required: ['converted', 'kept_english', 'deferred'],
      properties: {
        converted: { type: 'integer' },
        kept_english: { type: 'integer' },
        deferred: { type: 'integer' },
      },
    },
    dual_api: { type: 'array', items: { type: 'string' }, description: 'functions given ls_ variants, with why' },
    deferred: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'what', 'why'],
        properties: { file: { type: 'string' }, what: { type: 'string' }, why: { type: 'string' } },
      },
    },
    missed_strings: { type: 'array', items: { type: 'string' }, description: 'display strings found that inventory.json lacks' },
    checker_output: { type: 'string', description: 'verbatim final output of tools/check_locale.py' },
    observations: { type: 'string', description: 'wording bugs noticed (NOT fixed), risks, anything the final sweep must know' },
  },
}

const mkPrompt = (slice, files, cfg, notes) => `You are converting hardcoded English display strings to Factorio locale keys in the mod at ${REPO}. This is careful, mechanical work with exact rules.

FIRST read these, completely:
1. ${REPO}/docs/locale/CONVERSION-GUIDE.md — the contract you must follow exactly
2. ${REPO}/docs/locale/inventory.json — filter to your assigned files; those rows are your checklist (match by content; line numbers may have drifted slightly)
3. ${REPO}/.claude/skills/chat-message-style.md — house message style

Your slice: ${slice}
Your Lua files (edit ONLY these):
${files.map((f) => '- ' + REPO + '/' + f).join('\n')}
Your locale file (create it, own it exclusively): ${REPO}/locale/en/${cfg}

Pre-seeded shared keys you must reuse instead of defining: {"mts-cmd.player-only"} = "This command can only be used by a player.", {"mts-cmd.team-not-exists", name} = "Team '__1__' does not exist." (defined in locale/en/commands-shared.cfg). Stage-1 helpers available: helpers.ls_duration / ls_duration_coarse / ls_elapsed (LocalisedString duration builders), helpers.broadcast and helpers.add_title_bar carry LocalisedStrings, gui/confirm.lua opts accept LocalisedStrings.

Slice-specific notes (from the sweep — these override nothing in the guide, they focus it):
${notes}

Work through every inventory row for your files plus any display string the inventory missed. Read each whole file before editing it. When done: run 'python3 tools/check_locale.py' from ${REPO} (must be 0 errors; warnings about YOUR keys mean a typo — fix), then re-read your complete diff (git diff -- <your files>) against the guide's three classic mistakes. Do NOT run any other git commands. Your final output is consumed by a script — return only the structured report.`

const SLICES = [
  {
    slice: 'cmd-team', cfg: 'commands-team.cfg',
    files: ['scripts/commands/team.lua', 'scripts/commands.lua', 'scripts/team_rename.lua'],
    notes: `team_rename.attempt returns English error strings consumed by scripts/commands/team.lua AND gui/team_settings.lua (~line 289). Grep every consumer: if all of them only pass the result to print/caption, switch the return type to LocalisedString in place (you may fix the trivial print sites in gui/team_settings.lua for this one contract — the sole permitted out-of-slice edit, keep it minimal); otherwise use the dual-API rule. commands.add_command help texts get keys in [mts-cmd]. Command responses printed via game.print/caller.print all convert. team_modifiers.describe()/marked_badge() results used around lines 201-205 of team.lua are ANOTHER slice's producer strings: leave those call sites on the string API, report as deferred.`,
  },
  {
    slice: 'cmd-admin', cfg: 'commands-admin.cfg',
    files: ['scripts/commands/admin.lua', 'scripts/commands/debug_cmd.lua', 'scripts/chunk_trim.lua'],
    notes: `chunk_trim.start returns English error strings and chunk_trim.notify prints progress — its only consumers are in commands/admin.lua (verify by grep), so the whole contract can move to LocalisedString in one motion. debug_cmd: ONLY the add_command help strings get keys; all /mts-debug output stays English (debug policy), and the task labels persisted in storage stay English with a -- TODO(locale-stage5) comment. Confirm-dialog call sites pass keyed opts. teams_data.activity_info().ago_text consumed around admin.lua:132 is another slice's producer — leave on string API, report deferred. The "[Admin] " broadcast prefix: keep it inside each key's value (byte-identical), do not make it a separate fragment.`,
  },
  {
    slice: 'lifecycle-chat', cfg: 'chat.cfg',
    files: ['events/player_lifecycle.lua', 'events/chat.lua', 'events/ticks.lua', 'events/player_surface.lua', 'events/gui_clicks.lua', 'events/gui_state.lua'],
    notes: `Welcome/welcome-back broadcasts: colored player name is a parameter; the Discord invite sentence is conditionally appended — compose with {"", base, cond and {"mts-chat....", url} or ""}. The "Teams looking for more players" block is copy-pasted twice in player_lifecycle.lua (~96-109 and ~118-135): dedupe into one local function while converting (same file, allowed). events/chat.lua: player message bodies and names are data; the "[spectating] " prefix and shout formatting become keys — the relay loop already prints per player, so per-recipient LocalisedStrings work today. events/ticks.lua Discord-reminder broadcast is in-game only (not bridged) — convert with the URL as parameter. events/gui_state.lua prints team_modifiers.disable_blocked_reason() — another slice's producer: leave that call, report deferred. mts.player_joined/player_left bridge emissions in these files: the data.text sent to the bridge stays plain English; only the in-game broadcast converts.`,
  },
  {
    slice: 'modifiers-flags', cfg: 'modifiers.cfg',
    files: ['scripts/team_modifiers.lua', 'scripts/admin_flags.lua'],
    notes: `You are the producer slice for the mod's worst fragment hotspot; the admin GUI (converted later) composes your outputs. For the MODIFIERS spec table and admin_flags.FLAGS: keep existing string fields (label/tooltip/short) untouched and ADD ls_label/ls_tooltip/ls_short LocalisedString fields beside them — consumers migrate later; report under dual_api. Same for describe()/guidance()/marked_badge()/hud_tag()/disable_blocked_reason(): add ls_ variants. Broadcasts issued from WITHIN these two files (modifier-change announcements, starter-items announcements incl. their hand-rolled plurals and "have/has") convert fully now, using your ls_ variants. announce_starter_items_added: the in-game broadcast converts; check whether any of its output also feeds a bridge payload — if so keep that path plain.`,
  },
  {
    slice: 'milestones-research', cfg: 'milestones.cfg',
    files: ['milestones/engine.lua', 'milestones/config.lua', 'scripts/global_milestones.lua', 'scripts/tech_records.lua', 'events/research.lua'],
    notes: `THE Discord dual-path slice (guide section "What must NOT be converted", first bullet — read twice). build_achievement_desc/build_external_achievement currently feed BOTH the in-game broadcast/pop-text AND the bridge data.text: split into two builders — keyed LocalisedString for in-game, the existing plain-English builder (with plain() rich-text stripping) for the bridge. Byte-identical English on both paths. For built-in milestones (milestones/config.lua) the in-game sentences become real parameterised keys with __plural_for_parameter__ replacing the blind appended "s" where the count is a parameter. For EXTERNAL consumer-registered milestones the verb/noun arrive as English data over the frozen mts-v1 interface: the in-game sentence skeleton still becomes a key, with verb/noun as parameters, and the English "s" pluralization of the noun stays in Lua (data limitation — note it in observations). rocket_launched announcements in global_milestones.lua: same split (throttling logic untouched). Record announcements using fmt_duration: in-game path switches to helpers.ls_duration, bridge path keeps fmt_duration. events/research.lua: in-game research-finished text converts; the bridge text (raw tech id in backticks) stays exactly as is. pop_text.global_milestone / rendering paths accept LocalisedStrings.`,
  },
  {
    slice: 'spectator-slots', cfg: 'spectator.cfg',
    files: ['scripts/spectator/core.lua', 'scripts/spectator/ops.lua', 'scripts/spectator/events.lua', 'scripts/spectator.lua', 'scripts/team_slots.lua', 'scripts/team_disband.lua'],
    notes: `Spectator chat prefixes and possessives ("<name>'s"): full-sentence keys with the colored name as parameter — never a standalone possessive fragment. spectator.get_chat_prefix consumers: check whether any are outside your slice (events/chat.lua reads it — that slice converts today too, so coordinate via the dual-API rule: add ls_ variant, leave the string one). team_slots: conditional-tail broadcasts ("... Their base has been cleaned up.") compose as {"", main, cond and {"", " ", {"key"}} or ""}; the default team name "Team %02d" written into storage.team_names stays a plain string with -- TODO(locale-stage5). helpers.diag calls stay English.`,
  },
  {
    slice: 'world-misc', cfg: 'misc.cfg',
    files: ['scripts/spawn_labels.lua', 'scripts/planet_map.lua', 'scripts/pop_text.lua', 'scripts/pre_start.lua', 'scripts/space_age.lua', 'scripts/surface_utils.lua', 'scripts/team_clock.lua', 'scripts/team_surfaces.lua', 'scripts/force_utils.lua', 'scripts/buddy_store.lua', 'scripts/color_fix.lua', 'scripts/blueprint_lock.lua', 'scripts/debug.lua', 'compat/claustorephobic.lua', 'compat/clone_mirror.lua', 'compat/compat_utils.lua', 'compat/dangoreus.lua', 'compat/deep_core_ops.lua', 'compat/gridlocked.lua', 'compat/lignumis.lua', 'compat/mts_dimension_warp.lua', 'compat/platformer.lua', 'compat/reassign_player_force.lua', 'compat/remote_safe.lua', 'compat/space_is_fake.lua', 'compat/ultracube.lua', 'compat/vanilla.lua', 'compat/voidblock.lua', 'prototypes/connections.lua', 'prototypes/planets.lua'],
    notes: `Wide but sparse — most compat files have zero display strings (inventory tells you which). spawn_labels.compute_text ("<name>'s spawn" style + clock): becomes a parameterised key; rendering.draw_text accepts LocalisedStrings; keep the plain builder only if some consumer needs a string (grep). compat_utils.planet_display_name (capitalises internal ids, re-exported by vanilla/voidblock/mts_dimension_warp): add ls_planet_display_name using {"?", {"space-location-name." .. id}, existing_capitalised_fallback}; convert consumers inside this slice (planet_map notify currently shows raw internal variant names — use the ls variant + helpers.display_surface_name semantics; that raw-name display is one of the sanctioned bugfixes, report it). prototypes/connections.lua " (Team N)" suffix: parameterised [entity-name]-style key modeled on mts-passivized-radar-prefix — data-stage locale tables have a 200-char key limit, fine here. pop_text.lua "RIP!" death text converts. debug.lua and blueprint_lock stay English per policy (check inventory rows and disposition them).`,
  },
  {
    slice: 'remote-gui-producers', cfg: 'producers.cfg',
    files: ['scripts/remote_api.lua', 'gui/teams_data.lua', 'gui/friendship.lua', 'gui/hud_clock.lua'],
    notes: `remote_api.lua is the Discord bridge heart: bridge_text/connection_text/emit_chat/bridge_payload/register_source descriptions/BRIDGE_LABELS ALL stay plain English (external) — disposition them kept_english. get_team_label stays a plain rich-text string (frozen mts-v1 contract). Convert only strings that are displayed IN-GAME from this file (grep for print/caption/flying text within it; the inventory rows marked visibility player/admin). gui/teams_data.lua: fmt_ago/fmt_playtime/activity_info return English fragments consumed by team_card/stats/admin (other slices, later): ADD ls_ variants (ls_fmt_ago, ls_fmt_playtime, ls_activity_info returning LocalisedString fields alongside) — dual_api. gui/friendship.lua get_state returned label/tooltip: add ls_label/ls_tooltip fields. gui/hud_clock.lua clock_caption: add ls_ variant; convert hud_clock's OWN GUI element captions/tooltips now. Planet/surface display names built by Lua-capitalising internal ids: use {"?", {"space-location-name." .. id}, fallback} per the guide.`,
  },
]

phase('Convert')
const results = await parallel(
  SLICES.map((s) => () => agent(mkPrompt(s.slice, s.files, s.cfg, s.notes), { label: 'convert:' + s.slice, phase: 'Convert', schema: REPORT_SCHEMA }))
)

return { reports: results, slices: SLICES.map((s) => s.slice) }
