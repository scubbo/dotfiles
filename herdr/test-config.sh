#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
config="$repo_root/herdr/config.toml"

[[ -f "$config" ]] || {
  echo "Expected Herdr configuration at $config" >&2
  exit 1
}

grep -Fxq 'ln -sf ~/Code/dotfiles/herdr/config.toml $HOME/.config/herdr/config.toml' "$repo_root/setup.sh" || {
  echo "Expected setup.sh to link the Herdr configuration" >&2
  exit 1
}
