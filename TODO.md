# TODO

- [ ] Make `test-friction-tracker-reminder.sh` portable and keep its load-order check in sync with `zshrc`. On Linux, `zsh test-friction-tracker-reminder.sh` fails because `script` uses macOS-specific arguments; it also assumes `/bin/zsh` and fixed system paths. Its load-order check expects a PATH assignment that no longer matches `zshrc`.
- [ ] Make `test-shell-aliases.sh` run shell startup with a terminal and check its errors. With `fzf` installed, the test runs without a terminal, captures `can't change option: zle` errors, and still reports success.
