#!/usr/bin/env zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

for role in personal professional; do
  test_home="$test_dir/$role"
  mkdir -p "$test_home"
  ln -s "$repo_root/gitconfig" "$test_home/.gitconfig"
  ln -s "$repo_root/gitconfig-$role" "$test_home/.gitconfig-local"

  if output=$(HOME="$test_home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$test_home/.gitconfig" \
    git config --global --includes --get gpg.ssh.allowedSignersFile 2>&1); then
    [[ "$role" == professional && "$output" == /Users/jackjackson/.ssh/allowed_signers ]] || {
      print -u2 -- "Unexpected SSH signature verification setting for $role: $output"
      exit 1
    }
  else
    exit_code=$?
    [[ "$role" == personal && "$exit_code" == 1 && -z "$output" ]] || {
      print -u2 -- "Unexpected Git config error for $role: $output"
      exit 1
    }
  fi
done

print -- "Git configuration tests passed."
