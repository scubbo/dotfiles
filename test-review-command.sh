#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
command_file="$repo_root/opencode/.config/opencode/commands/review.md"

grep -Fq 'default_branch=$(git def)' "$command_file" || {
  printf '%s\n' 'Expected review to resolve the repository default with git def' >&2
  exit 1
}
grep -Fq 'refs/remotes/origin/$default_branch' "$command_file" || {
  printf '%s\n' 'Expected review to use the remote-tracking default branch' >&2
  exit 1
}
grep -Fq 'Use the ref from `--base=<ref>` if provided.' "$command_file" || {
  printf '%s\n' 'Expected review to retain the explicit base option' >&2
  exit 1
}
if grep -Eq 'git diff main\.\.\.HEAD|default: `main`|compared to `main`' "$command_file"; then
  printf '%s\n' 'Expected review not to hard-code main as its default base' >&2
  exit 1
fi

printf '%s\n' 'Review command tests passed.'
