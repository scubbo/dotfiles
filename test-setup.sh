#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

test_home="$test_dir/home"
fake_bin="$test_dir/bin"
mkdir -p "$test_home/Code" "$fake_bin"
ln -s "$repo_root" "$test_home/Code/dotfiles"

cat >"$fake_bin/hostname" <<'EOF'
#!/bin/zsh
print -r -- Jacks-MacBook-Pro.local
EOF
chmod +x "$fake_bin/hostname"

mkdir -p "$test_home/Code/dotfiles-private/.claude"
print -r -- personal-claude-overlay >"$test_home/Code/dotfiles-private/.claude/CLAUDE-personal.md"

mkdir -p "$test_home/.cursor/commands" \
  "$test_home/.config/herdr" \
  "$test_home/Library/Application Support/Sublime Text" \
  "$test_home/Library/Application Support/Code/User" \
  "$test_home/.vscode/extensions"
print -r -- user-zshrc >"$test_home/.zshrc"
ln -s "$test_dir/wrong-gitconfig" "$test_home/.gitconfig"
print -r -- user-cursor-command >"$test_home/.cursor/commands/user.md"
print -r -- user-herdr-config >"$test_home/.config/herdr/config.toml"
print -r -- Herdr-runtime-state >"$test_home/.config/herdr/session.json"
print -r -- Herdr-runtime-log >"$test_home/.config/herdr/herdr-server.log"
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
assert_link "$test_home/Library/Application Support/Sublime Text/Default (OSX).sublime-keymap" "$repo_root/sublime-keymapping.json"
assert_link "$test_home/Library/Application Support/Code/User/settings.json" "$repo_root/VSCode/settings.json"
assert_link "$test_home/Library/Application Support/Code/User/keybindings.json" "$repo_root/VSCode/keybindings.json"
assert_link "$test_home/.vscode/extensions" "$repo_root/VSCode/extensions"

backup_count=$(find "$test_home/.dotfiles-backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
[[ "$backup_count" == 1 ]] || {
  print -u2 -- "Expected one backup directory"
  exit 1
}
backup_dir=$(find "$test_home/.dotfiles-backups" -mindepth 1 -maxdepth 1 -type d -print -quit)

grep -Fxq user-zshrc "$backup_dir/.zshrc"
[[ -L "$backup_dir/.gitconfig" ]]
grep -Fxq user-cursor-command "$backup_dir/.cursor/commands/user.md"
grep -Fxq user-herdr-config "$backup_dir/.config/herdr/config.toml"
grep -Fxq Herdr-runtime-state "$test_home/.config/herdr/session.json"
grep -Fxq Herdr-runtime-log "$test_home/.config/herdr/herdr-server.log"
grep -Fxq user-sublime-keybinding "$backup_dir/Library/Application Support/Sublime Text/Default (OSX).sublime-keymap"
grep -Fxq user-vs-code-settings "$backup_dir/Library/Application Support/Code/User/settings.json"
grep -Fxq user-vs-code-keybindings "$backup_dir/Library/Application Support/Code/User/keybindings.json"
grep -Fxq user-extension "$backup_dir/.vscode/extensions/user-extension.txt"

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
