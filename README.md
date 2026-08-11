# claude-statusline

Claude Code 2-row statusline script.

```
Opus 4.8 (1M) high | s ████████ 8% 53m  w ████████ 3% 2d19h | ctx ████████ 4%
SpaceCat | main ↑2
```

**Row 1** — Model name (+ context-size tag, effort level) · Session/weekly usage bars with reset countdown · Context usage bar (green <50%, amber ≥50%, red ≥75%)  
**Row 2** — Repo or directory · Branch · Git sync status (↑ push, ↓ pull, ↕ diverged)

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
