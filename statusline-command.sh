#!/bin/sh
export GIT_OPTIONAL_LOCKS=0

input=$(cat)
now=$(date +%s)
ESC=$(printf '\033')

# How recently `git fetch` must have run for the ahead/behind arrows to be
# trusted. Past this, they are dimmed — see the git section below.
FETCH_FRESH_MIN=30

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

bar() {
  # $1 = percentage (numeric, may be empty), $2 = width in chars (default 6)
  pct=$1
  width=${2:-6}
  if [ -z "$pct" ] || [ "$pct" = "null" ]; then
    return
  fi
  pct_int=$(printf '%.0f' "$pct")
  [ "$pct_int" -gt 100 ] && pct_int=100
  [ "$pct_int" -lt 0 ] && pct_int=0
  filled=$(( (pct_int * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  empty=$(( width - filled ))

  filled_str=""
  i=0
  while [ "$i" -lt "$filled" ]; do
    filled_str="${filled_str}█"
    i=$((i + 1))
  done

  empty_str=""
  i=0
  while [ "$i" -lt "$empty" ]; do
    empty_str="${empty_str}█"
    i=$((i + 1))
  done

  if [ "$pct_int" -ge 75 ]; then
    printf "\033[38;5;203m%s\033[0m\033[38;5;238m%s\033[0m" "$filled_str" "$empty_str"
  elif [ "$pct_int" -ge 50 ]; then
    printf "\033[38;5;214m%s\033[0m\033[38;5;238m%s\033[0m" "$filled_str" "$empty_str"
  else
    printf "\033[38;5;76m%s\033[0m\033[38;5;238m%s\033[0m" "$filled_str" "$empty_str"
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

# ── parse input ───────────────────────────────────────────────────────────────
# One jq call for every field. A process per field costs ~44ms each on Windows,
# which dominated the whole script. The model name is derived here too, for the
# same reason: it used to take a grep/sed/cut/awk chain.
#
# `claude-opus-5[1m]` -> `Opus 5 (1M)`, and a trailing 8-digit date is dropped so
# `claude-opus-4-5-20250929` -> `Opus 4.5`. Anything that is not a `claude-<name>`
# id falls back to the display name.
eval "$(printf '%s' "$input" | jq -r '
  (.model.id // "") as $raw
  | ($raw | capture("\\[(?<n>[0-9]+)(?<u>[mMkK])\\]") // null) as $ann
  | ($raw | gsub("\\[[^\\]]*\\]"; "")) as $id
  | (if ($id | test("^claude-[a-z]"))
     then ($id | ltrimstr("claude-") | split("-")) as $part
       | (($part[0] // "") | (.[0:1] | ascii_upcase) + .[1:]) as $family
       | ($part[1] // "") as $major
       | ($part[2] // "") as $minor
       | (if $minor == "" or ($minor | test("^[0-9]{8}$"))
          then $major
          else $major + "." + $minor
          end) as $version
       | ($family + " " + $version)
     else (.model.display_name // "?")
     end) as $name
  | @sh "model_name=\($name + (if $ann
                               then " (" + $ann.n + ($ann.u | ascii_upcase) + ")"
                               else "" end))",
    @sh "effort_level=\(.effort.level // "")",
    @sh "fast_mode=\(.fast_mode // false)",
    @sh "five_pct=\(.rate_limits.five_hour.used_percentage // 0)",
    @sh "five_resets=\(.rate_limits.five_hour.resets_at // "")",
    @sh "week_pct=\(.rate_limits.seven_day.used_percentage // 0)",
    @sh "week_resets=\(.rate_limits.seven_day.resets_at // "")",
    @sh "ctx_pct=\(.context_window.used_percentage // 0)",
    @sh "cost_usd=\(.cost.total_cost_usd // 0)",
    @sh "cwd=\(.workspace.current_dir // .cwd // "")",
    @sh "pr_num=\(.pr.number // "")",
    @sh "pr_state=\(.pr.review_state // "")"
' 2>/dev/null)"

# jq produces nothing at all if the input is not valid JSON
[ -n "$model_name" ] || model_name="?"
[ -n "$five_pct" ] || five_pct=0
[ -n "$week_pct" ] || week_pct=0
[ -n "$ctx_pct" ] || ctx_pct=0
[ -n "$cost_usd" ] || cost_usd=0

# ── effort level and fast mode ────────────────────────────────────────────────
[ -n "$effort_level" ] && model_name="${model_name} ${effort_level}"
[ "$fast_mode" = "true" ] && model_name="${model_name} ⚡"

# ── rate limits ───────────────────────────────────────────────────────────────
# Remaining time until 5h session window resets
five_time=""
if [ -n "$five_resets" ]; then
  five_remaining=$(( five_resets - now ))
  [ "$five_remaining" -lt 0 ] && five_remaining=0
  five_time=$(fmt_5h "$five_remaining")
fi

# Remaining time until 7d weekly window resets
week_time=""
if [ -n "$week_resets" ]; then
  week_remaining=$(( week_resets - now ))
  [ "$week_remaining" -lt 0 ] && week_remaining=0
  week_time=$(fmt_7d "$week_remaining")
fi

# ── build ctx segment (right after the model block) ───────────────────────────
ctx_pct_int=$(printf '%.0f' "$ctx_pct")
ctx_seg="ctx $(bar "$ctx_pct" 6) $(colorize "$ctx_pct" "${ctx_pct_int}%")"

# ── build rate limits segment (session · week, each with its own bar) ────────
five_pct_int=$(printf '%.0f' "$five_pct")
s_text="${five_pct_int}%"
[ -n "$five_time" ] && s_text="${s_text} ${five_time}"

week_pct_int=$(printf '%.0f' "$week_pct")
w_text="${week_pct_int}%"
[ -n "$week_time" ] && w_text="${w_text} ${week_time}"

rate_seg="s $(bar "$five_pct" 6) $(colorize "$five_pct" "$s_text")"
rate_seg="${rate_seg}  w $(bar "$week_pct" 6) $(colorize "$week_pct" "$w_text")"

# ── session cost ──────────────────────────────────────────────────────────────
cost_seg=$(printf '$%.2f' "$cost_usd")

# ── assemble row 1 ────────────────────────────────────────────────────────────
row1="${model_name} | ${ctx_seg} | ${rate_seg} | ${cost_seg}"

# ── git info for row 2 ────────────────────────────────────────────────────────
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd" 2>/dev/null

NL='
'
git_info=$(git rev-parse --show-toplevel --git-dir 2>/dev/null)
if [ -n "$git_info" ]; then
  git_root=${git_info%%"$NL"*}
  git_dir=${git_info#*"$NL"}

  case "$git_root" in
    "$HOME"*) dir="~${git_root#"$HOME"}" ;;
    *)        dir="$git_root" ;;
  esac

  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  branch="${branch:-HEAD}"

  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null)
  behind=$(git rev-list --count HEAD..@{u} 2>/dev/null)

  # `@{u}` is a local snapshot of the remote that only `git fetch` refreshes, so
  # a stale FETCH_HEAD means "behind 0" may just mean "haven't looked lately".
  # Dim the arrows when that snapshot is old, and show ↻ when there are no
  # arrows to dim — otherwise the untrustworthy case looks exactly like in-sync.
  if [ -n "$(find "$git_dir/FETCH_HEAD" -mmin "-$FETCH_FRESH_MIN" 2>/dev/null)" ]; then
    c_ahead="${ESC}[34m"
    c_behind="${ESC}[32m"
    c_both="${ESC}[38;5;214m"
    stale=""
  else
    c_ahead="${ESC}[38;5;244m"
    c_behind="$c_ahead"
    c_both="$c_ahead"
    stale=1
  fi

  git_icons=""
  if [ -n "$ahead" ] && [ -n "$behind" ]; then
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      # diverged — show a single ↕
      git_icons=" $(printf '%s\xe2\x86\x95\033[0m' "$c_both")"
    else
      [ "$ahead" -gt 0 ] && \
        git_icons="${git_icons} $(printf '%s\xe2\x86\x91%s\033[0m' "$c_ahead" "$ahead")"
      [ "$behind" -gt 0 ] && \
        git_icons="${git_icons} $(printf '%s\xe2\x86\x93%s\033[0m' "$c_behind" "$behind")"
    fi
    [ -z "$git_icons" ] && [ -n "$stale" ] && \
      git_icons=" $(printf '%s\xe2\x86\xbb\033[0m' "$c_ahead")"
  fi

  pr_seg=""
  if [ -n "$pr_num" ]; then
    case "$pr_state" in
      approved)          pr_mark=$(printf '\033[32m\xe2\x9c\x93\033[0m') ;;
      changes_requested) pr_mark=$(printf '\033[31m\xe2\x9c\x97\033[0m') ;;
      pending)           pr_mark=$(printf '\033[38;5;214m\xe2\x97\x8b\033[0m') ;;
      draft)             pr_mark=$(printf '\033[38;5;244m\xe2\x97\x8c\033[0m') ;;
      *)                 pr_mark="" ;;
    esac
    pr_seg=" $(printf '\033[38;5;39m#%s\033[0m' "$pr_num")"
    [ -n "$pr_mark" ] && pr_seg="${pr_seg} ${pr_mark}"
  fi

  row2="${dir} | ${branch}${git_icons}${pr_seg}"
else
  dir=${cwd:-$PWD}
  case "$dir" in
    "$HOME"*) dir="~${dir#"$HOME"}" ;;
  esac
  row2="$dir"
fi

# ── output ────────────────────────────────────────────────────────────────────
printf "%s\n%s" "$row1" "$row2"
