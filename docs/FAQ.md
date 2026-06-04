# Frequently Asked Questions

Answers for founders and non-engineers using the Agile Flow template.

---

## "Why can't I push to main?"

The `main` branch is protected, which means nobody -- not even you -- can
push code to it directly. This is a safety net. All changes go through a
**pull request** (a proposal to add your changes) so they can be reviewed
and tested before they reach the live codebase. Think of `main` as the
published version of your project; edits have to be approved before they
go live.

**What to do:**

```bash
# Create a new branch (a private workspace) for your change
git checkout -b feature/my-change

# Make your changes, then push the branch
git add -A
git commit -m "feat: describe what you changed"
git push -u origin feature/my-change
```

Then open a pull request on GitHub to propose merging your branch into
`main`.

---

## "Why do I need three GitHub accounts?"

> **Solo developers:** You do not. You can use your personal GitHub
> account for everything. Bot accounts are optional and mainly useful for
> teams that want a clear audit trail.

For **team setups**, Agile Flow uses three separate identities so there is
a clear record of who did what. Your personal account is for final
decisions (approving and merging). A "worker" bot account writes code and
opens pull requests. A "reviewer" bot account reviews pull requests. This
separation means no single account can write code AND approve it, which
is a basic safety practice. You only set this up once.

**What to do:**

1. Create two extra free GitHub accounts (e.g., `yourcompany-worker` and
   `yourcompany-reviewer`).
2. Invite both accounts to your repository with **Write** access.
3. Log each account into the GitHub CLI:

```bash
gh auth login   # log in with your personal account
gh auth login   # log in with the worker bot account
gh auth login   # log in with the reviewer bot account
```

The system switches between them automatically after that.

---

## "What if CI fails?"

**CI** (Continuous Integration) is an automatic checker that runs every time
you push code or open a pull request. It looks for common mistakes --
formatting problems, broken tests, invalid files. If CI fails, your pull
request will show a red "X" instead of a green checkmark, and you should
fix the issue before merging.

**Quick fix:**

```bash
# See what failed -- go to your pull request on GitHub and click the
# red X next to the failed check, then "Details" to read the error.

# Common fixes:

# Fix markdown formatting issues
npx markdownlint --fix **/*.md

# Fix code style issues
uv run ruff check . --fix

# Re-run tests locally to see what broke
uv run pytest
```

If you are stuck, look at the CI error message -- it usually tells you
exactly which file and line has a problem.

---

## "How do I add a dependency?"

A **dependency** is a third-party package your project uses (for example,
a library for sending emails). How you add one depends on your project's
programming language.

**Quick fix:**

```bash
# Add a dependency to the project
uv add package-name

# Add a dev-only dependency (e.g., a test or lint tool)
uv add --dev package-name

# Then commit the change
git add -A
git commit -m "build: add package-name dependency"
```

After adding the dependency, push your branch and open a pull request so
the change is tracked.

---

## "What does the pre-push hook do?"

A **pre-push hook** is a script that runs automatically every time you try
to push code. It checks your code for errors and runs your tests *before*
the push goes through. If something fails, the push is blocked so broken
code never reaches GitHub. Think of it as a spell-checker that runs before
you hit send.

The hook auto-detects your project language (Python, Node.js, or Go) and
runs the appropriate linter and test suite.

**What to do if the push is blocked:**

```bash
# Read the error output in your terminal -- it tells you what failed.

# If it is a lint (code style) error, try the auto-fixer:
uv run ruff check . --fix

# If tests are failing, run them locally to see details:
uv run pytest

# Fix the issues, commit your fixes, then try pushing again.
git add -A
git commit -m "fix: resolve lint errors"
git push
```

Never use `git push --no-verify` to skip the hook. If broken code reaches
GitHub it will fail CI, block your pull request, and potentially break
other people's preview environments. The hook catches these problems
before they leave your machine.

---

## "Why does `/groom-backlog` fail with 'Resource not accessible by integration' even though my PAT has the project scope?"

You probably have a **fine-grained PAT** and the org you're trying to
manage hasn't allowlisted it. Two separate things have to be true for
fine-grained PATs to work on org-level Project v2 boards:

