# Bump Version

## When to use
When the user asks to bump the version, release a new version, or after the version in `info.json` has been changed.

## Steps

1. **Bump the version in `info.json`** if not already done. Follow semver: patch for bugfixes, minor for features, major for breaking changes. Ask the user which component to bump if unclear.

2. **Generate a changelog entry** at the top of `changelog.txt`:
   - Determine the previous version's git tag (format: `v<old_version>`). If no tag exists, use `git log` to find commits since the last changelog entry.
   - Collect the diff: `git log --pretty=format:"- %s" v<old_version>..HEAD` (exclude "Bump version" commits).
   - Write a new entry at the **top** of `changelog.txt` following the existing format exactly:
     ```
     ---------------------------------------------------------------------------------------------------
     Version: <new_version>
     Date: <YYYY-MM-DD>
       Features:
         - ...
       Changes:
         - ...
       Bugfixes:
         - ...
     ```
   - Only include sections (Features, Changes, Bugfixes) that have entries. Categorize each commit appropriately. Reword commit messages into clear, user-facing descriptions — don't just paste raw commit subjects.
   - Show the draft entry to the user for approval before writing it.

3. **Recreate mod symlinks** by running:
   ```bash
   ./link-mod.sh
   ```
   This removes old `multi-team-support_*` symlinks and creates new ones with the current version in both `~/factorio/mods/` and `~/.factorio/mods/`.

4. **Commit the version bump**: stage `info.json` and `changelog.txt`, then commit with message: `Bump version to <new_version>`.
