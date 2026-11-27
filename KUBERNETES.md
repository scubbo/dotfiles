# Homelab Kubernetes access

`setup.sh` asks once whether this machine should have homelab Kubernetes access.
The answer is stored in `${XDG_CONFIG_HOME:-~/.config}/dotfiles/kubernetes-access`
as `yes` or `no`, next to `machine-type`. Edit that file to change the answer.
Non-interactive setup does not make a choice on your behalf.

Install `kubectl` using the machine's package manager (on NixOS, add `kubectl`
to the appropriate Nix configuration); use a version compatible with the
cluster. Connect to the homelab network or its Tailscale routes. Obtain a
kubeconfig using a trusted encrypted channel; prefer a dedicated read-only
credential. A kubeconfig can contain private keys or bearer tokens, and can
also configure executable credential plugins: use only a trusted file, and
never commit it, paste it into chat, or print it in logs.

The existing homelab runbook documents another option:
`~/Code/homelab-configuration/agentic-investigations/2026-07-12-k3s-client-cert-refresh.md`.
**The server's `/etc/rancher/k3s/k3s.yaml` grants full cluster-admin access,
not read-only access.** Use it only on a trusted machine when that privilege is
intended. Its client certificate expires; copying an expired file will not
restore access. Certificate rotation and the runbook's ArgoCD refresh can
change or interrupt the cluster and are separate, explicitly approved work;
do not run the refresh script as part of ordinary workstation setup.

To copy that admin config, if authorized:

1. SSH to `scubbo@epsilon.avril` and verify its host key against a trusted
   source. On epsilon, make a private temporary directory and copy the config
   into it (sudo prompts for your epsilon password):

   ```sh
   export KUBE_EXPORT="$(mktemp -d "$HOME/kube-export.XXXXXXXX")"
   sudo install -m 600 -o "$(id -un)" /etc/rancher/k3s/k3s.yaml "$KUBE_EXPORT/k3s.yaml"
   printf 'Copy from: scubbo@epsilon.avril:%s/k3s.yaml\n' "$KUBE_EXPORT"
   ```

2. In a separate local terminal, create a private temporary file and use the
   path printed above with `scp`:

   ```sh
   umask 077
   kube_source="$(mktemp "${TMPDIR:-/tmp}/homelab-kubeconfig.XXXXXXXX")"
   scp 'scubbo@epsilon.avril:/home/scubbo/kube-export.REPLACE_ME/k3s.yaml' "$kube_source"
   printf 'Local file: %s\n' "$kube_source"
   ```

   In the epsilon terminal, remove the temporary server copy promptly, even
   if `scp` fails: `rm -f "$KUBE_EXPORT/k3s.yaml"; rmdir "$KUBE_EXPORT"`.
3. Run `setup.sh`, answer yes, and enter the local file's path. Setup installs
   it at `~/.kube/config` without overwriting an existing file, and changes the
   k3s loopback API endpoint to `https://epsilon:6443`. Existing remote endpoints
   are not changed. It embeds referenced certificate files, but credential
   plugins may still require additional tools. It does not rotate certificates
   or modify ArgoCD.
4. Verify with `kubectl -n arr-stack get pods`, then remove the temporary local
   copy (`rm -f "$kube_source"`). If authentication fails, check credential
   expiry and follow the runbook with appropriate approval.

If `KUBECONFIG` is set or `~/.kube/config` already exists, setup leaves it
untouched. Manage merging and the active context yourself; do not accidentally
overwrite a different cluster's configuration.
