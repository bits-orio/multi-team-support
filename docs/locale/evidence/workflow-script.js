export const meta = {
  name: 'mts-locale-inventory',
  description: 'Inventory every user-visible English string in MTS and verify Factorio localisation mechanics against local docs',
  phases: [
    { title: 'Sweep', detail: '8 readers over all 111 Lua files' },
    { title: 'Docs', detail: 'verify localisation mechanics against local Factorio 2.0 docs' },
    { title: 'Audit', detail: 'completeness critic over the merged inventory' },
  ],
}

const REPO = '/home/shobhitg/src/multi-team-support'

const STRINGS_SCHEMA = {
  type: 'object',
  required: ['files_scanned', 'strings', 'notes'],
  properties: {
    files_scanned: { type: 'array', items: { type: 'string' } },
    strings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'category', 'text', 'status', 'dynamic', 'visibility', 'hazards'],
        properties: {
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'integer' },
          category: { enum: ['chat', 'gui', 'tooltip', 'flying-text', 'command', 'setting', 'prototype', 'alert', 'log', 'error', 'external', 'other'] },
          text: { type: 'string', description: 'the English literal (or the locale key if already localised)' },
          status: { enum: ['hardcoded', 'localised', 'partial'] },
          dynamic: { type: 'string', description: 'how the string is assembled: concatenations, string.format, params interpolated. Empty string if fully static.' },
          visibility: { enum: ['player', 'admin', 'debug', 'external', 'log-only'] },
          hazards: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    notes: { type: 'string' },
  },
}

const FACTS_SCHEMA = {
  type: 'object',
  required: ['facts', 'caveats'],
  properties: {
    facts: {
      type: 'array',
      items: {
        type: 'object',
        required: ['topic', 'statement', 'source'],
        properties: {
          topic: { type: 'string' },
          statement: { type: 'string' },
          source: { type: 'string', description: 'where in the local docs/files this was verified (file + concept/class/section)' },
        },
      },
    },
    caveats: { type: 'string' },
  },
}

const CONV_SCHEMA = {
  type: 'object',
  required: ['chat_style_rules', 'key_conventions', 'remote_api_strings', 'discord_integration', 'notes'],
  properties: {
    chat_style_rules: { type: 'string' },
    key_conventions: { type: 'string' },
    remote_api_strings: { type: 'string' },
    discord_integration: { type: 'string' },
    notes: { type: 'string' },
  },
}

const CRITIC_SCHEMA = {
  type: 'object',
  required: ['missed', 'category_gaps', 'sample_check', 'notes'],
  properties: {
    missed: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'line', 'evidence'],
        properties: {
          file: { type: 'string' },
          line: { type: 'integer' },
          evidence: { type: 'string' },
        },
      },
    },
    category_gaps: { type: 'array', items: { type: 'string' } },
    sample_check: { type: 'string' },
    notes: { type: 'string' },
  },
}

