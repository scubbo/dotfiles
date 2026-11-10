#!/bin/zsh

set -euo pipefail

unset FX_HOME CODEX_HOME XDG_CONFIG_HOME TEST_HOSTNAME TEST_ARCH

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
mkdir -p "$test_home/Code" "$fake_bin"
ln -s "$repo_root" "$test_home/Code/dotfiles"

cat >"$fake_bin/hostname" <<'EOF'
#!/bin/zsh
print -r -- "${TEST_HOSTNAME:-Jacks-MacBook-Pro.local}"
EOF
cat >"$fake_bin/uname" <<'EOF'
#!/bin/zsh
if [[ "$1" == "-m" ]]; then
  print -r -- "${TEST_ARCH:-arm64}"
else
  /usr/bin/uname "$@"
fi
EOF
# Setup schedules a launchd job. Recording the calls keeps the tests from changing the real schedule.
launchctl_log="$test_dir/launchctl.log"
cat >"$fake_bin/launchctl" <<EOF
#!/bin/zsh
print -r -- "\$*" >>"$launchctl_log"
EOF
chmod +x "$fake_bin/hostname" "$fake_bin/uname" "$fake_bin/launchctl"

# Each test home would otherwise start with an empty Go build cache.
if (( $+commands[go] )); then
  export GOCACHE=$(go env GOCACHE)
fi

mkdir -p "$test_home/Code/dotfiles-private/.claude"
print -r -- personal-claude-overlay >"$test_home/Code/dotfiles-private/.claude/CLAUDE-personal.md"

mkdir -p "$test_home/.cursor/commands" \
  "$test_home/.fx" \
  "$test_home/.codex" \
  "$test_home/.config/opencode" \
  "$test_home/.config/herdr" \
  "$test_home/.config/rex" \
  "$test_home/Library/Application Support/Sublime Text" \
  "$test_home/Library/Application Support/Code/User" \
  "$test_home/.vscode/extensions"
print -r -- user-zshrc >"$test_home/.zshrc"
print -r -- user-fx-instructions >"$test_home/.fx/AGENTS.md"
print -r -- user-codex-instructions >"$test_home/.codex/AGENTS.md"
print -r -- user-opencode-instructions >"$test_home/.config/opencode/AGENTS.md"
ln -s "$test_dir/wrong-gitconfig" "$test_home/.gitconfig"
print -r -- user-cursor-command >"$test_home/.cursor/commands/user.md"
print -r -- user-herdr-config >"$test_home/.config/herdr/config.toml"
print -r -- Herdr-runtime-state >"$test_home/.config/herdr/session.json"
print -r -- Herdr-runtime-log >"$test_home/.config/herdr/herdr-server.log"
print -r -- user-rex-config >"$test_home/.config/rex/init.lua"
print -r -- user-rex-helper >"$test_home/.config/rex/new-worktree-tab.sh"
print -r -- Rex-runtime-log >"$test_home/.config/rex/new-worktree-tab.log"
print -r -- user-sublime-keybinding >"$test_home/Library/Application Support/Sublime Text/Default (OSX).sublime-keymap"
print -r -- user-vs-code-settings >"$test_home/Library/Application Support/Code/User/settings.json"
print -r -- user-vs-code-keybindings >"$test_home/Library/Application Support/Code/User/keybindings.json"
print -r -- user-extension >"$test_home/.vscode/extensions/user-extension.txt"

output=$(HOME="$test_home" PATH="$fake_bin:$PATH" zsh "$repo_root/setup.sh" 2>&1)
[[ "$output" == *'WARNING: Backed up'* ]] || {
  print -u2 -- "Expected conflict backups to produce a warning"
  exit 1
}

assert_link() {
  local target=$1
  local source=$2

  [[ "$target" -ef "$source" ]] || {
    print -u2 -- "Expected $target to link to $source"
    exit 1
  }
}

