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
machine_type_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/machine-type"

# A local role file keeps machine selection independent of hostnames.
if [[ -f "$machine_type_file" ]]; then
  MACHINE_TYPE=$(<"$machine_type_file")
elif [[ "$current_hostname" == "MacBookPro.avril" || "$current_hostname" == "Jacks-MacBook-Pro.local" ]]; then
  MACHINE_TYPE="personal"
elif [[ "$current_hostname" == "Mac.avril" || "$current_hostname" == "Jacks-MacBook-Pro-2.local" ]]; then
  MACHINE_TYPE="work"
elif [[ "$arch_name" == "aarch64" ]]; then
  MACHINE_TYPE="personal"
else
  print -u2 -- "Unrecognized machine: hostname=$current_hostname, arch=$arch_name"
  print -u2 -- "Set $machine_type_file to work or personal."
  exit 1
fi

case "$MACHINE_TYPE" in
  work)
    local_zshrc="$repo_root/zshrc-work-mactop"
    local_gitconfig="$repo_root/gitconfig-professional"
    ;;
  personal)
    if [[ "$arch_name" == "aarch64" ]]; then
      local_zshrc="$repo_root/zshrc-local-pi"
    else
      local_zshrc="$repo_root/zshrc-local-mactop"
    fi
    local_gitconfig="$repo_root/gitconfig-personal"
    ;;
  *)
    print -u2 -- "Invalid machine type '$MACHINE_TYPE' in $machine_type_file."
    print -u2 -- "Set $machine_type_file to work or personal."
    exit 1
    ;;
esac

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

# Generate user-level AGENTS.md files from base + machine-specific overlay
agent_base="$repo_root/.claude/CLAUDE-base.md"

if [[ "$MACHINE_TYPE" == "work" ]]; then
  agent_overlay="$repo_root/.claude/CLAUDE-work.md"
else
  agent_overlay="$HOME/Code/dotfiles-private/.claude/CLAUDE-personal.md"
  if [[ ! -f "$agent_overlay" ]]; then
    print -u2 -- "ERROR: Personal machine detected but $agent_overlay not found."
    print -u2 -- "Please clone dotfiles-private repo to $HOME/Code/dotfiles-private"
    exit 1
  fi
fi

generate_agent_instructions() {
  local target=$1
  local instructions_file

  mkdir -p "${target:h}"
  instructions_file=$(mktemp "$target.XXXXXX")
  {
    cat <<'EOF'
<!-- GENERATED FILE - DO NOT EDIT DIRECTLY -->
<!-- Edit CLAUDE-base.md and CLAUDE-work.md (or CLAUDE-personal.md) in dotfiles repo -->

EOF
    cat "$agent_overlay"
    print
    cat "$agent_base"
  } >"$instructions_file"
  ensure_file "$instructions_file" "$target"
}

# Agents share the AGENTS.md format, but use separate global instruction paths.
generate_agent_instructions "${FX_HOME:-$HOME/.fx}/AGENTS.md"
generate_agent_instructions "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
generate_agent_instructions "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"

ensure_symlink "$repo_root/cursor/commands" "$HOME/.cursor/commands"

# herdr keeps runtime state (sockets, logs, session) in ~/.config/herdr, so
# durable configuration and scripts are symlinked individually rather than
# linking the whole directory. Referenced by the prefix+c keybinding.
ensure_symlink "$repo_root/herdr/config.toml" "$HOME/.config/herdr/config.toml"
ensure_symlink "$repo_root/herdr/new-worktree-tab.sh" "$HOME/.config/herdr/new-worktree-tab.sh"

rex_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rex"
ensure_symlink "$repo_root/rex/init.lua" "$rex_config_dir/init.lua"
ensure_symlink "$repo_root/rex/new-worktree-tab.sh" "$rex_config_dir/new-worktree-tab.sh"

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