const finderPrompt = (files) => `You are inventorying user-visible English strings in a Factorio 2.0 mod for a localisation project. Repo: ${REPO}. Read EVERY file in this list COMPLETELY (they are small; read the whole file, not excerpts):

${files.map((f) => REPO + '/' + f).join('\n')}

For each file, find EVERY string that can reach a player's screen, and report it in the structured output. That includes:
- chat/console messages: game.print, player.print, force.print, surface.print
- flying text (player.create_local_flying_text etc.)
- GUI: caption=, tooltip=, text= on LuaGuiElement .add{} or assignments, including strings inside localised-string tables
- commands.add_command name + help text, and every response string those commands print
- custom alerts, message dialogs, set_goal_description, chart/map tag names, anything else display-bound
- data-stage: localised_name/localised_description, prototype names/descriptions, setting prototypes
- error() messages and log() calls (classify as category 'error'/'log', visibility 'log-only' or 'debug' as appropriate)
- strings handed to other mods or external systems (remote interface return values that get displayed, Discord bridge payloads) → category 'external'

Include even tiny strings ("OK", "Cancel", "+", "▶", "×"). For icon/symbol-only strings add hazard 'symbol-only'. Do NOT report: code comments, table keys, event/style/prototype identifier names used only as identifiers, file paths, pattern strings for string.find, storage keys.

Per string, set:
- status: 'localised' if it is already a {"section.key", ...} locale reference, 'partial' if a locale reference is concatenated/mixed with hardcoded English, 'hardcoded' otherwise.
- dynamic: describe exactly how it is assembled if not static — every '..' concatenation, string.format, table.concat, tick-to-time formatting, number formatting, player/team name interpolation. This is critical: concatenated sentences are the main localisation hazard.
- visibility: 'player' (any player sees it), 'admin' (admin-only), 'debug' (behind a debug flag), 'external' (leaves the game: Discord, RCON, files), 'log-only'.
- hazards, any of: 'concat' (sentence built by concatenation), 'plural' (text hardcodes singular/plural like "1 slot"/"slots" or picks between them in Lua), 'sentence-fragments' (reusable fragment strings composed into sentences elsewhere), 'rich-text' (embeds [color=]/[item=]/[font=] tags), 'server-side-string' (built into a plain Lua string before display, so all players would get one language), 'discord-mirror' (also sent to Discord/external where a LocalisedString cannot go), 'symbol-only', 'sorted-by-text' (list sorted by the display string), 'newlines' (embedded \\n layout).

files_scanned must list every file you read (repo-relative), even ones with zero strings. In notes, mention anything structurally interesting for the localisation plan (helper functions that build messages, message pipelines, patterns repeated across files).

Your final output is consumed by a script, not a human — return only the structured data.`

const DOCS_RUNTIME = `You are verifying Factorio 2.0 localisation mechanics for a mod localisation plan. Ground truth is the LOCAL docs at /home/shobhitg/factorio-2.0/doc-html/runtime-api.json (large file — query it with python3/jq, e.g. extract the 'concepts' array entry named 'LocalisedString', and specific classes/methods). Do NOT answer from memory; every fact must be verified in the local docs and cite where.

Verify and report on:
1. The LocalisedString concept in full: composition rules (key + parameters), the empty-first-element "" concatenation form, parameter substitution (__1__ etc.), maximum parameter count, maximum nesting depth, the plural syntax (__plural_for_parameter_...__ — exact grammar and which patterns are supported, e.g. exact numbers, 'rest', 'ends in'), any special built-in parameters (__CONTROL__..., __ENTITY__..., __ITEM__..., etc.), and the '?' fallback-list form if it exists.
2. For each of these API surfaces, whether it accepts LocalisedString or only plain string (check the exact signature in the JSON): game.print, LuaPlayer.print, LuaForce.print, LuaSurface.print, LuaGuiElement.caption, LuaGuiElement.tooltip, LuaGuiElement.text (textbox/textfield content), LuaGuiElement.add parameters, commands.add_command (the help parameter), LuaPlayer.create_local_flying_text, LuaPlayer.add_custom_alert / add_alert, LuaPlayer.set_goal_description, LuaForce.set_goal_description if it exists, LuaPlayer.request_translation / request_translations and the on_string_translated event, log(), localised printing to RCON (rcon.print), game.show_message_dialog if it exists, LuaEntity/LuaCustomChartTag text or chart tag names, LuaGuiElement elem_tooltip, choose-elem-buttons, anything notable about 'caption vs text' distinctions.
3. Per-player locale behaviour: what the docs say about where LocalisedString is resolved (server vs each client), and the implications of request_translation for sorting translated lists.
4. LuaPlayer.locale or equivalent (how to read a player's language), if it exists in 2.0.
Also check /home/shobhitg/factorio-2.0/doc-html/prototype-api.json briefly for: how localised_name/localised_description on prototypes interact with auto-generated locale keys (entity-name.X etc.), and the TechnologyPrototype localised_name level conventions if documented.

Report each finding as a fact with a source pointer (which file, which concept/class/member). If something cannot be verified in the local docs, say so explicitly in caveats rather than guessing. Your final output is consumed by a script — return only structured data.`