assert_link "$test_home/.zshrc" "$repo_root/zshrc"
assert_link "$test_home/.gitconfig" "$repo_root/gitconfig"
assert_link "$test_home/.zshrc-local" "$repo_root/zshrc-local-mactop"
assert_link "$test_home/.gitconfig-local" "$repo_root/gitconfig-personal"
assert_link "$test_home/.cursor/commands" "$repo_root/cursor/commands"
assert_link "$test_home/.config/herdr/config.toml" "$repo_root/herdr/config.toml"
assert_link "$test_home/.config/rex/init.lua" "$repo_root/rex/init.lua"
assert_link "$test_home/.config/rex/new-worktree-tab.sh" "$repo_root/rex/new-worktree-tab.sh"
assert_link "$test_home/Library/Application Support/Sublime Text/Default (OSX).sublime-keymap" "$repo_root/sublime-keymapping.json"
assert_link "$test_home/Library/Application Support/Code/User/settings.json" "$repo_root/VSCode/settings.json"
assert_link "$test_home/Library/Application Support/Code/User/keybindings.json" "$repo_root/VSCode/keybindings.json"
[[ -d "$test_home/.vscode/extensions" && ! -L "$test_home/.vscode/extensions" ]] || {
  print -u2 -- "Expected setup to leave the extension directory unchanged"
  exit 1
}
grep -Fxq user-extension "$test_home/.vscode/extensions/user-extension.txt"

assert_instructions() {
  local overlay=$1
  shift
  local expected="$test_dir/expected-instructions.md"
  local target

  {
    cat <<'EOF'
<!-- GENERATED FILE - DO NOT EDIT DIRECTLY -->
<!-- Edit CLAUDE-base.md and CLAUDE-work.md (or CLAUDE-personal.md) in dotfiles repo -->

EOF
    cat "$overlay"
    print
    cat "$repo_root/.claude/CLAUDE-base.md"
  } >"$expected"

  for target in "$@"; do
    cmp -s "$expected" "$target" || {
      print -u2 -- "Expected $target to contain the machine overlay followed by the base instructions"
      exit 1
    }
  done
}

assert_instructions "$test_home/Code/dotfiles-private/.claude/CLAUDE-personal.md" \
  "$test_home/.fx/AGENTS.md" \
  "$test_home/.codex/AGENTS.md" \
  "$test_home/.config/opencode/AGENTS.md"
[[ ! -e "$test_home/.claude/CLAUDE.md" ]] || {
  print -u2 -- "Expected setup not to install Claude instructions"
  exit 1
}
[[ -n "$(tail -n 1 "$test_home/.fx/AGENTS.md")" ]] || {
  print -u2 -- "Expected generated instructions not to end with a blank line"
  exit 1
}

assert_agent_friction() {
  local home=$1
  local fx_sessions=$2
  local binary="$home/.local/bin/agent-friction"
  local label=com.scubbo.agent-friction
  local plist="$home/Library/LaunchAgents/$label.plist"
  local job_command usage

  usage=$("$binary" 2>&1) && {
    print -u2 -- "Expected $binary to reject a call without a command"
    exit 1
  }
  [[ "$usage" == *'usage: agent-friction'* ]] || {
    print -u2 -- "Expected $binary to be the agent-friction program, got: $usage"
    exit 1
  }

  plutil -lint "$plist" >/dev/null || {
    print -u2 -- "Expected $plist to be a valid property list"
    exit 1
  }
  [[ "$(plutil -extract Label raw "$plist")" == "$label" && \
    "$(plutil -extract StartCalendarInterval.Weekday raw "$plist")" == 1 ]] || {
    print -u2 -- "Expected $plist to schedule $label weekly"
    exit 1
  }
  job_command=$(plutil -extract ProgramArguments.2 raw "$plist")
  [[ "$job_command" == "'$binary' scan --fx-sessions '$fx_sessions' --state '$home/.local/state/agent-friction' && "*'display notification'* ]] || {
    print -u2 -- "Expected the scheduled job to scan $fx_sessions and then notify, got: $job_command"
    exit 1
  }
  [[ -d "$home/.local/state/agent-friction/logs" ]] || {
    print -u2 -- "Expected a log directory for the scheduled job"
    exit 1
  }
  grep -Fxq "bootstrap gui/$UID $plist" "$launchctl_log" || {
    print -u2 -- "Expected setup to load $plist into launchd"
    exit 1
  }
}

if (( $+commands[go] )); then
  assert_agent_friction "$test_home" "$test_home/.fx/sessions/v2"
  [[ "$(head -n 1 "$launchctl_log")" == "bootout gui/$UID/com.scubbo.agent-friction" ]] || {
    print -u2 -- "Expected setup to unload the scheduled job before loading it"
    exit 1
  }
fi

backup_count=$(find "$test_home/.dotfiles-backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$backup_count" == 1 ]] || {
  print -u2 -- "Expected one backup directory"
  exit 1
}
backup_dir=$(find "$test_home/.dotfiles-backups" -mindepth 1 -maxdepth 1 -type d -print -quit)

