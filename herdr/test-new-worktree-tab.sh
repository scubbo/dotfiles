#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script=${SCRIPT:-"$repo_root/herdr/new-worktree-tab.sh"}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

origin="$test_dir/origin.git"
source_repo="$test_dir/source"
parent_repo="$test_dir/parent"

git init --bare "$origin" >/dev/null 2>&1
git init --initial-branch=trunk "$source_repo" >/dev/null 2>&1
git -C "$source_repo" config user.email 'test@example.com'
git -C "$source_repo" config user.name 'Test User'
printf 'initial\n' >"$source_repo/file"
git -C "$source_repo" add file
git -C "$source_repo" commit -m initial >/dev/null 2>&1
git -C "$source_repo" remote add origin "$origin"
git -C "$source_repo" push --set-upstream origin trunk >/dev/null 2>&1
git -C "$origin" symbolic-ref HEAD refs/heads/trunk
git clone "$origin" "$parent_repo" >/dev/null 2>&1

printf 'updated\n' >"$source_repo/file"
git -C "$source_repo" commit -am updated >/dev/null 2>&1
git -C "$source_repo" push >/dev/null 2>&1
expected_commit=$(git -C "$source_repo" rev-parse HEAD)

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/herdr" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2" = 'workspace list' ]; then
  printf '%s\\n' '{"result":{"workspaces":[{"focused":true,"workspace_id":"workspace-1","worktree":{"repo_root":"$parent_repo"}}]}}'
fi
EOF
chmod +x "$test_dir/bin/herdr"

if ! PATH="$test_dir/bin:$PATH" \
  HERDR_TAB_WORKTREE_ROOT="$test_dir/worktrees" \
  HERDR_TAB_LOG="$test_dir/new-worktree-tab.log" \
  "$script" >"$test_dir/script-output" 2>&1 <<'EOF'
Add feature
EOF
then
  cat "$test_dir/script-output" >&2
  exit 1
fi

parent_commit=$(git -C "$parent_repo" rev-parse HEAD)
worktree="$test_dir/worktrees/parent/Add-feature"
worktree_commit=$(git -C "$worktree" rev-parse HEAD)

[ "$parent_commit" = "$expected_commit" ] || {
  printf 'Parent repo was not updated to origin/trunk.\n' >&2
  exit 1
}

[ "$worktree_commit" = "$expected_commit" ] || {
  printf 'Worktree was not created from origin/trunk.\n' >&2
  exit 1
}

grep -Fq "result=success workspace_id=workspace-1 repo=$parent_repo branch=Add-feature" "$test_dir/new-worktree-tab.log" || {
  printf 'Expected successful worktree creation to be recorded in the log.\n' >&2
  exit 1
}
