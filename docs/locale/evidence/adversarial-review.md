# Adversarial review: localization migration `2ed28e5..HEAD` (pre-fix state)

Independent single-agent review run 2026-08-19 after both conversion workflows and
the final sweep landed (reviewing `2ed28e5..342183d`); findings F1–F3 and the F5
comment refreshes were fixed in commit `0dd14e3`. Report reproduced verbatim.

---

**Preflight:** `python3 tools/check_locale.py` → `472 referenced, 472 defined, 0 errors, 0 warnings` — confirmed. Mechanics were verified against the local install, not memory: `__plural_for_parameter__N__{...}__` syntax and `ends in N` patterns (`~/factorio/data/core/locale/en/core.cfg`), `time-symbol-*-short` are root-scope core keys (`=__1__m`/`=__1__h`), the `{"?", ...}` fallback picks the first valid parameter (doc-html/concepts/LocalisedString.html), and leading-space locale values are engine-preserved (core.cfg itself ships `unconfirmed-mod-changes= __1__ ...`).

**Bottom line: no crash-severity bugs found.** The migration is unusually clean mechanically. What survived scrutiny: 2 wrong-text findings, 1 English-drift judgment call, and a cluster of cosmetic/latent issues.

## Findings

**F1. wrong-text — `scripts/chat_channel.lua:107-125` was never migrated (scope gap, no deferral marker).**
`announce()` still builds hardcoded English: `"Team chat is now " .. state .. " (switched by " .. ... .. ")."`, printed to every member on every GLOBAL/TEAM HUD-switch click or `/mts-chat` (via `hud_clock.select_channel` → `chat_channel.set_for`). Its GUI twin `gui/chat_switch.lua` was fully converted in this diff, and every other deliberately-deferred string carries a `TODO(locale-stage5)` comment — this file has neither.

**F2. wrong-text (visible in English today) — `locale/en/gui-stats.cfg:52` `awards-match-count` plural inverts verb agreement.**
`__plural_for_parameter__1__{1=match|rest=matches}__` renders "1 / 5 **match**" but "3 / 5 **matches**" — exactly backwards for the verb reading (singular subject → "matches", plural → "match").

**F3. wrong-text (latent) — `/mts-players` feeds the localised template its plain-English twins. `scripts/commands/team.lua:98-99`.**
Uses plain `name`/`location` fields (raw prototype ids, untranslatable `"in transit"`, hardcoded `planet_disp .. " base"`) while `collect_team_surfaces` builds `ls_name`/`ls_location` twins precisely for this; `gui/team_card.lua` did migrate, so this is a missed last holdout, not a decision.

**F4. cosmetic — inconsistent fallback capitalisation in `gui/teams_data.lua:43`** (platform rows pass lowercase fallback; planet-surface sites capitalise). Only visible for a modded space location lacking a `space-location-name.*` entry; matches pre-migration output — not a regression. NOT fixed.

**F5. cosmetic — four stale "dual API" comments that now lie about their consumers** (a hazard for the planned fold-away sweep): `scripts/spectator/events.lua:230-231`, `gui/hud_clock.lua:68-70`, `gui/friendship.lua:18-21`, `gui/teams_data.lua:28-31`.

**F6. cosmetic, pre-existing — `mts-cmd.trim-skipped-no-force`** can render `"X (X): ..."` since `label` falls back to `surface.name` on exactly the branch that fires. Faithful to the old concat. NOT fixed.

**F7. drift, likely sanctioned — welcome-back names are now colored** (old text used plain `player.name`). Consistent with house chat style rule 1 and the sanctioned first-join welcome colorization. Judged sanctioned; kept.

## Category-by-category verdicts

1. **CONCAT-ON-TABLE: clean.** All 234 `..` sites traced with operand back-tracing (not pattern-matching). The three dangerous-looking ones live inside the retained plain twins whose inputs are all plain fields.
2. **TABLE-TO-STRING-SINK: clean.** Bridge (`remote_api.lua` `bridge_text`, `emit_*`), milestones' bridge path kept deliberately-plain parallel values that never share a variable with the LS path. `player.tag`, all `log()` sites, all storage writes, textfield `.text` reads, and `pen_info_panel.set_text` (type-guarded) are plain.
3. **PARAM MISMATCH: 80 keys with `__2__`+ fully audited — zero arity/order mismatches** (brace-balanced multi-line-aware counting across all 472 references). Only F2's plural index survived.
4. **ENGLISH DRIFT: ~35 hunks sampled — byte-identical except sanctioned conversions, F2, and F7.** Every formatter twin verified equal (`ls_duration`, `ls_duration_coarse`, `ls_elapsed`, `ls_fmt_ago`, `ls_fmt_playtime`, `ls_clock_caption`). Whitespace-bearing values verified on disk (`welcome-tab-about=  About  ` trailing spaces intact — fragile against editor trailing-whitespace stripping, worth a checker rule).
5. **LOST BEHAVIOR: clean.** nil-contracts preserved for every ls_ twin; `friendship.get_state`'s 6-return consumed correctly; `build_popup`'s signature change updated at both call sites; `chunk_trim.start`/`team_rename.attempt` err-returns only ever reach `print`.
6. **BROKEN COMPOSITION: clean.** Every space-carrying seam checked (leading-space tails, ` (offline)` suffixes, `force_tag` seams, `" · "` separators, double-space layout indents). `helpers.ls_join` sits exactly at the 20-param ceiling, not over.
7. **NIL PARAMETERS: clean — zero constructors can receive nil/false.** All 188 `{"mts-...", ...}` constructors parsed and every non-literal param traced. Fragile-but-safe invariants worth knowing: `helpers.display_name(nil)` returns nil and feeds params at six (all currently guarded) sites — the likeliest future break; `ls_duration`/`ls_duration_coarse`/`ls_fmt_ago` crash on nil ticks rather than truncating (unlike `ls_elapsed`); `global_milestones.lua:157`'s `or {"mts-milestone.a-team"}` is dead (left side is total), misleading about the contract.
