---
description: "Pull the latest framework updates from vibeacademy/agile-flow into this fork"
---

# /pull-upstream — Apply Upstream Framework Updates

Pulls the latest agent prompts, commands, hooks, and skills from the upstream
`vibeacademy/agile-flow` repo into this GCP fork. Safe to run mid-workshop.
Only framework files are updated — your application code is never touched.

## Instructions

1. **Verify clean working tree** — run `git status --porcelain`.
   If there are uncommitted changes, STOP and report:

   ```
   Your working tree has uncommitted changes. Please commit or stash them
   before running /pull-upstream:
     git stash
     /pull-upstream
   ```

2. **Run the sync script**:

   ```bash
   bash scripts/pull-upstream.sh
   ```

3. **Parse the output** and report what happened. The script will print one of:

   - **Already up to date** — no action needed.
   - A list of `UPDATED` / `ADDED` file lines, followed by a commit
     confirmation and a push reminder.
   - **ERROR** — report the error message with the suggested fix.

4. **If changes were applied**, push immediately so Codespace participants
   get the update:

   ```bash
   git push origin HEAD
   ```

   Then report:

   ```
   Upstream sync complete. N file(s) updated and pushed.
   Participants can pull the latest with:
     git pull
   ```

5. **If already up to date**, report:

   ```
   Already up to date with upstream. No changes applied.
   ```

## Important

- This command is designed for facilitators running it mid-workshop from a
  Codespace. It commits and pushes automatically.
- Files listed in `.agile-flow-overrides` are intentionally GCP-customised
  and will never be overwritten.
- Only files that exist in the upstream repo AND are in the syncDirectories
  list (`.agile-flow-version`) are updated.
- Application code, migrations, infrastructure files, and GCP-specific
  scripts are never touched.

### Output Format

End your output with a Result Block:

```
---

**Result:** Upstream sync complete
Files updated: N
Commit: <short SHA>
Pushed: yes
```

Or if already up to date:

```
---

**Result:** Already up to date
No changes applied.
```

Or if an error occurred:

```
---

**Result:** Sync failed
Error: <message>
Fix: <suggested action>
```
