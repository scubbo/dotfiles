#!/usr/bin/env bash
# Adapted from ~/.config/herdr/new-worktree-tab.sh.
# One Rex session = one repo; one tab = one worktree.
set -euo pipefail

WT_ROOT="${REX_TAB_WORKTREE_ROOT:-$HOME/.rex/worktrees}"
LOG="${REX_TAB_LOG:-${XDG_CONFIG_HOME:-$HOME/.config}/rex/new-worktree-tab.log}"
mkdir -p "$(dirname "$LOG")"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG"
}

run() {
  local step=$1
  shift
  log "step=$step status=started"
  if "$@" >>"$LOG" 2>&1; then
    log "step=$step status=completed"
  else
    log "step=$step status=failed"
    return 1
  fi
}

outcome=failure
on_exit() {
  local status=$?
  log "result=$outcome session_id=${session_id:-} repo=${repo:-} branch=${branch:-} exit_code=$status dir=${dir:-}"
}
trap on_exit EXIT
log "result=started"

die() {
  log "error=$*"
  printf '\n%s\nSee %s for details.\n' "$*" "$LOG" >&2
  if [ -t 0 ]; then
    printf 'Press any key to close… '
    read -rsn1 || true
  fi
  exit 1
}

session_id=${1:-${REX_SESSION:-}}
cwd=${2:-$PWD}
client_id=${3:-${REX_CLIENT:-}}
[ -n "$session_id" ] || die "No Rex session. Run this from New Worktree Tab in Rex."

# --git-common-dir resolves a linked worktree back to the main checkout,
# just as the Herdr helper does.
if ! git_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  printf 'Current directory is not inside a Git repo (%s).\n' "$cwd"
  while :; do
    if ! IFS= read -rp 'Repository path (blank to cancel): ' repo_path || [ -z "$repo_path" ]; then
      outcome=cancelled
      exit 0
    fi

    # Expand only ~/ and resolve relative paths from the source terminal.
    # Never evaluate the input as shell code; spaces in paths stay literal.
    case "$repo_path" in
      \~) repo_path=$HOME ;;
      \~/*) repo_path="$HOME/${repo_path#\~/}" ;;
    esac
    case "$repo_path" in
      /*) ;;
      *) repo_path="$cwd/$repo_path" ;;
    esac

    if git_dir=$(git -C "$repo_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      break
    fi
    printf 'Not a Git repository: %s\n' "$repo_path" >&2
  done
fi
repo=$(dirname "$git_dir")

printf 'Repo: %s\n' "$repo"
if ! read -rp 'Topic: ' topic || [ -z "$topic" ]; then
  outcome=cancelled
  exit 0
fi

branch=$(printf '%s' "$topic" | LC_ALL=C tr -c 'A-Za-z0-9_-' '-' | tr -s '-')
branch="${branch#-}"
branch="${branch%-}"
[ -n "$branch" ] || die "Topic has no characters usable in a branch name."
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "Topic is not a valid branch name."
printf 'Branch: %s\n' "$branch"

dir="$WT_ROOT/$(basename "$repo")/$branch"
log "session_id=$session_id repo=$repo branch=$branch dir=$dir"

if [ -e "$dir" ] || [ -L "$dir" ]; then
  # Do not silently open an unrelated directory that happens to have this name.
  existing_git_dir=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    die "Worktree path already exists but is not a Git worktree ($dir)."
  existing_root=$(git -C "$dir" rev-parse --show-toplevel)
  existing_branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD) ||
    die "Worktree path already exists with a detached HEAD ($dir)."
  [ "$existing_git_dir" = "$git_dir" ] &&
    [ "$existing_root" = "$(cd "$dir" && pwd -P)" ] &&
    [ "$existing_branch" = "$branch" ] ||
    die "Worktree path belongs to another checkout or branch ($dir)."
else
  default_branch=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD) ||
    die "Could not determine origin's default branch."
  default_branch=${default_branch#origin/}
  log "default_branch=$default_branch"

  # Unlike Herdr's pull, fetch does not merge into or modify the main checkout.
  printf 'Fetching origin/%s…\n' "$default_branch"
  run fetch-default git -C "$repo" fetch origin "$default_branch" ||
    die "Could not fetch origin/$default_branch."

  if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    run create-worktree git -C "$repo" -c checkout.workers=4 worktree add "$dir" "$branch" ||
      die "git worktree add failed."
  else
    run create-worktree git -C "$repo" -c checkout.workers=4 worktree add -b "$branch" "$dir" "origin/$default_branch" ||
      die "git worktree add failed."
  fi
fi

log "step=create-tab status=started"
if ! created=$(rex window new -s "$session_id" "$topic" -c "$dir" --focus --json 2>>"$LOG"); then
  log "step=create-tab status=failed"
  die "Worktree created at $dir but the tab could not be opened."
fi
printf '%s\n' "$created" >>"$LOG"
log "step=create-tab status=completed"
window_id=$(jq -er '.window_id | strings | select(length > 0)' <<<"$created" 2>>"$LOG") ||
  die "Rex did not return a tab ID."

client_args=()
if [ -n "$client_id" ]; then
  client_args=(-C "$client_id")
fi
run select-tab rex "${client_args[@]}" 'do' session.select "session_id=$session_id" "window_id=$window_id" ||
  die "The worktree tab opened, but Rex.app could not select it."
outcome=success
