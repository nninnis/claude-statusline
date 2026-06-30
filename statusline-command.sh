#!/bin/sh
export GIT_OPTIONAL_LOCKS=0

input=$(cat)
now=$(date +%s)

# ── helpers ───────────────────────────────────────────────────────────────────

colorize() {
  # $1 = percentage (numeric, may be empty), $2 = text to print
  pct=$1
  text=$2
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    printf "%s" "$text"
    return
  fi
  pct_int=$(printf '%.0f' "$pct")
  if [ "$pct_int" -ge 75 ]; then
    printf "\033[31m%s\033[0m" "$text"
  elif [ "$pct_int" -ge 50 ]; then
    printf "\033[38;5;214m%s\033[0m" "$text"
  else
    printf "%s" "$text"
  fi
}

fmt_5h() {
  # format seconds as e.g. 3h24m or 45m
  secs=$1
  h=$(( secs / 3600 ))
  m=$(( (secs % 3600) / 60 ))
  if [ "$h" -eq 0 ]; then
    echo "${m}m"
  elif [ "$m" -eq 0 ]; then
    echo "${h}h"
  else
    echo "${h}h${m}m"
  fi
}

fmt_7d() {
  # format seconds as e.g. 3d2h or 5h
  secs=$1
  d=$(( secs / 86400 ))
  h=$(( (secs % 86400) / 3600 ))
  if [ "$d" -eq 0 ]; then
    echo "${h}h"
  elif [ "$h" -eq 0 ]; then
    echo "${d}d"
  else
    echo "${d}d${h}h"
  fi
}

# ── model name ────────────────────────────────────────────────────────────────
raw_model_id=$(echo "$input" | jq -r '.model.id // ""')
# Extract context-size annotation like [1m] before stripping brackets
ctx_annotation=""
bracket=$(echo "$raw_model_id" | grep -oE '\[[0-9]+[mMkK]\]' | head -1)
if [ -n "$bracket" ]; then
  # Normalise: extract the number+unit, uppercase the unit
  inner=$(echo "$bracket" | tr -d '[]')
  num=$(echo "$inner" | sed 's/[^0-9]//g')
  unit=$(echo "$inner" | sed 's/[0-9]//g' | tr '[:lower:]' '[:upper:]')
  ctx_annotation="${num}${unit}"
fi
model_id=$(echo "$raw_model_id" | sed 's/\[[^]]*\]//g')

if echo "$model_id" | grep -qE '^claude-[a-z]'; then
  family=$(echo "$model_id" | sed 's/^claude-//' | cut -d'-' -f1)
  rest=$(echo "$model_id" | sed "s/^claude-${family}-//")
  major=$(echo "$rest" | cut -d'-' -f1)
  minor=$(echo "$rest" | cut -d'-' -f2)
  # If minor is empty or is an 8-digit date suffix, omit it
  if [ -z "$minor" ] || echo "$minor" | grep -qE '^[0-9]{8}$'; then
    version="$major"
  else
    version="${major}.${minor}"
  fi
  cap=$(echo "$family" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  case "$family" in
    *)    model_name="${cap} ${version}" ;;
  esac
else
  model_name=$(echo "$input" | jq -r '.model.display_name // "?"')
fi
[ -n "$ctx_annotation" ] && model_name="${model_name} (${ctx_annotation})"

# ── rate limits ───────────────────────────────────────────────────────────────
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Elapsed time for 5h session window
five_time=""
if [ -n "$five_resets" ]; then
  five_remaining=$(( five_resets - now ))
  five_elapsed=$(( 18000 - five_remaining ))   # 5 * 3600 = 18000
  [ "$five_elapsed" -lt 0 ] && five_elapsed=0
  five_time=$(fmt_5h "$five_elapsed")
fi

# Elapsed time for 7d weekly window
week_time=""
if [ -n "$week_resets" ]; then
  week_remaining=$(( week_resets - now ))
  week_elapsed=$(( 604800 - week_remaining ))  # 7 * 24 * 3600 = 604800
  [ "$week_elapsed" -lt 0 ] && week_elapsed=0
  week_time=$(fmt_7d "$week_elapsed")
fi

# ── context window ────────────────────────────────────────────────────────────
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# ── build rate limits segment ─────────────────────────────────────────────────
rate_seg=""
if [ -n "$five_pct" ]; then
  five_pct_int=$(printf '%.0f' "$five_pct")
  s_text="s:${five_pct_int}%"
  [ -n "$five_time" ] && s_text="${s_text} ${five_time}"
  rate_seg=$(colorize "$five_pct" "$s_text")
fi

if [ -n "$week_pct" ]; then
  week_pct_int=$(printf '%.0f' "$week_pct")
  w_text="w:${week_pct_int}%"
  [ -n "$week_time" ] && w_text="${w_text} ${week_time}"
  w_colored=$(colorize "$week_pct" "$w_text")
  if [ -n "$rate_seg" ]; then
    rate_seg="${rate_seg}  ${w_colored}"
  else
    rate_seg="$w_colored"
  fi
fi

# ── build ctx segment ─────────────────────────────────────────────────────────
ctx_seg=""
if [ -n "$ctx_pct" ]; then
  ctx_pct_int=$(printf '%.0f' "$ctx_pct")
  ctx_text="ctx: ${ctx_pct_int}%"
  ctx_seg=$(colorize "$ctx_pct" "$ctx_text")
fi

# ── assemble row 1 ────────────────────────────────────────────────────────────
row1="$model_name"
if [ -n "$rate_seg" ] && [ -n "$ctx_seg" ]; then
  row1="${row1} | ${rate_seg} | ${ctx_seg}"
elif [ -n "$rate_seg" ]; then
  row1="${row1} | ${rate_seg}"
elif [ -n "$ctx_seg" ]; then
  row1="${row1} | ${ctx_seg}"
fi

# ── git info for row 2 ────────────────────────────────────────────────────────
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null

git_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$git_root" ]; then
  dir=$(echo "$git_root" | sed "s|^$HOME|~|")
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  branch="${branch:-HEAD}"

  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)

  git_icons=""
  if [ -n "$ahead" ] && [ -n "$behind" ] && [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
    # diverged — show single ↕ in amber
    git_icons=" $(printf '\033[38;5;214m\xe2\x86\x95\033[0m')"
  else
    [ -n "$ahead" ] && [ "$ahead" -gt 0 ] && \
      git_icons="${git_icons} $(printf '\033[34m\xe2\x86\x91%s\033[0m' "$ahead")"
    [ -n "$behind" ] && [ "$behind" -gt 0 ] && \
      git_icons="${git_icons} $(printf '\033[32m\xe2\x86\x93%s\033[0m' "$behind")"
  fi

  row2="${dir} | ${branch}${git_icons}"
else
  dir=$(echo "${cwd:-$(pwd)}" | sed "s|^$HOME|~|")
  row2="$dir"
fi

# ── output ────────────────────────────────────────────────────────────────────
printf "%s\n%s" "$row1" "$row2"
