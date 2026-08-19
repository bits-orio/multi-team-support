# MTS Localisation Plan — Phase 1: make every string localisable

Written 2026-08-19 against commit `e755abe`. Companion documents:
- [INVENTORY.md](INVENTORY.md) — all 754 user-visible strings, per file/line, with hazards. This is the phase-1 checklist.
- [inventory.json](inventory.json) — the same data machine-readable, for driving the conversion.
- [evidence/](evidence/) — raw sweep outputs, agent transcripts, docs citations, and the audit run, for independent cross-examination.

Phases: **1** — convert MTS so every English string *can* be translated (this document). **2** — add actual language files. **3** — same treatment for LTR and the other MTS-family mods.

---

## 1. How Factorio localisation works (verified against the local 2.0.77 install, not memory)

Everything below was verified against `/home/shobhitg/factorio-2.0/doc-html/runtime-api.json` / `prototype-api.json` and the shipped locale files under `/home/shobhitg/factorio-2.0/data/`. Full citations in [evidence/workflow-result-full.json](evidence/workflow-result-full.json) (`runtimeFacts`, `localeFacts`).

**The one big idea.** Code never passes translated text around. It passes a **LocalisedString** — a Lua table `{"section.key", param1, param2}` — and *each player's client* resolves it in *that player's* language. `player.locale` is per-player; `on_string_translated` documents "the player whose locale was used". So once MTS speaks LocalisedString end-to-end, a German and a Japanese player on the same server each see their own language, with zero per-player work in our code. That is what phase 1 buys, even before phase 2 adds any language: the English just moves from Lua into `locale/en/`.

**Locale files.** `locale/<language-code>/<any-name>.cfg`, UTF-8, INI-style `[section]` + `key=value`, one physical line per value (`\n` written literally as two characters), `#` or `;` comments. Adding a language later = adding one directory of cfg files, no code changes. The base game ships 50 language codes (full list in evidence) — that's the phase-2 candidate pool.