const DOCS_LOCALE_FILES = `You are verifying how Factorio 2.0 locale FILES work, for a mod localisation plan. Ground truth: the LOCAL Factorio install at /home/shobhitg/factorio-2.0/ — especially data/base/locale/ and data/core/locale/. Do NOT answer from memory; verify everything by inspecting real files and cite paths.

Tasks:
1. List the full set of language directory codes under data/base/locale/ (this is the list of languages the base game ships — candidate targets for phase 2).
2. Locale file format: examine several real .cfg files in data/base/locale/en/ and data/core/locale/en/ — encoding, [section] names in real use, comment syntax, multi-line handling, how keys with parameters look in practice.
3. Find REAL examples of plural handling: grep for 'plural_for_parameter' across data/*/locale/en/*.cfg and quote 2-3 real examples verbatim, including one from a non-English language dir (e.g. ru or pl) showing how a translation uses different plural patterns than English.
4. Verify the correct locale sections for mod metadata shown in the Mods GUI: search data/core/locale/en/*.cfg for 'mod-name' / 'mod-description' sections and confirm the exact section names a mod should use. Note: the mod under review currently uses a section called [mod-info] in its locale/en/locale.cfg (path: /home/shobhitg/src/multi-team-support/locale/en/locale.cfg) — determine whether [mod-info] is actually a recognized section (search the core/base locale + any shipped mods under /home/shobhitg/factorio-2.0/data/ for it) or whether it should be [mod-name]/[mod-description].
5. Verify the sections for mod settings ([mod-setting-name], [mod-setting-description]) and — important — how allowed_values of a string setting are localised ([string-mod-setting] section? find real usage in base/core or document absence).
6. Confirm locale folder layout rules for mods (locale/<code>/<any>.cfg) by finding a real mod or base-game example, and what happens on missing keys (the literal 'Unknown key' rendering) if any core locale file or docs mention it.
7. Check data/core/locale/en/core.cfg (or similar) for commonly reusable built-in keys a mod could reference instead of duplicating (e.g. [gui] ok/cancel/confirm keys, per-second suffixes, time formats like hours/minutes abbreviations) and list ~10 useful ones with their exact section.key names.
Report facts with exact file paths as sources. If something cannot be verified locally, say so in caveats. Your final output is consumed by a script — return only structured data.`

const CONVENTIONS = `You are gathering house conventions for a localisation plan for the Factorio mod at ${REPO}. Read these files fully:
- ${REPO}/CONTEXT.md
- ${REPO}/README.md
- ${REPO}/.claude/skills/chat-message-style.md
- ${REPO}/.claude/skills/lua.md
- ${REPO}/locale/en/locale.cfg
- ${REPO}/docs/MTS_API.md
- ${REPO}/docs/COMPAT.md (skim for anything about messages/strings crossing mod boundaries)

Also grep the repo's scripts/ and events/ for how the open-discord-bridge integration works (search for 'discord', 'bridge', 'odb'): which strings MTS sends to Discord or receives, and via what mechanism (remote calls? game events?).

Report:
- chat_style_rules: the house style for chat messages (prefixes, tone, formatting, color conventions) as documented in chat-message-style.md — summarize the actual rules, they shape locale key values.
- key_conventions: what naming/structure conventions the existing locale/en/locale.cfg uses (sections, key prefixes, comment style).
- remote_api_strings: which strings cross the remote-interface boundary per MTS_API.md — strings other mods (like land-title-registry) display, or strings MTS displays on behalf of other mods. These constrain what can become a LocalisedString without breaking consumers.
- discord_integration: exactly which messages mirror to Discord and how; whether they're plain strings.
- notes: anything else in the docs bearing on localisation (multiplayer considerations, pause behavior around GUI, etc.).
Your final output is consumed by a script — return only structured data.`

