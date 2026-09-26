#!/bin/zsh

set -e

repo_root=${0:A:h}
backup_root=""

backup_existing() {
  local target=$1
  local backup_path

  if [[ -z "$backup_root" ]]; then
    backup_root="$HOME/.dotfiles-backups/$(date +%Y%m%d%H%M%S)-$$"
  fi

  backup_path="$backup_root${target#"$HOME"}"
  mkdir -p "${backup_path:h}"
  mv "$target" "$backup_path"
  print -u2 -- "WARNING: Backed up $target to $backup_path before replacing it."
}

ensure_symlink() {
  local source=$1
  local target=$2

  [[ -e "$source" ]] || {
    print -u2 -- "ERROR: Cannot link missing source $source"
    exit 1
  }

  mkdir -p "${target:h}"

  if [[ -L "$target" ]] && [[ "$target" -ef "$source" ]]; then
    print -- "Already linked $target"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    backup_existing "$target"
  fi

  ln -s "$source" "$target"
  print -- "Linked $target"
}

ensure_file() {
  local source=$1
  local target=$2

  mkdir -p "${target:h}"

  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
    rm "$source"
    print -- "Already current $target"
    return
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    backup_existing "$target"
  fi

  mv "$source" "$target"
  print -- "Updated $target"
}

# Detect machine type
current_hostname=$(hostname)
arch_name=$(uname -m)

if [[ "$current_hostname" == "MacBookPro.avril" || "$current_hostname" == "Jacks-MacBook-Pro.local" ]]; then
  MACHINE_TYPE="personal"
  local_zshrc="$repo_root/zshrc-local-mactop"
  local_gitconfig="$repo_root/gitconfig-personal"
elif [[ "$current_hostname" == "Mac.avril" ]]; then
  MACHINE_TYPE="work"
  local_zshrc="$repo_root/zshrc-work-mactop"
  local_gitconfig="$repo_root/gitconfig-professional"
elif [[ "$arch_name" == "aarch64" ]]; then
  MACHINE_TYPE="personal"
  local_zshrc="$repo_root/zshrc-local-pi"
  local_gitconfig="$repo_root/gitconfig-personal"
else
  print -u2 -- "Unrecognized machine: hostname=$current_hostname, arch=$arch_name"
  exit 1
fi

# Install dotfiles
ensure_symlink "$local_zshrc" "$HOME/.zshrc-local"
ensure_symlink "$local_gitconfig" "$HOME/.gitconfig-local"
ensure_symlink "$repo_root/zshrc" "$HOME/.zshrc"
ensure_symlink "$repo_root/gitignore_global" "$HOME/.gitignore_global"
ensure_symlink "$repo_root/gitconfig" "$HOME/.gitconfig"
ensure_symlink "$repo_root/vimrc" "$HOME/.vimrc"
ensure_symlink "$repo_root/envFolder" "$HOME/.env"
ensure_symlink "$repo_root/bin" "$HOME/bin"
ensure_symlink "$repo_root/screenrc" "$HOME/.screenrc"
ensure_symlink "$repo_root/tmux.conf" "$HOME/.tmux.conf"

# Generate ~/.claude/CLAUDE.md from base + machine-specific overlay
claude_base="$repo_root/.claude/CLAUDE-base.md"

if [[ "$MACHINE_TYPE" == "work" ]]; then
  claude_overlay="$repo_root/.claude/CLAUDE-work.md"
else
  claude_overlay="$HOME/Code/dotfiles-private/.claude/CLAUDE-personal.md"
  if [[ ! -f "$claude_overlay" ]]; then
    print -u2 -- "ERROR: Personal machine detected but $claude_overlay not found."
    print -u2 -- "Please clone dotfiles-private repo to $HOME/Code/dotfiles-private"
    exit 1
  fi
fi

mkdir -p "$HOME/.claude"
claude_file=$(mktemp "$HOME/.claude/CLAUDE.md.XXXXXX")
{
  cat <<'EOF'
<!-- GENERATED FILE - DO NOT EDIT DIRECTLY -->
<!-- Edit CLAUDE-base.md and CLAUDE-work.md (or CLAUDE-personal.md) in dotfiles repo -->

EOF
  cat "$claude_overlay"
  print
  cat "$claude_base"
} >"$claude_file"
ensure_file "$claude_file" "$HOME/.claude/CLAUDE.md"

ensure_symlink "$repo_root/cursor/commands" "$HOME/.cursor/commands"

# herdr keeps runtime state (sockets, logs, session) in ~/.config/herdr, so
# durable configuration and scripts are symlinked individually rather than
# linking the whole directory. Referenced by the prefix+c keybinding.
ensure_symlink "$repo_root/herdr/config.toml" "$HOME/.config/herdr/config.toml"
ensure_symlink "$repo_root/herdr/new-worktree-tab.sh" "$HOME/.config/herdr/new-worktree-tab.sh"

# Install Sublime keybindings, if sublime is present
sublime_keymapping_dir="$HOME/Library/Application Support/Sublime Text"
sublime_keymapping_file="$sublime_keymapping_dir/Default (OSX).sublime-keymap"
if [[ -d "$sublime_keymapping_dir" ]]; then
  ensure_symlink "$repo_root/sublime-keymapping.json" "$sublime_keymapping_file"
else
  print -- "Sublime is not currently installed - Sublime key-mappings not installed"
fi

vscode_app_dir="$HOME/Library/Application Support/Code/User"
if [[ -d "$vscode_app_dir" ]]; then
  ensure_symlink "$repo_root/VSCode/settings.json" "$vscode_app_dir/settings.json"
  ensure_symlink "$repo_root/VSCode/keybindings.json" "$vscode_app_dir/keybindings.json"
  ensure_symlink "$repo_root/VSCode/extensions" "$HOME/.vscode/extensions"
else
  print -- "VSCode is not installed - settings and keybindings not installed"
fi

print -- "Dotfiles installed."