**Mechanics we will lean on:**
- Parameters: `__1__`…`__20__` in the value; call site supplies them positionally. **Translations may reorder them** — this is how word-order differences are handled, and why sentences must be single keys, never concatenations.
- Max 20 parameters, max 20 nesting levels. Parameters can themselves be LocalisedStrings (that's how `{"entity-name.mts-passivized-radar-prefix", orig_name}` already works).
- `{"", a, " ", b}` — empty-string key concatenates parts (already used in `helpers.tech_label`).
- `{"?", option1, option2, fallback}` — first key that exists wins; useful for cross-mod lookups.
- Plurals: `__plural_for_parameter__1__{1=hour|rest=hours}__` selects text by the value of parameter 1. Patterns: exact number, `ends in N` (comma-separated lists), `rest`. Russian/Polish translators write their own richer branches (verbatim examples in evidence) — **we never encode plural logic in Lua**; we route the *number* as a parameter and let each language's file decide.
- Missing key renders literally as `Unknown key: 'section.key'` in game — ugly but instantly visible; our tooling (§6) turns that into a pre-release check.
- Reusable engine keys exist (`{"gui.close"}`=Close, `{"gui.save"}`=Save, root-scope `{"hours", n}` with plural handling built in, `{"time-symbol-hours-short", n}`="__1__h", `{"format-percent", n}`). Trap verified in the files: `gui.cancel` is the text **"Back"** — a real Cancel is `gui-mod-settings.cancel`.

**Which APIs take LocalisedString (all verified in the 2.0 docs):** every `print` (game/player/force/surface), `LuaGuiElement` `caption`/`tooltip`/drop-down `items`/switch labels/tab `badge_text`, `commands.add_command` **help** text, `create_local_flying_text`, `add_custom_alert`, `set_goal_description`, `rendering.draw_text`, `LuaEntity.display_panel_text`, `log()`, `rcon.print`, `game.show_message_dialog`.

**Which are plain-string only (engine limits — cannot be localised, ever):**
- `LuaGuiElement.text` — textbox *contents*. Fine: we only use it for player input.
- Chart/map tag text, `player.tag` (the chat badge), space-platform names, force names, surface names.
- Anything leaving the game: Discord bridge payloads, files. A LocalisedString table has no meaning outside a Factorio client.

One correction to a sweep note: INVENTORY's note for `pen_info_panel` says `display_panel_text` is plain-string-only — the docs say it *does* accept LocalisedString. Moot in practice: that panel shows admin-*typed* text, which is data, not translatable copy.

---

## 2. Where MTS stands today

The sweep read all 111 Lua files (audit in [evidence/audit-output.txt](evidence/audit-output.txt): full coverage, zero missed display-patterns, 10/10 samples verified):

- **754 user-visible strings**: 736 hardcoded English, 11 already localised, 7 partial.
- By audience: 519 player-visible, 107 admin-only, 50 external (Discord/RCON), 52 log-only, 26 debug-gated.
- Hazards: 290 concatenation-assembled sentences, 165 reusable sentence fragments, 170 flattened server-side before display, 120 with rich-text tags, 54 mirrored to Discord, 22 hand-rolled plurals (`"(s)"`, `count == 1 and "" or "s"`, "have/has").
- `locale/en/locale.cfg` covers only settings + the passivized-radar prefix. **Zero runtime message keys exist.**

**Two live bugs found during verification (fix first, independent of everything else):**
1. The `[mod-info]` section in `locale/en/locale.cfg` **is not a real section** — zero occurrences anywhere in the shipped game data. The mod's Mods-GUI description key is dead. Correct form (verified against base/quality/space-age): `[mod-name]` / `[mod-description]` with key `multi-team-support`.
2. `mts_discord_url` has a `[mod-setting-name]` entry but no `[mod-setting-description]`.

**The good news** — three structural facts make this tractable:
1. Nearly every chat message flows through one choke point: `scripts/helpers.lua` (`broadcast`, `team_tag`, `colored_name`, `force_tag`, `fmt_duration`, `add_title_bar`…). Convert the pipeline once, and ~15 broadcast sites plus every GUI title come along.
2. The house chat style (colored names, trailing grey force tags) is built from **rich-text fragments** — and rich text passes through locale values and parameters untouched. `colored_name(...)` simply becomes parameter `__1__` of a key; the style survives translation intact.
3. The repo already contains the model patterns: `entity-name.mts-passivized-radar-prefix=Passive __1__` (parameterised key composing another mod's localised name) and `helpers.tech_label`'s `{"", localised_name, " ", label}`.

---

## 3. Design decisions

**D1 — Localise at the sentence level.** Every message becomes exactly one locale key; everything variable becomes a `__n__` parameter. Never translate fragments and glue them in Lua (word order, articles, and adjective agreement differ per language — this is the "grammar stuff" you were worried about, and parameterised whole sentences are the entire answer to it). During conversion, **English values move into locale/en byte-identical** — so playtests can diff messages against memory of current behavior.

**D2 — Convert the helpers pipeline to carry LocalisedString.**
- `helpers.broadcast`, `add_title_bar`, the confirm-dialog contract (`title`/`message`/`confirm_text`/`cancel_text`), `chunk_trim.notify` + its string-returning error contract, `team_rename.attempt` error returns: all accept/return LocalisedString.
- Fragment builders (`colored_name`, `team_tag`, `team_tag_with_leader`, `force_tag`, `item_rich_name`, `tech_rich_name`, `team_modifiers.marked_badge`) stay plain rich-text strings, used **as parameters**.
- The time/number formatters (`fmt_duration`, `fmt_duration_coarse`, `format_elapsed`, `teams_data.fmt_ago`/`fmt_playtime`, `counts.fmt`) become LocalisedString builders — one central fix that de-Englishes "3h 12m", "just now", "<1m", "2d ago" everywhere, using core's plural-aware `hours`/`minutes` keys or our own.

**D3 — Discord stays plain English, on a separate path.** A LocalisedString cannot leave the game. All `open-discord-bridge-v1` payloads (`data.text` etc.) remain server-built English strings. The one place in-game and Discord text currently share a builder — the milestone pipeline (`build_achievement_desc` / `build_external_achievement`) — gets split: LocalisedString for broadcast/pop-text, plain string for the bridge. 54 inventory entries carry the `discord-mirror` hazard; each gets this dual-path treatment.

**D4 — Key naming.** Keep existing prototype/setting sections untouched. Runtime strings get mod-prefixed sections mirroring the module layout, kebab-case keys:
`[mts-chat]` (broadcasts, join/leave, LFM), `[mts-cmd]` (help texts, usage, guards, responses), `[mts-gui]` (captions/labels), `[mts-tip]` (tooltips), `[mts-confirm]`, `[mts-milestone]`. Shared strings get one home (e.g. `mts-cmd.player-only` replaces the guard repeated verbatim ×10; `Team '<x>' does not exist.` ×4 → one key). Split `locale/en/` into a few cfg files (`chat.cfg`, `gui.cfg`, `commands.cfg`, `prototypes.cfg`) — filenames are arbitrary and 24 lines is about to become ~450+ keys. Keep the house `#`-comment style above non-obvious keys.

**D5 — Static keys only.** Call sites use literal `{"mts-chat.team-created", ...}` tables; no computed key names except the already-established prefix patterns (radar prefix, planet variants). This keeps keys greppable and makes the checker tool (§6) airtight.

**D6 — What deliberately stays English:** `log()`/`helpers.diag` diagnostics (grep-ability beats translation; 52+26 entries), Discord (D3), command *names* (`/mts-rename` is a typed token; the *help* text localises), RCON output, the `[multi-team-support]` log prefix, and persisted data (below).

**D7 — Persisted strings need special handling.** Three spots store display text in `storage` where it survives save/load and would never re-translate:
- `storage.nav_button_order` freezes top-bar *tooltips* into the save → **migration**: store locale keys, resolve at rebuild (nav already rebuilds buttons — the hook exists).
- Debug task labels (`/mts-debug list`) → stay English (debug surface).
- Default team names `string.format("Team %02d", slot)` are baked into `storage.team_names` and double as *data* (Discord, remote API, dedup) → stay plain strings; documented limitation.

**D8 — The frozen `mts-v1` remote interface constrains phase 3, not phase 1.** Per MTS_API.md the v1 shapes can gain optional fields but not change. `get_team_label` stays a rich-text string; consumer-registered milestone `{category, verb, noun}` stays English fragments (they feed Discord anyway). Additive door-openers, designed now, landed when phase 3 needs them: `caption`s for registered tabs/widgets may *also* be LocalisedStrings (GUI `caption` accepts both types today — verify storage round-trip in playtest), and `register_milestone` can later gain an optional `localised_desc`. LTR will be the first consumer.

**D9 — Accepted limitations (document, don't fight):** the TEAM/GLOBAL chat badge (`player.tag`) is engine plain-string — stays server-language; awards search matches internal item names, not translated ones (a per-player translated-name cache via `request_translations` is a possible phase-2.5, not phase 1); lists sorted by display name will look unsorted in other alphabets (kept: server-side order); `"<name>'s hub"` platform names are plain strings (consider the neutral `"<name> hub"` while touching it); world-rendered text (spawn labels, pen ground text, pop-text) becomes LocalisedString — *verify in playtest* whether each client resolves it in its own language (docs don't say; my expectation is yes since all rendering text resolution is client-side).

---

## 4. Grammar hazards → concrete treatment

| Hazard (count) | Treatment |
|---|---|
| `concat` (290) | Each assembled sentence → one key with `__n__` slots; fragments become parameters. |
| `sentence-fragments` (165) | Kill fragment *reuse across sentences*: `team_modifiers.MODIFIERS` label/tooltip composed at 4 sites, `guidance()`, `CAT_LABELS` `"> "..label` selected-tab prefix (×3 in stats), `diff_section`'s `"  (N)"` — each composition point gets its own full key taking the fragment as data or duplicating the wording per context. Translators need full sentences, not Lego bricks. |
| `plural` (22) | Route the number as a parameter; `__plural_for_parameter__` in the value. Kills `"(s)"`, `count==1 and "" or "s"`, "have/has", "is/are". |
| `server-side-string` (170) | Disappears automatically once the D2 pipeline carries tables instead of flattened strings. |
| `rich-text` (120) | No change needed — tags pass through locale values and parameters. |
| `discord-mirror` (54) | Dual-path per D3. |
| `newlines` (41) | `\n` is legal inside locale values (engine does this everywhere, e.g. `mod-caused-error`). Multi-paragraph welcome/About copy becomes a handful of long keys, one per paragraph/section. |
| Ordinals ("1st/2nd/3rd") & possessives ("X's clock", "X's hub") | Reword keys so the pattern is translator-controlled: `place-1=1st` style enumerated keys or `__1__.` ; possessives become full-sentence keys (`"__1__'s clock"` as the *English value*, freely restructured per language). |
| `"(press M)"` hardcoded keybind (start_playing_gui) | Use the engine `__CONTROL__<input-name>__` substitution if a real control exists, else keep as parameter. |
| Internal names shown raw | Fix while converting: admin starter-item rows (`item.name`, `"Equipment: "..internal`), `planet_map` notify, `compat_utils.planet_display_name`'s capitalise-the-id — all become `localised_name` / `{"space-location-name."..id}` lookups. Pre-existing cosmetic bugs that localisation flushes out. |

---

## 5. Execution stages

Each stage is a locally-committed, individually playtestable slice (house rule: push only after in-game confirmation). English text is preserved byte-identical throughout.

- **Stage 0 — bug fixes, no refactor.** `[mod-info]` → `[mod-name]`/`[mod-description]`; add `mts_discord_url` description; internal-name fixes from §4. *Playtest: Mods GUI shows description; admin panel shows real item names.*
- **Stage 1 — infrastructure.** Split `locale/en/` files; checker tool (§6) wired into `tools/release.sh`; D2 helper/pipeline conversion; formatters return LocalisedStrings. Few keys move yet — this stage is signatures + tooling. *Playtest: existing messages unchanged.*
- **Stage 2 — commands + chat.** `scripts/commands/*` (129 strings, biggest dedup win), broadcast messages, join/leave/LFM, chat prefixes. *Playtest: command walkthrough, two-player join/leave.*
- **Stage 3 — GUI, module by module.** Order by player exposure: welcome/About + teams + team_card → pen/start-playing flow → research trio → stats/awards → admin panel last. ~350 strings. *Playtest per module; check fixed-width buttons for clipping.*
- **Stage 4 — milestones + events + Discord split.** D3 dual-path; research/rocket/records announcements. *Playtest: Discord output byte-identical to before.*
- **Stage 5 — storage migration + remote-api door-openers + sweep.** nav tooltip migration; D8 additive acceptance; full checker sweep; missing-key hunt (§6); save/load round-trip of a save created mid-conversion. *Playtest: the MTS testbed save (9 qualities, no space-age) plus a fresh multiplayer join.*

Rough scope for estimates: ~600 player/admin-visible strings → ~450 unique keys after dedup; ~180 call-site rewrites that involve restructuring concatenation; 8 helper-signature changes; 1 storage migration. Stages 2–4 are mechanical-but-careful; the risk concentrates in stages 1 and 5.

---

## 6. Tooling & verification (how we keep 750 conversions honest)

1. **Static checker** (`tools/check_locale.py`, wired into release): extract every literal `{"mts-*.…"}` key from Lua, extract every key from `locale/en/*.cfg`, fail on either-direction mismatch; verify `__n__` references don't exceed supplied parameter counts. Catches typos before the engine renders `Unknown key: '…'`.
2. **In-game missing-key detector**: a debug command that runs every `mts-*` key through `player.request_translations` and reports entries where `on_string_translated` returns `translated=false`. (Verified: the event carries exactly this boolean.) This also becomes the phase-2 per-language completeness check, for free.
3. **Playtest matrix for stage 5**: two connected clients with different locales (per-player language is the whole point — must see different languages simultaneously); Discord regression (unchanged output); save/load with the migrated nav storage; the world-rendered-text resolution question from D9.

---

## 7. Decisions I've made that you may want to override

| Decision | My call | Alternative |
|---|---|---|
| Admin-only GUI (107 strings) | Localise — same machinery, admins aren't necessarily English speakers | Skip, save ~15% of the work |
| Log/diag strings (78) | Stay English | Localisable `log()` is supported if you ever want it |
| Discord language | English, permanently | A server setting choosing the bridge language is possible in phase 2 |
| Welcome "About" page | Localise (most-read text for new players) | Keep English, it's a lot of long keys |
| Number formatting ("1.2k", "3.4M") | Keep as-is | Locale-aware suffixes later |
| Default team names ("Team 02") | Stay plain data (D7) | Display-time resolution — costs a data/display split everywhere names are used |

## 8. Phases 2 and 3, briefly

**Phase 2** = one directory per language under `locale/`, mirroring the en file structure; the 50 shipped codes are the menu — realistic first wave for the Factorio audience: de, fr, ru, pl, pt-BR, zh-CN, ja, es-ES, ko, uk. Translation drafts by model, plural branches per the ru/pl patterns in evidence, QA via the §6.2 in-game detector + per-GUI screenshots. No code changes.

**Phase 3 (LTR + family)**: LTR already has correct scaffolding (`[mod-setting-*]` and the `[string-mod-setting]` dropdown pattern — it was the verification example for that mechanic). Its runtime strings get this same playbook, smaller. The mts-v1 additive extensions (D8) land when LTR starts consuming them.