1. Your PAT has the right Permissions (`Projects: read/write`,
   `Contents: read/write`, etc.)
2. The **org admin** has enabled "Allow access via fine-grained personal
   access tokens" in the org's **Settings → Personal access tokens**
   policy AND specifically allowed your PAT (or all PATs)

Most workshop attendees don't admin the `vibeacademy` org and can't
toggle that policy. Hence the symptom — your PAT looks correctly
scoped, but it silently fails on every org-board mutation with
`Resource not accessible by integration`.

**Two fixes:**

1. **(Recommended for workshop attendees)** Switch to a **classic PAT**
   instead. Classic PATs bypass the allowlist entirely. Generate one at
   <https://github.com/settings/tokens> with `repo`, `project`,
   `workflow`, `read:org`. Update your `GH_TOKEN` Codespaces secret with
   the new value. Restart your Codespace.
2. **(If you are the org admin)** Enable the org-level allowlist policy
   at `https://github.com/organizations/<org>/settings/personal-access-tokens`,
   and approve your PAT in the resulting list.

The framework recommends classic for workshop attendees specifically
because option 2 requires org-admin access that workshop attendees
don't have. For solo developers on their own forks, fine-grained is
the better long-term choice (least-privilege, repo-scoped). See
`docs/GETTING-STARTED.md` "GitHub personal access token" section for
the full classic-vs-fine-grained walkthrough.

---

## "Why is Claude Code asking me to log in via browser in my Codespace?"

**Short answer:** That's the expected path for interactive Claude
Code, even in a Codespace, even with `ANTHROPIC_API_KEY` set. It is
not a misconfiguration.

Claude Code's interactive CLI (`claude`) authenticates via browser
OAuth against your Anthropic account or Claude.ai subscription. We
previously documented `ANTHROPIC_API_KEY` as a way to skip the
browser flow; this was empirically falsified on 2026-05-04 — with
the secret set as a Codespaces secret and the Codespace restarted,
`claude` still prompted for browser OAuth. The interactive CLI
prefers OAuth/subscription auth over the env var. (See #156 for
the original report.)

The browser flow itself works fine in a Codespace — VS Code Server
forwards the OAuth callback automatically. It's one extra click on
first run per Codespace, then the session is cached.

**Why set `ANTHROPIC_API_KEY` as a Codespaces secret at all?**

It's still recommended, but for different reasons than "skip the
browser":

1. **App-side Anthropic SDK calls** — if your fork has code that
   imports the Anthropic SDK and makes programmatic calls (e.g.,
   `app/llm/anthropic_client.py`), that code reads
   `ANTHROPIC_API_KEY` from env and has no browser fallback.
2. **Headless `claude -p "..."` invocations** — one-shot prompts
   from scripts, agent hooks, or CI-like flows can't open a
   browser; they need the env var.
3. **Billing separation** — using a pay-as-you-go API key for
   workshop work keeps Anthropic API spend separate from a
   personal Claude.ai subscription.

**If you set the secret, it MUST be a *Codespaces* secret, not an
Actions secret.** GitHub has two separate secret stores:

| Secret type | Where it appears | Visible to Codespaces? |
|-------------|------------------|------------------------|
| **Codespaces** secret | Settings → Codespaces → Codespaces secrets | Yes — injected as env var |
| **Actions** secret | Settings → Secrets and variables → Actions | No — only visible to workflow runs |

If you set `ANTHROPIC_API_KEY` as an Actions secret, processes in
your Codespace (your app code, `claude -p`) won't see it — the env
var simply isn't there.

**How to set it:**

1. Open `https://github.com/settings/codespaces`
2. Click **New secret** under "Codespaces secrets"
3. Name: `ANTHROPIC_API_KEY`. Value: a key from
   `https://console.anthropic.com/settings/keys`
4. **Repository access:** select your fork
5. Restart your Codespace so the new env var is injected

