#!/usr/bin/env zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home"
export HOME="$test_dir/home"
export GIT_CONFIG_GLOBAL="$repo_root/gitconfig"
export GIT_CONFIG_NOSYSTEM=1

for default_branch in master main release/stable; do
  case_dir="$test_dir/${default_branch//\//-}"
  remote="$case_dir/remote.git"
  seed="$case_dir/seed"
  checkout="$case_dir/checkout"
  mkdir -p "$case_dir"
  git init -q --bare --initial-branch="$default_branch" "$remote"
  git init -q --initial-branch="$default_branch" "$seed"
  git -C "$seed" config user.name "Test"
  git -C "$seed" config user.email "test@example.invalid"
  git -C "$seed" commit -q --allow-empty -m initial
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -q origin "$default_branch"
  git clone -q "$remote" "$checkout"
  git -C "$checkout" config user.name "Test"
  git -C "$checkout" config user.email "test@example.invalid"

  actual=$(git -C "$checkout" def) || {
    print -u2 -- "Could not determine default branch $default_branch"
    exit 1
  }
  [[ "$actual" == "$default_branch" ]] || {
    print -u2 -- "Expected default $default_branch, got $actual"
    exit 1
  }

  git -C "$checkout" branch domain
  git -C "$checkout" branch feature/main-task
  git -C "$checkout" branch already-merged
  git -C "$checkout" switch -q -c unmerged
  git -C "$checkout" commit -q --allow-empty -m unmerged
  git -C "$checkout" switch -q -c topic "$default_branch"

  output=$(git -C "$checkout" clean-branches 2>&1) || {
    print -u2 -- "Cleanup failed for $default_branch: $output"
    exit 1
  }
  for retained in "$default_branch" topic unmerged; do
    git -C "$checkout" show-ref --verify --quiet "refs/heads/$retained" || {
      print -u2 -- "Cleanup deleted $retained with default $default_branch"
      exit 1
    }
  done
  for deleted in domain feature/main-task already-merged; do
    if git -C "$checkout" show-ref --verify --quiet "refs/heads/$deleted"; then
      print -u2 -- "Cleanup did not delete merged branch $deleted"
      exit 1
    fi
  done

  output=$(git -C "$checkout" nb next-branch 2>&1) || {
    print -u2 -- "Creating a branch from $default_branch failed: $output"
    exit 1
  }
  [[ "$(git -C "$checkout" branch --show-current)" == next-branch ]] || {
    print -u2 -- "Expected next-branch to be checked out"
    exit 1
  }
  [[ "$(git -C "$checkout" rev-parse HEAD)" == "$(git -C "$checkout" rev-parse "refs/heads/$default_branch")" ]] || {
    print -u2 -- "Expected next-branch to start from $default_branch"
    exit 1
  }

  git -C "$checkout" branch preserve-missing
  git -C "$checkout" symbolic-ref --delete refs/remotes/origin/HEAD
  for action in def clean-branches nb; do
    if output=$(git -C "$checkout" "$action" 2>&1); then
      print -u2 -- "Expected $action to fail without a default branch"
      exit 1
    fi
    [[ "$output" == *'Cannot determine the default branch'* ]] || {
      print -u2 -- "Expected $action to explain the missing default branch: $output"
      exit 1
    }
  done
  for retained in "$default_branch" preserve-missing; do
    git -C "$checkout" show-ref --verify --quiet "refs/heads/$retained" || {
      print -u2 -- "Missing origin/HEAD must not delete $retained"
      exit 1
    }
  done
  git -C "$checkout" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/missing
  if output=$(git -C "$checkout" def 2>&1); then
    print -u2 -- "Expected def to fail for a missing remote-tracking branch"
    exit 1
  fi
  [[ "$output" == *'Cannot determine the default branch'* ]] || {
    print -u2 -- "Expected an error for a missing remote-tracking branch: $output"
    exit 1
  }

  git -C "$checkout" symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$default_branch"
  git -C "$checkout" switch -q --detach
  if output=$(git -C "$checkout" clean-branches 2>&1); then
    print -u2 -- "Expected cleanup to fail with a detached HEAD"
    exit 1
  fi
  [[ "$output" == *'Cannot clean branches with a detached HEAD.'* ]] || {
    print -u2 -- "Expected an error for a detached HEAD: $output"
    exit 1
  }
  git -C "$checkout" show-ref --verify --quiet refs/heads/preserve-missing || {
    print -u2 -- "Detached HEAD must not delete branches"
    exit 1
  }
done

print -- "Default-branch alias tests passed."
