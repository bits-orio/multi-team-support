export const meta = {
  name: 'mts-locale-convert-b',
  description: 'Convert GUI modules to locale keys (workflow B of the MTS localization)',
  phases: [{ title: 'Convert', detail: '6 GUI slice agents, disjoint file ownership' }],
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
    dual_api: { type: 'array', items: { type: 'string' } },
    deferred: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'what', 'why'],
        properties: { file: { type: 'string' }, what: { type: 'string' }, why: { type: 'string' } },
      },
    },
    missed_strings: { type: 'array', items: { type: 'string' } },
    checker_output: { type: 'string' },
    observations: { type: 'string' },
  },
}

const PRODUCERS = `Producer APIs already converted (workflow A, committed) — use these instead of the plain-string twins wherever your GUI displays their output:
- helpers.ls_duration / ls_duration_coarse / ls_elapsed (LocalisedString durations)
- teams_data.ls_fmt_ago / ls_activity_info / ls_build_activity_tooltip; collect_team_surfaces entries carry ls_name / ls_location
- friendship.get_state now ALSO returns ls_label, ls_tooltip as 5th/6th return values (first four unchanged)
- hud_clock.ls_clock_caption
- team_modifiers: ls_label/ls_short/ls_tooltip fields on MODIFIERS defs; ls_describe / ls_card_line / ls_marked_badge / ls_hud_tag / ls_guidance / ls_disable_blocked_reason / ls_records_tag
- admin_flags: ls_label/ls_tooltip fields on FLAGS defs; ls_get_flag_label
- compat_utils.ls_planet_display_name ({"?", {"space-location-name."..id}, fallback})
- spectator.ls_get_chat_prefix
Existing keys to REUSE, not redefine: mts-confirm.cancel/ok/title/message (shared.cfg), mts-gui.show-offline* (shared.cfg), everything in the other locale/en/*.cfg files — read them all first; reusing an existing key is right ONLY when both text and context match, otherwise define your own (duplicate English text across differently-named keys is fine and helps translators).`

const mkPrompt = (slice, files, cfg, notes) => `You are converting hardcoded English display strings to Factorio locale keys in the mod at ${REPO}. Careful, mechanical work with exact rules.

FIRST read these, completely:
1. ${REPO}/docs/locale/CONVERSION-GUIDE.md — the contract you must follow exactly
2. ${REPO}/docs/locale/inventory.json — filter to your assigned files; those rows are your checklist (line numbers may have drifted — match by content)
3. ${REPO}/.claude/skills/chat-message-style.md — house message style
4. All existing ${REPO}/locale/en/*.cfg files — to reuse keys and avoid duplicate definitions

${PRODUCERS}

Your slice: ${slice}
Your Lua files (edit ONLY these):
${files.map((f) => '- ' + REPO + '/' + f).join('\n')}
Your locale file (create it, own it exclusively): ${REPO}/locale/en/${cfg}

Slice-specific notes:
${notes}

Work through every inventory row for your files plus anything the inventory missed. Read each whole file before editing. GUI captions/tooltips/dropdown items accept LocalisedStrings; textfield/text-box .text contents do NOT (plain string — player input stays untouched). Numeric/punctuation-only compositions ("3 / 16", "x2" where x is literal → key; bare numbers → no key) follow the guide's symbol-only policy: no key when there is no English word or grammar in it.

When done: run 'python3 tools/check_locale.py' from ${REPO} (0 errors required; warnings naming YOUR keys are typos — fix; warnings naming other slices' in-flight keys are churn, note them), then re-read your full diff (git diff -- <your files>) against the guide's classic mistakes. Do NOT run any other git commands. Return only the structured report.`

