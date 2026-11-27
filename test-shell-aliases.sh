#!/usr/bin/env zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

for profile in zshrc-local-linux zshrc-local-mactop zshrc-local-pi zshrc-work-mactop; do
  test_home="$test_dir/$profile"
  mkdir -p "$test_home"
  ln -s "$repo_root/zshrc" "$test_home/.zshrc"
  ln -s "$repo_root/$profile" "$test_home/.zshrc-local"
  ln -s "$repo_root/envFolder" "$test_home/.env"
  ln -s "$repo_root/bin" "$test_home/bin"
  print -r -- test-token >"$test_home/.npm-token"

  if [[ "$profile" == zshrc-work-mactop ]]; then
    expected=work
  else
    expected=personal
  fi
  output=$(HOME="$test_home" EXPECTED_ROLE="$expected" zsh -f -i -c '
    source "$HOME/.zshrc"
    for command_name in npm pnpm bun; do
      if [[ "$EXPECTED_ROLE" == work ]]; then
        [[ "${aliases[$command_name]-}" == "sfw $command_name" ]] || {
          print -u2 -- "Expected work alias $command_name to use sfw"
          exit 1
        }
      else
        (( ! ${+aliases[$command_name]} )) || {
          print -u2 -- "Expected no $command_name alias on a personal machine"
          exit 1
        }
      fi
    done
  ' 2>&1) || {
    print -u2 -- "$profile: $output"
    exit 1
  }
  [[ "$output" != *'command not found'* && "$output" != *'no such file or directory'* ]] || {
    print -u2 -- "$profile: unexpected shell startup error: $output"
    exit 1
  }
done

print -- "Shell alias tests passed."
