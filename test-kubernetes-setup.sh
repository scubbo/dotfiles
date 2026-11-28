#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
export HOME="$test_dir/home"
export XDG_CONFIG_HOME="$test_dir/custom-config"
unset KUBECONFIG
mkdir -p "$HOME"
source "$repo_root/kubernetes-setup.zsh"

# Non-interactive setup must not invent or persist a preference.
setup_kubernetes </dev/null >"$test_dir/output"
[[ ! -e "$XDG_CONFIG_HOME/dotfiles/kubernetes-access" ]]
grep -q 'preference not set' "$test_dir/output"

printf 'invalid\ny\n' | kubernetes_preference >"$test_dir/output"
[[ "$(<"$XDG_CONFIG_HOME/dotfiles/kubernetes-access")" == yes ]]
grep -q 'Please answer y or n' "$test_dir/output"
kubernetes_preference </dev/null >/dev/null
print -r -- no >"$XDG_CONFIG_HOME/dotfiles/kubernetes-access"
if kubernetes_preference </dev/null >/dev/null; then
  print -u2 -- "Expected no preference to skip Kubernetes"
  exit 1
fi
print -r -- invalid >"$XDG_CONFIG_HOME/dotfiles/kubernetes-access"
if kubernetes_preference </dev/null >"$test_dir/output" 2>&1; then
  print -u2 -- "Expected invalid preference to be rejected"
  exit 1
fi
grep -q 'Invalid Kubernetes preference' "$test_dir/output"
rm "$XDG_CONFIG_HOME/dotfiles/kubernetes-access"
if kubernetes_preference </dev/null >/dev/null 2>&1; then
  print -u2 -- "Expected EOF to defer preference"
  exit 1
fi
[[ ! -e "$XDG_CONFIG_HOME/dotfiles/kubernetes-access" ]]

cat >"$test_dir/source" <<'EOF'
apiVersion: v1
kind: Config
clusters:
- name: homelab
  cluster:
    server: https://127.0.0.1:6443
contexts:
- name: homelab
  context:
    cluster: homelab
    user: test
current-context: homelab
users:
- name: test
  user:
    token: fixture-not-a-secret
EOF
kubernetes_install_config "$test_dir/source"
[[ -f "$HOME/.kube/config" && ! -L "$HOME/.kube/config" ]]
[[ "$(kubectl --kubeconfig "$HOME/.kube/config" config view --minify -o 'jsonpath={.clusters[0].cluster.server}')" == https://127.0.0.1:6443 ]]
[[ "$(kubectl --kubeconfig "$test_dir/source" config view --minify -o 'jsonpath={.clusters[0].cluster.server}')" == https://127.0.0.1:6443 ]]
zmodload zsh/stat
zstat -A file_mode +mode "$HOME/.kube/config"
(( (file_mode[1] & 8#077) == 0 ))
zstat -A directory_mode +mode "$HOME/.kube"
(( (directory_mode[1] & 8#077) == 0 ))
cp "$HOME/.kube/config" "$test_dir/installed"
if kubernetes_install_config "$test_dir/source" >"$test_dir/output" 2>&1; then
  print -u2 -- "Expected existing kubeconfig to be preserved"
  exit 1
fi
grep -q 'Not replacing existing' "$test_dir/output"
cmp "$test_dir/installed" "$HOME/.kube/config"

print -r -- yes >"$XDG_CONFIG_HOME/dotfiles/kubernetes-access"
export KUBECONFIG="$test_dir/source"
setup_kubernetes </dev/null >"$test_dir/output"
grep -q 'KUBECONFIG is set' "$test_dir/output"
cmp "$test_dir/installed" "$HOME/.kube/config"
unset KUBECONFIG
setup_kubernetes </dev/null >"$test_dir/output"
grep -q 'left unchanged' "$test_dir/output"

rm "$HOME/.kube/config"
kubernetes_install_config "$test_dir/source" epsilon
[[ "$(kubectl --kubeconfig "$HOME/.kube/config" config view --minify -o 'jsonpath={.clusters[0].cluster.server}')" == https://epsilon:6443 ]]
rm "$HOME/.kube/config"
kubectl --kubeconfig "$test_dir/source" config set-cluster homelab --server=https://remote.example:6443 >/dev/null
print -r -- certificate-fixture >"$test_dir/ca.crt"
kubectl --kubeconfig "$test_dir/source" config set-cluster homelab --certificate-authority="$test_dir/ca.crt" >/dev/null
kubernetes_install_config "$test_dir/source"
[[ "$(kubectl --kubeconfig "$HOME/.kube/config" config view --minify -o 'jsonpath={.clusters[0].cluster.server}')" == https://remote.example:6443 ]]
[[ -n "$(kubectl --kubeconfig "$HOME/.kube/config" config view --raw -o 'jsonpath={.clusters[0].cluster.certificate-authority-data}')" ]]
rm "$HOME/.kube/config"
print -r -- 'invalid: [secret-sentinel' >"$test_dir/invalid"
if kubernetes_install_config "$test_dir/invalid" >"$test_dir/output" 2>&1; then
  print -u2 -- "Expected invalid kubeconfig to be rejected"
  exit 1
fi
grep -q 'Could not flatten' "$test_dir/output"
if grep -q 'secret-sentinel' "$test_dir/output"; then
  print -u2 -- "Expected invalid credentials not to appear in diagnostics"
  exit 1
fi
[[ ! -e "$HOME/.kube/config" && -z "$(find "$HOME/.kube" -name '.config.*' -print)" ]]
ln -s "$test_dir/missing" "$HOME/.kube/config"
if kubernetes_install_config "$test_dir/source" >"$test_dir/output" 2>&1; then
  print -u2 -- "Expected a dangling symlink to be preserved"
  exit 1
fi
grep -q 'Not replacing existing' "$test_dir/output"
[[ -L "$HOME/.kube/config" ]]

print -- "Kubernetes setup tests passed."
