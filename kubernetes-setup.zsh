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
  local origin=${2:-supplied}
  local target="$HOME/.kube/config"
  local temp cluster server

  if [[ "$origin" != supplied && "$origin" != epsilon ]]; then
    print -u2 -- "Invalid kubeconfig source."
    return 1
  fi
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

  (umask 077; mkdir -p "${target:h}")
  temp=$(umask 077; mktemp "${target:h}/.config.XXXXXXXX") || return 1
  # Flatten referenced certificates/keys while they are still relative to the
  # source file. The output contains credentials, so write only to the private
  # temporary file, never to the terminal.
  if ! kubectl --kubeconfig "$source" config view --flatten --raw >"$temp" 2>/dev/null || ! chmod 600 "$temp"; then
    print -u2 -- "Could not flatten the supplied kubeconfig."
    rm -f "$temp"
    return 1
  fi
  # The server-local k3s config uses loopback, which is unreachable from a workstation.
  if ! cluster=$(kubectl --kubeconfig "$temp" config view --minify -o 'jsonpath={.contexts[0].context.cluster}' 2>/dev/null) ||
     ! server=$(kubectl --kubeconfig "$temp" config view --minify -o 'jsonpath={.clusters[0].cluster.server}' 2>/dev/null) ||
     [[ -z "$cluster" || -z "$server" ]]; then
    print -u2 -- "Could not read the current context from the supplied kubeconfig."
    rm -f "$temp"
    return 1
  fi
  if [[ "$origin" == epsilon && "$server" == "https://127.0.0.1:6443" ]]; then
    if ! kubectl --kubeconfig "$temp" config set-cluster "$cluster" --server=https://epsilon:6443 >/dev/null 2>&1; then
      print -u2 -- "Could not set the Kubernetes API endpoint."
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

  if [[ ! -f "$preference_file" && ! -t 0 ]]; then
    print -- "Kubernetes preference not set; run setup.sh interactively to configure it."
    return
  fi
  kubernetes_preference || return 0

  if (( ! $+commands[kubectl] )); then
    print -u2 -- "kubectl is not installed. Install it for your OS before running homelab-kubeconfig."
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
No ~/.kube/config found. To fetch and install epsilon's shared CLUSTER-ADMIN
credential, run this separately after setup:

  ~/bin/homelab-kubeconfig

Prefer per-user non-admin credentials when available. See KUBERNETES.md for
security precautions.
EOF
}