phase('Sweep')

const chunks = (args && args.chunks) || [
  { key: 'gui-1', files: ['gui/admin.lua', 'gui/awards.lua', 'gui/buddy_requests.lua', 'gui/chat_switch.lua', 'gui/confirm.lua', 'gui/follow_cam_frame.lua', 'gui/follow_cam.lua', 'gui/friendship.lua', 'gui/hud_clock.lua', 'gui/landing_pen.lua', 'gui/landing_pen_terrain.lua'] },
  { key: 'gui-2', files: ['gui/lfm_hint.lua', 'gui/nav.lua', 'gui/pen_gui.lua', 'gui/pen_info_panel.lua', 'gui/pen_ops.lua', 'gui/platform_hub.lua', 'gui/research_diff.lua', 'gui/research.lua', 'gui/research_overview.lua', 'gui/return_button.lua', 'gui/start_playing_gui.lua'] },
  { key: 'gui-3', files: ['gui/stats/columns.lua', 'gui/stats/counts.lua', 'gui/stats/discovery.lua', 'gui/stats/grid.lua', 'gui/stats/handlers.lua', 'gui/stats.lua', 'gui/stats/panel.lua', 'gui/stats/quality.lua', 'gui/team_card.lua', 'gui/teams_data.lua', 'gui/team_settings.lua', 'gui/teams.lua', 'gui/welcome.lua'] },
  { key: 'scripts-1', files: ['scripts/admin_flags.lua', 'scripts/blueprint_lock.lua', 'scripts/buddy_store.lua', 'scripts/chat_channel.lua', 'scripts/chat_tag.lua', 'scripts/chunk_trim.lua', 'scripts/color_fix.lua', 'scripts/commands/admin.lua', 'scripts/commands/debug_cmd.lua', 'scripts/commands.lua', 'scripts/commands/team.lua', 'scripts/debug.lua'] },
  { key: 'scripts-2', files: ['scripts/force_utils.lua', 'scripts/global_milestones.lua', 'scripts/helpers.lua', 'scripts/pause/control.lua', 'scripts/pause/power.lua', 'scripts/pause/state.lua', 'scripts/pause/wires.lua', 'scripts/planet_map.lua', 'scripts/pop_text.lua', 'scripts/pop_text_tick.lua', 'scripts/pre_start.lua', 'scripts/records.lua'] },
  { key: 'scripts-3', files: ['scripts/remote_api.lua', 'scripts/space_age.lua', 'scripts/spawn_labels.lua', 'scripts/spectator/core.lua', 'scripts/spectator/events.lua', 'scripts/spectator.lua', 'scripts/spectator/ops.lua', 'scripts/surface_utils.lua', 'scripts/team_clock.lua', 'scripts/team_disband.lua', 'scripts/team_modifiers.lua', 'scripts/team_rename.lua', 'scripts/team_slots.lua', 'scripts/team_surfaces.lua', 'scripts/tech_records.lua'] },
  { key: 'events-root', files: ['events/chat.lua', 'events/gui_clicks.lua', 'events/gui_state.lua', 'events/helpers.lua', 'events/player_force.lua', 'events/player_lifecycle.lua', 'events/player_removed.lua', 'events/player_surface.lua', 'events/research.lua', 'events/ticks.lua', 'milestones/config.lua', 'milestones/engine.lua', 'control.lua', 'data.lua', 'data-final-fixes.lua', 'settings.lua'] },
  { key: 'compat-proto', files: ['compat/claustorephobic.lua', 'compat/clone_mirror.lua', 'compat/compat_utils.lua', 'compat/dangoreus.lua', 'compat/deep_core_ops.lua', 'compat/gridlocked.lua', 'compat/lignumis.lua', 'compat/mts_dimension_warp.lua', 'compat/platformer.lua', 'compat/reassign_player_force.lua', 'compat/remote_safe.lua', 'compat/space_is_fake.lua', 'compat/ultracube.lua', 'compat/vanilla.lua', 'compat/voidblock.lua', 'prototypes/compat/belt_ban.lua', 'prototypes/connections.lua', 'prototypes/entities/passive-radar.lua', 'prototypes/entities/passivize-radars.lua', 'prototypes/planets.lua', 'prototypes/styles.lua'] },
]
const thunks = chunks.map((c) => () => agent(finderPrompt(c.files), { label: 'sweep:' + c.key, phase: 'Sweep', schema: STRINGS_SCHEMA }))
thunks.push(() => agent(DOCS_RUNTIME, { label: 'docs:runtime-api', phase: 'Docs', schema: FACTS_SCHEMA }))
thunks.push(() => agent(DOCS_LOCALE_FILES, { label: 'docs:locale-files', phase: 'Docs', schema: FACTS_SCHEMA }))
thunks.push(() => agent(CONVENTIONS, { label: 'docs:house-style', phase: 'Docs', schema: CONV_SCHEMA }))

