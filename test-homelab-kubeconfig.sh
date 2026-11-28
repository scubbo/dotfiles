#!/usr/bin/env zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
helper="$repo_root/bin/homelab-kubeconfig"
mkdir -p "$test_dir/home" "$test_dir/bin"
ln -s "$(command -v zsh)" "$test_dir/bin/zsh"
unset KUBECONFIG

output=$(HOME="$test_dir/home" PATH="$test_dir/bin" "$helper" --help 2>&1) || {
  print -u2 -- "Expected help to work without network tools: $output"
  exit 1
}
[[ "$output" == *'cluster-admin'* && "$output" == *'epsilon'* ]] || {
  print -u2 -- "Expected help to describe the admin credential and its source"
  exit 1
}

if output=$(HOME="$test_dir/home" PATH="$test_dir/bin" "$helper" </dev/null 2>&1); then
  print -u2 -- "Expected non-interactive admin credential import to fail"
  exit 1
fi
[[ "$output" == *'interactive terminal'* && ! -e "$test_dir/home/.kube/config" ]] || {
  print -u2 -- "Expected non-interactive import to stop before network access: $output"
  exit 1
}

mkdir -p "$test_dir/home/.kube"
print -r -- existing >"$test_dir/home/.kube/config"
if output=$(HOME="$test_dir/home" PATH="$test_dir/bin" "$helper" </dev/null 2>&1); then
  print -u2 -- "Expected an existing kubeconfig to be preserved"
  exit 1
fi
[[ "$output" == *'Not replacing existing'* && "$(<"$test_dir/home/.kube/config")" == existing ]] || {
  print -u2 -- "Expected existing credentials to be left untouched: $output"
  exit 1
}

if output=$(HOME="$test_dir/home" PATH="$test_dir/bin" KUBECONFIG="$test_dir/other" "$helper" </dev/null 2>&1); then
  print -u2 -- "Expected an explicit KUBECONFIG to be preserved"
  exit 1
fi
[[ "$output" == *'KUBECONFIG is set'* ]] || {
  print -u2 -- "Expected the KUBECONFIG override to be reported: $output"
  exit 1
}

print -- "Homelab kubeconfig helper tests passed."
