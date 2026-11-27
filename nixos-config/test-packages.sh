#!/usr/bin/env bash

set -euo pipefail

config_dir="$(cd "$(dirname "$0")" && pwd)"
has_fzf=$(nix eval --json "$config_dir#nixosConfigurations.phi.config.environment.systemPackages" \
  --apply 'packages: builtins.any (package: (package.pname or "") == "fzf") packages')
if [[ "$has_fzf" != true ]]; then
  printf '%s\n' "Expected fzf in phi's system packages" >&2
  exit 1
fi

printf '%s\n' "NixOS package tests passed."