grep -Fxq user-zshrc "$backup_dir/.zshrc"
grep -Fxq user-fx-instructions "$backup_dir/.fx/AGENTS.md"
grep -Fxq user-codex-instructions "$backup_dir/.codex/AGENTS.md"
grep -Fxq user-opencode-instructions "$backup_dir/.config/opencode/AGENTS.md"
[[ -L "$backup_dir/.gitconfig" ]]
grep -Fxq user-cursor-command "$backup_dir/.cursor/commands/user.md"
grep -Fxq user-herdr-config "$backup_dir/.config/herdr/config.toml"
grep -Fxq Herdr-runtime-state "$test_home/.config/herdr/session.json"
grep -Fxq Herdr-runtime-log "$test_home/.config/herdr/herdr-server.log"
grep -Fxq user-rex-config "$backup_dir/.config/rex/init.lua"
grep -Fxq user-rex-helper "$backup_dir/.config/rex/new-worktree-tab.sh"
grep -Fxq Rex-runtime-log "$test_home/.config/rex/new-worktree-tab.log"
grep -Fxq user-sublime-keybinding "$backup_dir/Library/Application Support/Sublime Text/Default (OSX).sublime-keymap"
grep -Fxq user-vs-code-settings "$backup_dir/Library/Application Support/Code/User/settings.json"
grep -Fxq user-vs-code-keybindings "$backup_dir/Library/Application Support/Code/User/keybindings.json"
[[ ! -e "$backup_dir/.vscode/extensions" ]] || {
  print -u2 -- "Expected setup not to back up the extension directory"
  exit 1
}

second_output=$(HOME="$test_home" PATH="$fake_bin:$PATH" zsh "$repo_root/setup.sh" 2>&1)
[[ "$second_output" != *'WARNING: Backed up'* ]] || {
  print -u2 -- "Expected second setup run not to create backups"
  exit 1
}

backup_count_after=$(find "$test_home/.dotfiles-backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$backup_count_after" == 1 ]] || {
  print -u2 -- "Expected second setup run not to create another backup"
  exit 1
}

work_home="$test_dir/work-home"
mkdir -p "$work_home/.claude"
print -r -- user-claude-instructions >"$work_home/.claude/CLAUDE.md"
work_output=$(HOME="$work_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=Jacks-MacBook-Pro-2.local \
  FX_HOME="$work_home/custom-fx" CODEX_HOME="$work_home/custom-codex" \
  XDG_CONFIG_HOME="$work_home/custom-config" zsh "$repo_root/setup.sh" 2>&1) || {
  print -u2 -- "$work_output"
  exit 1
}
assert_link "$work_home/.zshrc-local" "$repo_root/zshrc-work-mactop"
assert_link "$work_home/.gitconfig-local" "$repo_root/gitconfig-professional"
assert_link "$work_home/custom-config/rex/init.lua" "$repo_root/rex/init.lua"
assert_link "$work_home/custom-config/rex/new-worktree-tab.sh" "$repo_root/rex/new-worktree-tab.sh"
assert_instructions "$repo_root/.claude/CLAUDE-work.md" \
  "$work_home/custom-fx/AGENTS.md" \
  "$work_home/custom-codex/AGENTS.md" \
  "$work_home/custom-config/opencode/AGENTS.md"
grep -Fxq user-claude-instructions "$work_home/.claude/CLAUDE.md"
if (( $+commands[go] )); then
  assert_agent_friction "$work_home" "$work_home/custom-fx/sessions/v2"
fi
[[ ! -e "$work_home/.fx/AGENTS.md" && ! -e "$work_home/.codex/AGENTS.md" && \
  ! -e "$work_home/.config/opencode/AGENTS.md" ]] || {
  print -u2 -- "Expected agent configuration directory overrides to replace default paths"
  exit 1
}

