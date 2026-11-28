# TODO

- [ ] Make `test-friction-tracker-reminder.sh` portable and keep its load-order check in sync with `zshrc`. On Linux, `zsh test-friction-tracker-reminder.sh` fails because `script` uses macOS-specific arguments; it also assumes `/bin/zsh` and fixed system paths. Its load-order check expects a PATH assignment that no longer matches `zshrc`.
- [ ] Make `test-shell-aliases.sh` run shell startup with a terminal and check its errors. With `fzf` installed, the test runs without a terminal, captures `can't change option: zle` errors, and still reports success.
- [x] Protect the actual default branch in `git clean-branches` and resolve repository defaults in `git nb` and `git def`. Covered by `test-default-branches.sh`.
- [x] Stop the work `plf` alias before installing, staging, committing, or pushing when its fetch or merge fails. Covered by `test-work-plf.sh`.
- [ ] Replace the shared k3s administrator kubeconfig shortcut with per-user, non-admin Kubernetes credentials; coordinate the access policy with `homelab-configuration`.
- [ ] Verify `homelab-kubeconfig` cleanup against epsilon on an authorized machine without logging credentials. A live run installed working credentials, but remote cleanup failed because SSH batch mode blocked the password prompt; the fix allowing prompts needs a live check.
- [x] Show the explicit credential-fetch command instead of prompting for a local kubeconfig during setup. Covered by `test-kubernetes-setup.sh`.