const SLICES = [
  {
    slice: 'gui-admin', cfg: 'gui-admin.cfg',
    files: ['gui/admin.lua'],
    notes: `Switch FLAGS/MODIFIERS rendering to the ls_label/ls_tooltip fields and ls_marked_badge. The composed tooltip at ~line 145 (def.label .. " for this team. " .. def.tooltip) becomes a parameterised key taking ls_label and ls_tooltip as params: value "__1__ for this team. __2__". Sanctioned internal-name bugfixes: starter-item rows show item.name / item.name .. " [+grid]" / "Remove " .. item.name / "Equipment: " .. table.concat(internal names) — switch to prototypes.item[name].localised_name (guard missing prototypes; keep raw name as {"?"}-style fallback where a prototype may not exist). The two log() lines stay English. The buddy-limit dropdown items are numbers (tostring(i)) — no keys. "x" .. item.count → key "x__1__" (English-adjacent quantity prefix). The teams list line (~152) composes team_tag_with_leader + badge: use ls_marked_badge as a parameter in a keyed line. Admin-only visibility is still converted (policy decision: admins get localization too).`,
  },
  {
    slice: 'gui-teams', cfg: 'gui-teams.cfg',
    files: ['gui/team_card.lua', 'gui/teams.lua', 'gui/team_settings.lua', 'gui/lfm_hint.lua', 'gui/chat_switch.lua', 'gui/buddy_requests.lua'],
    notes: `team_card consumes many producers — switch to ls_ everywhere: teams_data.ls_activity_info (ago_text/tooltip), hud_clock.ls_clock_caption (~lines 70,324), team_modifiers.ls_card_line (~82), friendship.get_state's new 5th/6th ls returns (~144). Surface rows (~197,200) use entry ls_name/ls_location. team_settings: the rename err from team_rename.attempt is ALREADY a LocalisedString (workflow A switched it) — verify the print site needs no change; the "n / 16" length counter is numeric composition (no key) but its byte-length # and :sub truncation of player input stay untouched (pre-existing UTF-8 issue, observation only). The two LFM broadcasts (~326/329) are in-game only (helpers.broadcast does not bridge) — convert with team tag parameter. chat_switch 3-state tooltips: one key per variant, "\\nClick to switch ..." tails included in the values. buddy_requests: requester/leader prints with colored names as parameters. "Start recruiting" button caption is quoted inside welcome.lua's About text (another slice) — note the cross-reference in observations so wording stays consistent in phase 2.`,
  },
  {
    slice: 'gui-welcome', cfg: 'gui-welcome.cfg',
    files: ['gui/welcome.lua', 'gui/start_playing_gui.lua', 'gui/return_button.lua', 'gui/follow_cam_frame.lua', 'gui/follow_cam.lua'],
    notes: `welcome.lua's About tab is a documentation page of concatenated paragraphs: one key per paragraph/section, composed with {"", {"k1"}, "\\n\\n", {"k2"}, ...} respecting the 20-param cap (nest if needed). Keep the padded tab captions ("  About  ", "  Discord  ") byte-identical — padding inside the value. The Discord URL comes from settings as a parameter. start_playing_gui: possessive "{team}'s clock" becomes a whole-sentence key with the team name as __1__; the hardcoded "(press M)" keybind stays byte-identical inside its key value (note in observations that a __CONTROL__ substitution would need a real custom-input prototype — phase-2 candidate). follow_cam_frame: "  (no teams yet)" keeps its leading-space layout inside the value.`,
  },
  {
    slice: 'gui-pen', cfg: 'gui-pen.cfg',
    files: ['gui/pen_gui.lua', 'gui/pen_info_panel.lua', 'gui/pen_ops.lua', 'gui/landing_pen.lua', 'gui/landing_pen_terrain.lua', 'gui/platform_hub.lua'],
    notes: `pen_gui: the 3-way spawn-button tooltip (~171-175) and leader "— offline" suffix become per-variant whole keys; "Request to join" etc. straightforward. pen_info_panel: display_panel_text content is admin-authored data — stays plain (kept_english, note it); if there is a hardcoded DEFAULT text, leave it plain too but flag it in observations (making the default a key interacts with the admin edit textbox reading .text back — a stage-5 decision). landing_pen_terrain: rendering.draw_text ground text accepts LocalisedStrings — convert; note in observations that whether each client resolves world-render text in its own language is a playtest question. platform_hub: widget captions come from consumer mods via remote (pass-through, kept_english disposition). nav-button registrations encountered in these files: the tooltip strings passed into nav specs are PERSISTED IN STORAGE — leave them plain with -- TODO(locale-stage5) and disposition deferred.`,
  },
  {
    slice: 'gui-research', cfg: 'gui-research.cfg',
    files: ['gui/research.lua', 'gui/research_diff.lua', 'gui/research_overview.lua'],
    notes: `research_diff already has partial LocalisedStrings ({"", localised_label, hardcoded_suffix}) — replace the English tails with parameterised keys (status "partial" rows in the inventory). diff_section's appended "  (N)" count moves into the key ("__1__  (__2__)" or per-section keys). The 3-way clock-context variants and "Currently researching"/"Queued at position N" each get their own key (position as parameter). fmt_duration usages displayed in GUI switch to helpers.ls_duration (byte-identical); "You started X earlier than ..." style sentences take the duration LocalisedString as a parameter. "Research: You vs X" title: whole key with the team name parameter. The nav-button registration tooltip "Research Comparison" (research.lua ~172) is persisted in storage — leave plain, -- TODO(locale-stage5), disposition deferred. Sorting by internal prototype name while displaying localised labels: pre-existing sorted-by-text artifact, observation only.`,
  },
  {
    slice: 'gui-stats', cfg: 'gui-stats.cfg',
    files: ['gui/stats.lua', 'gui/stats/columns.lua', 'gui/stats/counts.lua', 'gui/stats/discovery.lua', 'gui/stats/grid.lua', 'gui/stats/handlers.lua', 'gui/stats/panel.lua', 'gui/stats/quality.lua', 'gui/awards.lua'],
    notes: `counts.fmt's "1.2k"/"3.4M" number suffixes: kept_english by policy (numeric formatting decision deferred to phase 2.5 — disposition + observation). The selected-tab pattern '"> " .. label' (3 sites in panel.lua): one key "> __1__" taking the (now keyed) label as parameter. Column headers and quality tooltips use prototype localised_name where available (grid.lua/panel.lua already do in places). "Team slot N (force-name)" tooltips: parameterised key (define your own even though team_card has similar text — different context). awards.lua: CAT_LABELS become keys; leaderboard "First"/milestone_prefix fragments become whole-sentence or whole-cell keys per the guide's fragment rule; ordinals 1st/2nd/3rd → key "__1__st"-style is WRONG — use one key with __plural_for_parameter__1__{ends in 11=th|ends in 12=th|ends in 13=th|ends in 1=st|ends in 2=nd|ends in 3=rd|rest=th}__ (first match wins; 11th/12th/13th before ends-in-1/2/3). "%d / %d match(es)" and "%d ×" get plural-aware keys. The search box matches internal prototype names — pre-existing limitation, observation only; search PLACEHOLDER/tooltip text converts. teams_data.fmt_ago plain consumer at grid.lua ~175 switches to ls_fmt_ago.`,
  },
]

phase('Convert')
const results = await parallel(
  SLICES.map((s) => () => agent(mkPrompt(s.slice, s.files, s.cfg, s.notes), { label: 'convert:' + s.slice, phase: 'Convert', schema: REPORT_SCHEMA }))
)

return { reports: results, slices: SLICES.map((s) => s.slice) }
