#!/usr/bin/env zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
print -r -- test-token >"$test_dir/.npm-token"

output=$(HOME="$test_dir" zsh -f -c '
  source "$1"
  print -r -- "${aliases[plf]}"
' -- "$repo_root/zshrc-work-mactop" 2>&1) || {
  print -u2 -- "Could not load work shell settings: $output"
  exit 1
}
expected='git fetch origin && git remote set-head origin --auto && git merge origin "$(git def)" && pnpm install && git add -A && git commit -m '"'"'pnpm-lock conflict fix'"'"' && git push'
[[ "$output" == "$expected" ]] || {
  print -u2 -- "Unexpected work plf alias: $output"
  exit 1
}

remote="$test_dir/remote.git"
seed="$test_dir/seed"
checkout="$test_dir/checkout"
git init -q --bare --initial-branch=master "$remote"
git init -q --initial-branch=master "$seed"
git -C "$seed" config user.name Test
git -C "$seed" config user.email test@example.invalid
print -r -- base >"$seed/conflict.txt"
git -C "$seed" add conflict.txt
git -C "$seed" commit -q -m base
git -C "$seed" remote add origin "$remote"
git -C "$seed" push -q origin master
git clone -q "$remote" "$checkout"
git -C "$checkout" config user.name Test
git -C "$checkout" config user.email test@example.invalid
git -C "$checkout" switch -q -c topic
print -r -- topic >"$checkout/conflict.txt"
git -C "$checkout" commit -q -am topic
original_head=$(git -C "$checkout" rev-parse HEAD)
print -r -- remote >"$seed/conflict.txt"
git -C "$seed" commit -q -am remote
git -C "$seed" push -q origin master
git -C "$checkout" update-ref refs/remotes/origin/stale "$original_head"
git -C "$checkout" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/stale

# Only the real Git executable is available; pnpm cannot install dependencies.
mkdir -p "$test_dir/bin"
ln -s "$(command -v git)" "$test_dir/bin/git"
run_plf() {
  HOME="$test_dir" WORK_PROFILE="$repo_root/zshrc-work-mactop" \
    CHECKOUT="$checkout" GIT_CONFIG_GLOBAL="$repo_root/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
    RESTRICTED_BIN="$test_dir/bin" zsh -f -s <<'EOF'
source "$WORK_PROFILE"
PATH="$RESTRICTED_BIN"
cd "$CHECKOUT"
plf
EOF
}

git -C "$checkout" remote set-url origin "$test_dir/unavailable.git"
if output=$(run_plf 2>&1); then
  print -u2 -- "Expected plf to stop when fetch fails"
  exit 1
fi
[[ "$output" == *'does not appear to be a git repository'* && "$output" != *'command not found'* ]] || {
  print -u2 -- "Expected a fetch failure without running pnpm: $output"
  exit 1
}
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original_head" && \
  -z "$(git -C "$checkout" ls-files -u)" ]] || {
  print -u2 -- "Expected a failed fetch not to alter the checkout"
  exit 1
}
git -C "$checkout" remote set-url origin "$remote"

if output=$(run_plf 2>&1); then
  print -u2 -- "Expected plf to stop on a real merge conflict"
  exit 1
fi
[[ "$output" == *'CONFLICT'* && "$output" != *'command not found'* ]] || {
  print -u2 -- "Expected a merge conflict without running pnpm: $output"
  exit 1
}
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$original_head" && \
  -n "$(git -C "$checkout" ls-files -u)" && \
  "$(git -C "$checkout" symbolic-ref refs/remotes/origin/HEAD)" == refs/remotes/origin/master ]] || {
  print -u2 -- "Expected the conflict to remain uncommitted and unstaged"
  exit 1
}

print -- "Work plf alias tests passed."
