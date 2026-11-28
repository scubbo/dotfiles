#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")" && pwd)"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
mkdir -p "$test_home/.local/bin"
ln -s "$repo_root/bin" "$test_home/bin"
cat >"$test_home/.local/bin/path-probe" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' local-bin-found
EOF
chmod +x "$test_home/.local/bin/path-probe"

environment_file=$(nix build --no-link --print-out-paths \
  "$repo_root/nixos-config#nixosConfigurations.phi.config.system.build.setEnvironment")
bash_executable=$(command -v bash)
output=$(env -i HOME="$test_home" "$bash_executable" --noprofile --norc -c '
  set -e
  . "$1"
  awake --help
  path-probe
' bash "$environment_file" 2>&1) || {
  printf 'Expected user commands to be found in PATH: %s\n' "$output" >&2
  exit 1
}
[[ "$output" == *'Usage: awake'* && "$output" == *'local-bin-found'* ]] || {
  printf 'Unexpected command output: %s\n' "$output" >&2
  exit 1
}

printf '%s\n' "User PATH tests passed."