**For workshop facilitators** who want to fund attendees'
app-side / headless API usage centrally, set `ANTHROPIC_API_KEY`
as a **Codespaces org secret** scoped to the cohort's repos
instead of asking each attendee to bring their own. Interactive
`claude` sessions still authenticate per-attendee via browser
OAuth against each attendee's own account. See
`docs/PLATFORM-GUIDE.md` → "Anthropic API key (Claude Code
authentication)" and #104.

---

## "How do I see my preview environment?"

A **preview environment** is a temporary, live version of your app that is
created automatically when you open a pull request. It lets you (or
anyone you share the link with) test your changes in a real browser before
merging. Preview environments are cleaned up automatically when the pull
request is closed.

**What to do:**

1. Open a pull request on GitHub.
2. Wait a few minutes for the preview to build.
3. Look for a comment on your pull request from the deploy bot -- it
   will contain a URL you can click to visit the preview.

If you do not see a preview URL:

- Preview deploys require platform secrets to be configured. Check
  `docs/CI-CD-GUIDE.md` for the secrets your platform needs.
- The first preview for a project takes longer because the platform is
  setting things up for the first time.
- Check the **Actions** tab on GitHub for any build errors.

---

## "What if my deploy fails?"

A **deploy** is when your code goes live (gets published to the internet).
If a deploy fails, your previous working version stays live -- nothing
breaks for your users. You just need to find and fix the problem, then
push again.

**What to do:**

```bash
# 1. Check the Actions tab on GitHub for the deploy error details.

# 2. Fix the issue on your branch, commit, and push:
git add -A
git commit -m "fix: resolve deploy issue"
git push

# 3. If the site is down and you need to go back to the last working
#    version immediately, use the emergency rollback:
#    Go to GitHub > Actions > "Rollback Production" > "Run workflow"
#    Enter the reason for the rollback and click the green button.
```

If you are unsure what went wrong, check the deploy logs on your hosting
platform (Render, Vercel, etc.) for specific error messages.

---

## "What is a pull request?"

A **pull request** (often called a "PR") is a proposal to add your changes
to the main codebase. When you finish working on a feature or fix, you do
not put it directly into the main project. Instead, you open a pull request
that says "here are my changes -- please review them." Other people (or the
AI review agent) can look at what you changed, leave comments, and approve
it. Once approved, a human clicks "Merge" to add the changes to the main
project.

**What to do:**

```bash
# After pushing your branch:
gh pr create --title "Add my new feature" --body "Description of changes"

# Or just go to GitHub.com, navigate to your repository, and click the
# green "Compare & pull request" button that appears after you push a
# branch.
```

---

## "What does 'merge' mean?"

**Merging** is the act of combining your changes into the main codebase.
When you work on a branch, your changes are isolated -- only you can see
them. Merging takes those isolated changes and folds them into `main` so
they become part of the official project. In Agile Flow, only humans can
merge; the AI agents can propose and review changes, but a person always
makes the final call.

**What to do:**

1. Go to your pull request on GitHub.
2. Make sure all checks are green (CI passed, review approved).
3. Click the green **"Squash and merge"** button.
4. After merging, move the ticket to the **Done** column on your project
   board.

---

## "How do I upgrade to a newer version of Agile Flow?"

Run `/upgrade` from Claude Code. This checks for a newer release, syncs
framework files into your project, and opens a pull request for you to review.
Your application code and configuration are never touched.

For the full upgrade guide, alternative methods, and troubleshooting, see
[UPGRADING.md](UPGRADING.md).

---

## "Why did the agent create a branch?"

When you run `/work-ticket`, the AI agent picks up the next task and starts
working on it. The first thing it does is create a **branch** -- a separate
copy of the codebase where it can make changes without affecting the main
project. This is normal and expected. The branch name follows the pattern
`feature/issue-{number}-short-description` so you can tell which task it
relates to. After the agent finishes, it opens a pull request so you can
review the work before it goes live.

**What to do:**

Nothing -- this is automatic and expected. After the agent finishes:

1. Run `/review-pr` to get an AI review of the changes.
2. Go to the pull request on GitHub to see what changed.
3. If everything looks good, click **"Squash and merge"** to add the
   changes to your project.
