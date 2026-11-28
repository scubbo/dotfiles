# Homelab Kubernetes credentials

`setup.sh` asks whether this machine should have homelab access. It saves the answer in `${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/kubernetes-access`; non-interactive setup does not make a choice. Change the file to `yes` or `no` to change the preference.

When access is enabled and no kubeconfig exists, setup prints the command to fetch credentials; it does not fetch them itself. It leaves an existing file or `KUBECONFIG` override unchanged. A kubeconfig can contain private keys, tokens, and executable authentication plugins: use only a trusted file and never commit it or paste it into chat.

## Explicit admin shortcut

The k3s config on epsilon is a **shared cluster-admin credential**, not a per-user or read-only credential. Per-user non-admin access is tracked in `TODO.md`; use that instead when available.

To copy the admin config, run this separately in an interactive terminal:

```sh
~/bin/homelab-kubeconfig
```

The helper requires SSH access to `scubbo@epsilon.avril`, permission to run `sudo` there, and local `kubectl`. Verify the SSH host key through a trusted channel. It asks for explicit confirmation, copies the credential over SSH, and installs it at `~/.kube/config` with mode `600` only if no kubeconfig already exists and `KUBECONFIG` is unset. It embeds referenced certificates and keys; for this server-local config, it changes `https://127.0.0.1:6443` to `https://epsilon:6443`.

The helper makes private temporary copies locally and on epsilon and attempts to remove them on exit or interruption. If cleanup fails, it prints their locations; remove them promptly. A forced termination or network outage can prevent cleanup. It does not rotate certificates, change Kubernetes resources, or contact the cluster API.

Verify access separately with `kubectl -n arr-stack get pods`. The admin client certificate expires; if it is invalid, follow the homelab runbook with appropriate approval rather than rotating certificates during workstation setup.

On phi, the NixOS configuration includes `kubectl`; apply it with `sudo nixos-rebuild switch --flake ~/Code/dotfiles/nixos-config#phi`. On other systems, install a `kubectl` version compatible with the cluster.
