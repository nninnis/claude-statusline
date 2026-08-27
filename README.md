# claude-statusline

Claude Code 2-row statusline script.

```
Opus 5 (1M) high | ctx ██████ 34% | s ██████ 41% 1h56m  w ██████ 12% 3d11h | $0.42
~/dev/claude-statusline | main ↑2 #1234 ✓
```

## Row 1 — the session

| | |
|---|---|
| `Opus 5 (1M) high` | Model name, context-window size, reasoning effort. `⚡` appears when fast mode is on |
| `ctx ██████ 34%` | How much of the context window is in use |
| `s ██████ 41% 1h56m` | 5-hour rate limit used, and time until that window resets |
| `w ██████ 12% 3d11h` | 7-day rate limit used, and time until that window resets |
| `$0.42` | Estimated session cost — see below |

Every bar is green below 50%, amber at 50%, red at 75%. Bars render at 0% from
the start of a session, so the row keeps its shape instead of growing once the
first API response arrives.

### What the `$` at the end means

Claude Code's own running estimate of what the current session has cost
(`cost.total_cost_usd`). It is calculated on your machine from token counts, so
treat it as a gauge rather than an invoice — it can differ from what you are
actually billed, and it resets to `$0.00` when `/clear` starts a new session.

On a Claude subscription you are not charged per session at all; the number is
still useful as a relative measure of how expensive a session is getting.

## Row 2 — the repository

| | |
|---|---|
| `~/dev/claude-statusline` | Repository root, or the working directory outside a repo |
| `main` | Current branch |
| `↑2` `↓3` `↕` | Commits ahead, behind, or diverged |
| `↻` | The remote state is unknown — see below |
| `#1234 ✓` | Open pull request and its review state: `✓` approved, `✗` changes requested, `○` pending, `◌` draft |

### Why `↻` shows up

The arrows compare your branch against `refs/remotes/<remote>/<branch>`, a
snapshot stored in `.git` that only `git fetch` refreshes. Nothing here reaches
the network, so a branch that has been behind for two weeks looks exactly like
one that is in sync.

When the last fetch is more than 30 minutes old the arrows are dimmed, and `↻`
appears if there are no arrows to dim. It means "no arrows, but I have not
looked lately" — run `git fetch` and it clears.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/nninnis/claude-statusline/main/setup.sh | bash
```

Restart Claude Code to apply.

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/nninnis/claude-statusline/main/setup.sh | bash
```

Same command — re-running overwrites the script and updates `settings.json`.