work_output=$(HOME="$work_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=Mac.avril \
  FX_HOME="$work_home/custom-fx" CODEX_HOME="$work_home/custom-codex" \
  XDG_CONFIG_HOME="$work_home/custom-config" zsh "$repo_root/setup.sh" 2>&1)
[[ "$work_output" != *'WARNING: Backed up'* ]] || {
  print -u2 -- "Expected both work hostnames to select the same dotfiles"
  exit 1
}

mkdir -p "$work_home/custom-config/dotfiles"
print -r -- work >"$work_home/custom-config/dotfiles/machine-type"
work_output=$(HOME="$work_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=Jacks-MacBook-Pro.local \
  FX_HOME="$work_home/custom-fx" CODEX_HOME="$work_home/custom-codex" \
  XDG_CONFIG_HOME="$work_home/custom-config" zsh "$repo_root/setup.sh" 2>&1) || {
  print -u2 -- "$work_output"
  exit 1
}
assert_link "$work_home/.zshrc-local" "$repo_root/zshrc-work-mactop"
assert_link "$work_home/.gitconfig-local" "$repo_root/gitconfig-professional"
assert_instructions "$repo_root/.claude/CLAUDE-work.md" \
  "$work_home/custom-fx/AGENTS.md" \
  "$work_home/custom-codex/AGENTS.md" \
  "$work_home/custom-config/opencode/AGENTS.md"
[[ "$work_output" != *'WARNING: Backed up'* ]] || {
  print -u2 -- "Expected the machine-type file to take precedence over the hostname"
  exit 1
}

personal_home="$test_dir/personal-home"
mkdir -p "$personal_home/.config/dotfiles" "$personal_home/Code/dotfiles-private/.claude" \
  "$personal_home/Library/Application Support/Code/User"
print -r -- personal >"$personal_home/.config/dotfiles/machine-type"
print -r -- personal-overlay >"$personal_home/Code/dotfiles-private/.claude/CLAUDE-personal.md"
personal_output=$(HOME="$personal_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=Mac.avril \
  zsh "$repo_root/setup.sh" 2>&1) || {
  print -u2 -- "$personal_output"
  exit 1
}
assert_link "$personal_home/.zshrc-local" "$repo_root/zshrc-local-mactop"
assert_link "$personal_home/.gitconfig-local" "$repo_root/gitconfig-personal"
[[ ! -e "$personal_home/.vscode/extensions" && ! -L "$personal_home/.vscode/extensions" ]] || {
  print -u2 -- "Expected setup not to create an extension directory"
  exit 1
}
assert_instructions "$personal_home/Code/dotfiles-private/.claude/CLAUDE-personal.md" \
  "$personal_home/.fx/AGENTS.md" \
  "$personal_home/.codex/AGENTS.md" \
  "$personal_home/.config/opencode/AGENTS.md"

pi_home="$test_dir/pi-home"
mkdir -p "$pi_home/Code/dotfiles-private/.claude"
print -r -- pi-overlay >"$pi_home/Code/dotfiles-private/.claude/CLAUDE-personal.md"
pi_output=$(HOME="$pi_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=pi.local TEST_ARCH=aarch64 \
  zsh "$repo_root/setup.sh" 2>&1)
assert_link "$pi_home/.zshrc-local" "$repo_root/zshrc-local-pi"
assert_link "$pi_home/.gitconfig-local" "$repo_root/gitconfig-personal"

without_go_home="$test_dir/without-go-home"
mkdir -p "$without_go_home/Code/dotfiles-private/.claude"
print -r -- overlay >"$without_go_home/Code/dotfiles-private/.claude/CLAUDE-personal.md"
without_go_output=$(HOME="$without_go_home" PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  zsh "$repo_root/setup.sh" 2>&1) || {
  print -u2 -- "$without_go_output"
  exit 1
}
[[ "$without_go_output" == *'agent-friction not installed'* && \
  ! -e "$without_go_home/.local/bin/agent-friction" && ! -e "$without_go_home/Library/LaunchAgents" ]] || {
  print -u2 -- "Expected setup to skip agent-friction when Go is missing"
  exit 1
}

invalid_home="$test_dir/invalid-home"
mkdir -p "$invalid_home/.config/dotfiles"
for invalid_type in unknown ''; do
  print -r -- "$invalid_type" >"$invalid_home/.config/dotfiles/machine-type"
  if invalid_output=$(HOME="$invalid_home" PATH="$fake_bin:$PATH" \
    zsh "$repo_root/setup.sh" 2>&1); then
    print -u2 -- "Expected an invalid machine-type file to stop setup"
    exit 1
  fi
  [[ "$invalid_output" == *'Invalid machine type'* && ! -e "$invalid_home/.zshrc" ]] || {
    print -u2 -- "Expected an invalid machine type to fail before installing dotfiles"
    exit 1
  }
done

unknown_home="$test_dir/unknown-home"
if unknown_output=$(HOME="$unknown_home" PATH="$fake_bin:$PATH" TEST_HOSTNAME=unknown.local \
  zsh "$repo_root/setup.sh" 2>&1); then
  print -u2 -- "Expected an unknown machine to stop setup"
  exit 1
fi
[[ "$unknown_output" == *'Unrecognized machine:'* && ! -e "$unknown_home/.zshrc" ]] || {
  print -u2 -- "Expected an unknown machine to fail before installing dotfiles"
  exit 1
}

print -- "Setup tests passed (machine selection, instructions, directory overrides, backups, idempotence, agent-friction)."
