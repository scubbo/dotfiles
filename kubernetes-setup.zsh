# Optional, per-machine homelab Kubernetes access. This file is sourced by setup.sh.

kubernetes_preference() {
  local preference_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/kubernetes-access"
  local answer

  if [[ -f "$preference_file" ]]; then
    answer=$(<"$preference_file")
  else
    print -n -- "Should this machine have homelab Kubernetes access? [y/n] "
    while read -r answer; do
      case "$answer" in
        y|Y|yes|YES) answer=yes; break ;;
        n|N|no|NO) answer=no; break ;;
        *) print -n -- "Please answer y or n: " ;;
      esac
    done
    case "$answer" in
      yes|no) ;;
      *) print -u2 -- "Kubernetes setup deferred; no preference saved."; return 1 ;;
    esac
    mkdir -p "${preference_file:h}"
    (umask 077; print -r -- "$answer" >"$preference_file")
    print -- "Saved $answer to $preference_file"
  fi

  case "$answer" in
    yes) return 0 ;;
    no) return 1 ;;
    *) print -u2 -- "Invalid Kubernetes preference in $preference_file; use yes or no."; return 1 ;;
  esac
}

kubernetes_install_config() {
  local source=$1
  local target="$HOME/.kube/config"
  local temp cluster server

  if [[ ! -f "$source" || ! -r "$source" ]]; then
    print -u2 -- "Cannot read kubeconfig: $source"
    return 1
  fi
  if [[ -e "$target" || -L "$target" ]]; then
    print -u2 -- "Not replacing existing $target."
    return 1
  fi
  if (( ! $+commands[kubectl] )); then
    print -u2 -- "Install kubectl first, then rerun setup.sh."
    return 1
  fi

  mkdir -p "${target:h}"
  temp=$(umask 077; mktemp "${target:h}/.config.XXXXXXXX") || return 1
  # Flatten referenced certificates/keys while they are still relative to the
  # source file. The output contains credentials, so write only to the private
  # temporary file, never to the terminal.
  if ! kubectl --kubeconfig "$source" config view --flatten --raw >"$temp" || ! chmod 600 "$temp"; then
    print -u2 -- "Could not flatten the supplied kubeconfig."
    rm -f "$temp"
    return 1
  fi
  # k3s's server-local admin config uses loopback. Other kubeconfigs, including
  # restricted ones and those already using a remote endpoint, are left alone.
  if ! cluster=$(kubectl --kubeconfig "$temp" config view --minify -o 'jsonpath={.contexts[0].context.cluster}') ||
     ! server=$(kubectl --kubeconfig "$temp" config view --minify -o 'jsonpath={.clusters[0].cluster.server}') ||
     [[ -z "$cluster" || -z "$server" ]]; then
    print -u2 -- "Could not read the current context from the supplied kubeconfig."
    rm -f "$temp"
    return 1
  fi
  if [[ "$server" == "https://127.0.0.1:6443" ]]; then
    if ! kubectl --kubeconfig "$temp" config set-cluster "$cluster" --server=https://epsilon:6443 >/dev/null; then
      rm -f "$temp"
      return 1
    fi
  fi
  # Hard-link creation fails rather than overwriting a concurrently created file.
  if ! ln "$temp" "$target"; then
    print -u2 -- "Could not install $target; existing files were not overwritten."
    rm -f "$temp"
    return 1
  fi
  rm -f "$temp"
  print -- "Installed $target with mode 600."
}

setup_kubernetes() {
  local preference_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/kubernetes-access"
  local source

  if [[ ! -f "$preference_file" && ! -t 0 ]]; then
    print -- "Kubernetes preference not set; run setup.sh interactively to configure it."
    return
  fi
  kubernetes_preference || return 0

  if (( ! $+commands[kubectl] )); then
    print -u2 -- "kubectl is not installed. Install it for your OS (on NixOS, add kubectl to your packages), then rerun setup.sh."
  fi
  if [[ -n "${KUBECONFIG:-}" ]]; then
    print -- "KUBECONFIG is set; setup will not modify it. Check your active configuration with kubectl config current-context."
    return
  fi
  if [[ -e "$HOME/.kube/config" || -L "$HOME/.kube/config" ]]; then
    print -- "Existing $HOME/.kube/config left unchanged. Verify access with: kubectl -n arr-stack get pods"
    return
  fi

  cat <<'EOF'
No ~/.kube/config found. Obtain a kubeconfig through a trusted, encrypted channel.
Prefer a restricted read-only credential. The k3s server's /etc/rancher/k3s/k3s.yaml
is CLUSTER ADMIN, not read-only; use it only if you intend to grant full access.
See KUBERNETES.md for the existing homelab procedure and security precautions.
EOF
  if [[ ! -t 0 ]]; then
    print -- "Run setup.sh interactively after obtaining the kubeconfig."
    return
  fi
  print -n -- "Path to the local kubeconfig to install (blank to defer): "
  if ! read -r source || [[ -z "$source" ]]; then
    print -- "Kubernetes configuration deferred; rerun setup.sh when ready."
    return
  fi
  if kubernetes_install_config "$source"; then
    print -- "Verify with: kubectl -n arr-stack get pods"
    print -- "Once verified, remove any temporary credential copies."
  else
    print -u2 -- "Kubernetes configuration not installed; rerun setup.sh when ready."
  fi
}
