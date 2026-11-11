#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h}
reminder="$repo_root/bin/friction-tracker-reminder.zsh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fake_bin="$test_dir/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/friction-tracker" <<'FAKE'
#!/bin/zsh
print -r -- "friction-tracker was called with: $*"
FAKE
chmod +x "$fake_bin/friction-tracker"

# `script` runs the shell in a terminal, as a person's shell would be.
# `-f` keeps the user's own startup files out of the test.
in_terminal() {
  script -q /dev/null env PATH="$1" /bin/zsh -f -i -c "source '$reminder'" </dev/null 2>&1
}

terminal_output=$(in_terminal "$fake_bin:/usr/bin:/bin") || true
[[ "$terminal_output" == *'friction-tracker was called with: unread'* ]] || {
  print -u2 -- "Expected a terminal shell to ask friction-tracker for a reminder, got: $terminal_output"
  exit 1
}

# An agent captures the output of its shell commands, so that output is not a terminal.
captured_output=$(PATH="$fake_bin:/usr/bin:/bin" /bin/zsh -f -i -c "source '$reminder'" 2>&1) || true
[[ -z "$captured_output" ]] || {
  print -u2 -- "Expected no reminder when output is captured, got: $captured_output"
  exit 1
}

missing_output=$(in_terminal "/usr/bin:/bin") || true
[[ "$missing_output" != *'friction-tracker'* && "$missing_output" != *'not found'* ]] || {
  print -u2 -- "Expected silence when friction-tracker is not installed, got: $missing_output"
  exit 1
}

path_line=$(grep -n -m 1 -F 'export PATH="$HOME/.local/bin:$PATH"' "$repo_root/zshrc" | cut -d: -f1)
source_line=$(grep -n -m 1 -F 'source $HOME/bin/friction-tracker-reminder.zsh' "$repo_root/zshrc" | cut -d: -f1)
[[ -n "$path_line" && -n "$source_line" ]] && (( source_line > path_line )) || {
  print -u2 -- "Expected zshrc to load the reminder after it adds ~/.local/bin to PATH"
  exit 1
}

print -- "Reminder tests passed (terminal, captured output, program missing, load order)."
