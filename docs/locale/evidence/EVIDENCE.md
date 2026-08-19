# Evidence index — MTS localisation sweep (2026-08-19)

Everything in this directory is the raw intermediate output behind [../PLAN.md](../PLAN.md) and [../INVENTORY.md](../INVENTORY.md), preserved for independent cross-examination by another model or reviewer. Repo state at sweep time: commit `e755abe`.

## How the data was produced

A 12-agent orchestrated workflow (run id `wf_554c16de-7c6`, 676,314 subagent tokens, 190 tool calls, ~6.4 min):

- **8 sweep agents** — partitioned all 111 Lua files (partition visible in `workflow-script.js`), read each file completely, and returned every display-bound string as structured JSON (schema in the script: file, line, category, text, status, assembly description, visibility, hazards).
- **2 docs agents** — verified Factorio localisation mechanics exclusively against the local install: `/home/shobhitg/factorio-2.0/doc-html/runtime-api.json` + `prototype-api.json` (api v6, application 2.0.77) and the shipped locale files under `/home/shobhitg/factorio-2.0/data/`. Every fact carries a source citation; unverifiable items are called out in `caveats` rather than asserted.
- **1 conventions agent** — read CONTEXT.md, README, chat-message-style skill, MTS_API.md, COMPAT.md, the existing locale.cfg, and traced the open-discord-bridge integration.
- **1 completeness-critic agent** — failed on a session usage limit before running; replaced by a scripted audit run from the main session (`audit-output.txt`).

## Files

| File | What it is |
|---|---|
| `workflow-script.js` | The exact orchestration script: agent prompts, JSON schemas, file partition, merge logic. |
| `workflow-result-full.json` | The workflow's merged return value: all 754 inventory entries, per-agent `finder_notes`, `runtimeFacts` + `localeFacts` (docs verification with citations), `conventions`, `scanned` file list. |
| `workflow-task-output-raw.json` | Unprocessed task harness output: run logs, per-agent progress metadata, token/tool-call accounting, and the critic agent's failure record. |
| `agent-transcripts/` | Full per-agent transcripts (`agent-*.jsonl` + meta), including every tool call each agent made, and `journal.jsonl` with each agent's raw return value. This is the primary cross-examination material: any inventory row or docs fact can be traced to the exact reads/greps that produced it. |
| `conventions-and-finder-notes.txt` | Human-readable dump of the conventions result and all 8 finder structural notes (same content as in the JSON, formatted). |
| `audit-output.txt` | The replacement completeness audit, run from the main session: (1) all 111 Lua files on disk appear in the scanned set; (2) zero files reported string-free contain display-pattern + word-literal hits; (3) 10 randomly sampled entries re-verified against actual file lines (seed 7, reproducible); (4) grep-verified absence of chart tags / shortcuts / custom-inputs / tips-and-tricks; (5) the `mts_discord_url` missing-description finding. |

## Known caveats to weigh during cross-examination

- Line numbers reference commit `e755abe`; they drift with subsequent edits (inventory.json is the canonical machine copy to re-anchor from).
- The plural syntax (`__plural_for_parameter__`) and special substitutions (`__CONTROL__`, `__ENTITY__`, …) are **not** in the JSON API docs; they were evidenced from shipped locale files only (exact paths/lines cited in `localeFacts`). The formal grammar lives on the wiki (Tutorial:Localisation), which was not available locally.
- Per-player client-side resolution of LocalisedString is inferred from three cited doc statements, not a single explicit sentence; flagged as such in `runtimeFacts` caveats.
- `[mod-setting-*]`/`[string-mod-setting]` sections were verified against the shipped changelog + the locally installed land-title-registry mod (no Wube-shipped mod defines settings).
- One sweep-note error was caught and corrected in PLAN §1: a finder claimed `display_panel_text` is plain-string-only; the docs verify it accepts LocalisedString.
- The critic agent never ran as an agent; its function was reproduced by the scripted audit above. The audit is narrower than the planned critic prompt (it did not adversarially re-read whole files), so residual risk concentrates in strings invisible to the audit's regex (e.g. a display string assigned via an unusual variable-only pattern). The 8 finder agents read every file in full, which bounds that risk.
