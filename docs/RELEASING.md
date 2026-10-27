# Releasing

One release line: `master`, versions 0.7.x, `factorio_version 2.1`. The Factorio 2.0 line (0.6.x on master, with 0.7.x on a `factorio-2.1` branch beside it) ended when 2.1 went stable; master became the 2.1 line in October 2026. The last 0.6.x release, 0.6.11, stays on the portal, and the in-game mod browser shows each player only the release that matches their game.

## Step by step

1. Test on 2.1: `python3 tools/check_locale.py`, `python3 tests/syntax_check.py`, `python3 tests/run.py`, then load on the headless rig (`~/factorio-dev/rig/start-server.sh 2.1 ...`) or in the clients (`~/factorio-test/players start 2 2.1`).
2. Bump per `.claude/skills/bump-version.md`: patch bump in `info.json`, changelog entry at the top of `changelog.txt`, README and welcome-panel check, commit.
3. Push master, then `./tools/release.sh`. It checks the clean tree, the changelog entry, the locale keys and that HEAD is on origin, then pushes the tag. GitHub Actions builds the zip, publishes the GitHub release with the changelog entries since the previous release, posts to Discord, uploads to the portal and syncs the portal page.
4. Confirm: `python3 tools/portal_check.py`, or `curl -s https://mods.factorio.com/api/mods/multi-team-support/full` and look for the new version with `"factorio_version": "2.1"`.

## Cadence and exceptions

- One release per week at most, per the house release discipline; same-day patches only for crash fixes.
- Companion mods (brave-new-mts, mts-dimension-warp, open-discord-bridge) declare the MTS version they need; a release they depend on goes out first.

## What the workflow does per tag, and what to check when it fails

`.github/workflows/release.yml` on the tagged commit: read `info.json`, find the previous published GitHub release on the same line (same `vMAJOR.MINOR.` prefix), extract the changelog entries down to it, build the zip (tools, docs, tests and scripts stripped), create the GitHub release, post the changelog to Discord, upload to the portal, sync the portal page, post the "live on the portal" ping. Both Discord titles name the Factorio version.

- Portal upload failed: the tag and GitHub release stand; re-run the "Upload to Mod Portal" workflow, it is idempotent.
- Release notes contain more than one entry: the previous release on that line was not found (the tag prefix changed, or the release list is missing it). The first release of a new line takes its newest entry alone. Edit the GitHub release text if it happens.
