#!/usr/bin/env bash
# Create a git worktree for the focused workspace's repo and open it as a tab
# in that same workspace, so one workspace = one repo and one tab = one worktree.
set -euo pipefail

# Where tab-scoped worktrees live. Independent of herdr's [worktrees] directory,
# which only governs the built-in worktree-as-workspace flow.
WT_ROOT="${HERDR_TAB_WORKTREE_ROOT:-$HOME/.herdr/worktrees}"

die() {
  printf '\n%s\n' "$*" >&2
  printf 'Press any key to close… '
  read -rsn1 || true
  exit 1
}

ws=$(herdr workspace list | jq -c '.result.workspaces[] | select(.focused)') ||
  die "Could not reach the herdr API."
[ -n "$ws" ] || die "No focused workspace."

ws_id=$(jq -r '.workspace_id' <<<"$ws")
repo=$(jq -r '.worktree.repo_root // empty' <<<"$ws")

if [ -z "$repo" ]; then
  # Only workspaces created through herdr's worktree flow carry repo metadata.
  # For plain cwd workspaces, fall back to the workspace's focused pane and let
  # git decide whether we're in a repo. --git-common-dir (not --show-toplevel)
  # so a pane sitting in a linked worktree resolves to the main checkout.
  active_tab=$(jq -r '.active_tab_id // empty' <<<"$ws")
  cwd=$(herdr pane list | jq -r --arg ws "$ws_id" --arg tab "$active_tab" '
    [.result.panes[] | select(.workspace_id == $ws)]
    | (map(select(.focused)) + map(select(.tab_id == $tab)) + .)[0]
    | .foreground_cwd // .cwd // empty')
  [ -n "$cwd" ] || die "Could not determine the focused pane's directory."
  git_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    die "Focused workspace is not inside a git repo ($cwd)."
  repo=$(dirname "$git_dir")
fi

printf 'Repo: %s\n' "$repo"
read -rp 'Topic: ' topic
[ -n "$topic" ] || exit 0

# Git refnames permit more than this, but restricting to alphanumerics, hyphen
# and underscore keeps the branch shell-safe and rules out the awkward cases
# (leading dot, "..", a ".lock" suffix) without needing to check for them.
branch=$(printf '%s' "$topic" | tr -c 'A-Za-z0-9_-' '-' | tr -s '-')
branch="${branch#-}"
branch="${branch%-}"
[ -n "$branch" ] || die "Topic has no characters usable in a branch name."
printf 'Branch: %s\n' "$branch"

dir="$WT_ROOT/$(basename "$repo")/$branch"

if [ -d "$dir" ]; then
  : # already checked out; just open a tab on it
elif git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$repo" worktree add "$dir" "$branch" || die "git worktree add failed."
else
  git -C "$repo" worktree add -b "$branch" "$dir" || die "git worktree add failed."
fi

herdr tab create --workspace "$ws_id" --cwd "$dir" --label "$topic" --focus >/dev/null ||
  die "Worktree created at $dir but the tab could not be opened."
