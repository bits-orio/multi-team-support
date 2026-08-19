# Conversion guide — turning hardcoded strings into locale keys

Contract for every conversion slice (human or agent). Read fully before editing.
Mechanics were verified against the local Factorio 2.0.77 install — see PLAN.md §1.

## The rules

1. **Byte-identical English.** The English a player sees must not change. The
   locale value is the exact current text, parameters included. Do not fix
   wording, punctuation, or grammar while converting (file an observation
   instead). One deliberate exception category: internal prototype names
   currently shown raw (e.g. `iron-plate`) become proper `localised_name`
   lookups — that is a bugfix, list it in your report.
2. **One key per sentence.** Never translate fragments and glue them in Lua.
   Anything variable becomes a `__1__`-style parameter. Translators reorder
   parameters; concatenation freezes English word order.
3. **Static keys only.** Call sites contain literal `{"mts-<section>.<key>", ...}`
   tables. No computed key names. `tools/check_locale.py` depends on this.
4. **Own your files only.** Edit only your assigned Lua files and your own new
   `locale/en/<slice>.cfg`. Never touch another slice's cfg. Repeating a
   `[section]` header across cfg files is fine (the engine merges); a duplicate
   *key* in the same section is not (checker fails it).
5. **No git.** Do not commit, stage, or revert anything.

## Key naming

Sections: `[mts-chat]` broadcasts/prints, `[mts-cmd]` command help + responses,
`[mts-gui]` captions/labels, `[mts-tip]` tooltips, `[mts-confirm]` confirm
dialogs, `[mts-milestone]` milestone/records text. Keys: kebab-case, descriptive,
prefixed by feature when useful (`pen-request-join`, `research-queue-empty`).
Comment (`#`) above any key whose usage isn't obvious from its text — house
style explains why, not what.

## Patterns

**Static caption**
```lua
caption = "Research"                      -->  caption = {"mts-gui.research"}
```
```cfg
[mts-gui]
research=Research
```

**Assembled sentence → parameterised key** (`__1__` = first arg after the key)
```lua
requester.print("You requested to join " .. team_tag .. ". Waiting for a member to accept.")
-->
requester.print({"mts-chat.join-requested", team_tag})
```
```cfg
join-requested=You requested to join __1__. Waiting for a member to accept.
```
Rich-text fragments (`helpers.colored_name`, `team_tag`, `item_rich_name`,
badges) are plain strings — pass them as parameters, they render inside
translated values unchanged.

**Trailing force tag stays composed** (house style: tag after the sentence):
```lua
helpers.broadcast({"", {"mts-chat.left-team", cn}, helpers.force_tag(fn)})
```
(`force_tag` already carries its leading space.)

**Plurals** — route the number, let the locale decide. Kills `"(s)"`,
`count == 1 and "" or "s"`, "have/has", "is/are":
```lua
msg = count .. " slot" .. (count == 1 and "" or "s")
-->
{"mts-gui.slot-count", count}
```
```cfg
slot-count=__1__ __plural_for_parameter__1__{1=slot|rest=slots}__
```
The number selects branches; patterns supported: exact (`1=`), `ends in N`,
`rest`. English needs only `{1=…|rest=…}`; other languages add branches later.

**Branchy variants** — each English variant is its own key; pick the key in Lua:
```lua
tooltip = is_ready and {"mts-tip.spawn-ready"} or {"mts-tip.spawn-blocked"}
```

**Durations** — use the stage-1 builders as parameters (they compose engine
core keys, already translated): `{"mts-gui.playing-for", helpers.ls_duration(ticks)}`.
Plain `fmt_duration` stays wherever the result goes to Discord or `log()`.

**Internal names shown raw** — replace with the prototype's `localised_name`:
```lua
caption = item.name          -->  caption = prototypes.item[item.name].localised_name
caption = item.name .. " [+grid]"  -->  caption = {"", proto.localised_name, " [+grid]"}
```
Planets/surfaces: `{"space-location-name." .. planet_id}` (use the `{"?", ...}`
fallback form if the id might have no prototype:
`{"?", {"space-location-name." .. id}, display_fallback}`).

**Multi-line text**: `\n` is written literally inside cfg values. A paragraph =
one key; a page (welcome/About) = one key per paragraph/section, composed with
`{"", {"k1"}, "\n\n", {"k2"}}` (≤ 20 params per table; nest if longer).

## What must NOT be converted

- **Discord / bridge text**: anything reaching `remote_api` bridge payloads
  (`data.text`, `bridge_text`, `emit_*`, milestone `plain()` output) stays a
  plain English server-built string. A LocalisedString cannot leave the game.
  If a message is both broadcast in-game AND mirrored to Discord, split it:
  keyed LocalisedString for the in-game path, existing plain builder for the
  bridge. Never share one value between the paths.
- **`log()`, `helpers.diag`, `error()`** — stays English (grep-ability).
- **`/mts-debug` command output** — debug surface, stays English (its
  `add_command` *help* text does get a key).
- **Command names** (`/mts-rename`, `/t`) — typed tokens.
- **Strings persisted in `storage`** (nav button tooltips, debug task labels,
  default team names "Team %02d", admin-authored pen description): leave
  as-is, add `-- TODO(locale-stage5)` where display text is stored, report as
  deferred. Stage 5 migrates them deliberately.
- **`player.tag`, textfield `.text` contents, chart tags, platform names** —
  engine plain-string surfaces.
- **Player data** (names, team display names, typed messages) — parameters,
  never keys.

## Cross-file producer functions (the dual-API rule)

If you convert a function that *returns* display text and it has consumers
outside your slice: do NOT change its return type. Add an `ls_`-prefixed
LocalisedString variant beside it, convert consumers inside your slice to the
variant, leave outside consumers on the string version, and report the function
under `dual_api`. (The final sweep folds variants once all consumers migrate.)
Exception: if you grep-verify that *every* consumer in the repo only passes the
result to `print`/`caption`/`tooltip`, you may switch the return type in place —
say so in your report with the grep evidence.

## Checklist discipline

Your assigned inventory rows (docs/locale/inventory.json, filtered to your
files) are your checklist. Line numbers are from commit e755abe and may have
drifted — match by content. Every row gets a disposition in your report:
`converted` | `kept-english` (policy: log/debug/discord/data/symbol-only —
say which) | `deferred` (storage/cross-slice — say why). Also report any
display string you find that the inventory missed.

Before finishing: run `python3 tools/check_locale.py` from the repo root —
zero errors required (warnings about your keys mean a typo'd or dead key: fix).
Re-read your full diff once against these rules, then double-check the three
classic mistakes: a `..` concat left on a now-table value, a table sent to a
Discord path, `__2__` in a value whose call site passes one parameter.

Style: match the repo (see .claude/skills/lua.md, .claude/skills/chat-message-style.md) —
comment the why, keep functions small, no new polling.