const results = await parallel(thunks)
const finderResults = results.slice(0, chunks.length).filter(Boolean)
const runtimeFacts = results[chunks.length]
const localeFacts = results[chunks.length + 1]
const conventions = results[chunks.length + 2]

const inventory = finderResults.flatMap((r) => r.strings)
const scanned = finderResults.flatMap((r) => r.files_scanned)
const countsByFile = {}
for (const f of scanned) countsByFile[f] = 0
for (const s of inventory) countsByFile[s.file] = (countsByFile[s.file] || 0) + 1
log(`Sweep merged: ${inventory.length} strings across ${scanned.length} files (${finderResults.length}/${chunks.length} finders returned)`)

phase('Audit')

const criticPrompt = `A fan-out sweep inventoried user-visible English strings in the Factorio mod at ${REPO} for a localisation project. Your job: find what it MISSED. Per-file string counts from the sweep (repo-relative path -> count; a file listed with 0 was read and reported clean):

${JSON.stringify(countsByFile, null, 1)}

Do this:
1. Run your own greps over the repo (exclude .claude/) for display-bound patterns: '.print(', 'create_local_flying_text', 'create_flying_text', 'caption', 'tooltip', 'text =', 'add_custom_alert', 'add_alert', 'show_message_dialog', 'set_goal_description', 'chart_tag', 'add_command', 'help =', 'localised_', 'string.format', 'flying', 'rcon', 'game.print'. Any hit in a file with a suspiciously low/zero count above → read that file at that location and decide if a user-visible string was missed. Report each genuinely missed string in 'missed' with evidence (the code line).
2. Check whole-file coverage: list any .lua file in the repo (excluding .claude/) absent from the counts map entirely. Also check settings.lua, data.lua, data-final-fixes.lua, control.lua, and locale/en/locale.cfg were covered.
3. category_gaps: think about Factorio surfaces the sweep may have no entries for at all and check whether the mod uses them: map/chart tags, train stop or surface renames shown to players, custom-input key binding names ([controls] locale section), shortcut prototypes, tips-and-tricks, technology names from dynamic tech creation, milestone display names (milestones/), electric-network/pollution statistics names, GUI styles with default captions in data stage, changelog.txt (not localisable — confirm it's excluded by design), info.json description. For each gap: state whether the mod actually has such content and where.
4. sample_check: pick 8 random files with non-zero counts, read one reported location each, and confirm the line really contains that string (report mismatches).
Return only structured data.`

const critic = await agent(criticPrompt, { label: 'audit:completeness', phase: 'Audit', schema: CRITIC_SCHEMA })

return {
  inventory,
  scanned,
  finder_notes: finderResults.map((r) => r.notes),
  runtimeFacts,
  localeFacts,
  conventions,
  critic,
}
