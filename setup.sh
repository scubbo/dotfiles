#!/usr/bin/env zsh

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
os_name=$(uname -s)
machine_type_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/machine-type"

# A local role file keeps machine selection independent of hostnames.
if [[ -f "$machine_type_file" ]]; then
  MACHINE_TYPE=$(<"$machine_type_file")
elif [[ "$current_hostname" == "MacBookPro.avril" || "$current_hostname" == "Jacks-MacBook-Pro.local" ]]; then
  MACHINE_TYPE="personal"
elif [[ "$current_hostname" == "Mac.avril" || "$current_hostname" == "Jacks-MacBook-Pro-2.local" || "$current_hostname" == "jacks-mbp-2" ]]; then
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
    elif [[ "$os_name" == "Linux" ]]; then
      local_zshrc="$repo_root/zshrc-local-linux"
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

# Check all required inputs before changing anything in the home directory.
agent_base="$repo_root/.claude/CLAUDE-base.md"
if [[ "$MACHINE_TYPE" == "work" ]]; then
  agent_overlay="$repo_root/.claude/CLAUDE-work.md"
else
  agent_overlay="$HOME/Code/dotfiles-private/.claude/CLAUDE-personal.md"
  if [[ ! -e "$agent_overlay" && ! -L "$agent_overlay" ]]; then
    print -u2 -- ""
    print -u2 -- "****************************************************************"
    print -u2 -- "WARNING: Personal agent instructions are missing: $agent_overlay"
    print -u2 -- "Setup will install BASE-ONLY agent instructions, without the personal overlay."
    print -u2 -- "Existing instruction files will be backed up if they differ."
    print -u2 -- "To include the overlay, add the file and run setup again."
    print -u2 -- "****************************************************************"
    print -u2 -- ""
    agent_overlay=""
  fi
fi

instruction_files=("$agent_base")
if [[ -n "$agent_overlay" ]]; then
  instruction_files+=("$agent_overlay")
fi
for instruction_file in "${instruction_files[@]}"; do
  if [[ ! -f "$instruction_file" || ! -r "$instruction_file" ]]; then
    print -u2 -- "ERROR: Required agent instructions are missing or unreadable: $instruction_file"
    exit 1
  fi
done

required_sources=(
  "$local_zshrc" "$local_gitconfig" "$repo_root/zshrc"
  "$repo_root/gitignore_global" "$repo_root/gitconfig" "$repo_root/vimrc"
  "$repo_root/envFolder" "$repo_root/bin" "$repo_root/screenrc" "$repo_root/tmux.conf"
  "$repo_root/cursor/commands" "$repo_root/herdr/config.toml"
  "$repo_root/herdr/new-worktree-tab.sh" "$repo_root/rex/init.lua"
  "$repo_root/rex/new-worktree-tab.sh"
  "$repo_root/skills/issue-tracking/SKILL.md"
  "$repo_root/kubernetes-setup.zsh"
)
if [[ -d "$HOME/Library/Application Support/Sublime Text" ]]; then
  required_sources+=("$repo_root/sublime-keymapping.json")
fi
if [[ -d "$HOME/Library/Application Support/Code/User" ]]; then
  required_sources+=("$repo_root/VSCode/settings.json" "$repo_root/VSCode/keybindings.json")
fi
for source in "${required_sources[@]}"; do
  if [[ ! -e "$source" ]]; then
    print -u2 -- "ERROR: Cannot link missing source $source"
    exit 1
  fi
done

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
    if [[ -n "$agent_overlay" ]]; then
      cat "$agent_overlay"
      print
    fi
    cat "$agent_base"
  } >"$instructions_file"
  ensure_file "$instructions_file" "$target"
}

# Agents share the AGENTS.md format, but use separate global instruction paths.
generate_agent_instructions "${FX_HOME:-$HOME/.fx}/AGENTS.md"
generate_agent_instructions "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
generate_agent_instructions "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"

ensure_symlink "$repo_root/cursor/commands" "$HOME/.cursor/commands"
skill_target="$HOME/.agents/skills/issue-tracking/SKILL.md"
mkdir -p "${skill_target:h}"
skill_file=$(mktemp "$skill_target.XXXXXX")
cat "$repo_root/skills/issue-tracking/SKILL.md" >"$skill_file"
ensure_file "$skill_file" "$skill_target"

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
else
  print -- "VSCode is not installed - settings and keybindings not installed"
fi

# friction-tracker writes a weekly digest of friction that keeps happening in
# agent sessions. It is built from a clone of its repository and scheduled with
# launchd, so it needs Go and macOS.
install_friction_tracker() {
  local source_dir="$HOME/Code/friction-tracker"
  local binary="$HOME/.local/bin/friction-tracker"
  local fx_sessions="${FX_HOME:-$HOME/.fx}/sessions/v2"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/friction-tracker"
  local label=com.scubbo.friction-tracker
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  local plist_file

  # An existing clone is built as it is, because it may hold work in progress.
  if [[ ! -d "$source_dir" ]]; then
    git clone git@github.com:scubbo/friction-tracker.git "$source_dir" || {
      print -u2 -- "WARNING: Could not clone friction-tracker to $source_dir - friction-tracker not installed"
      return
    }
  fi

  mkdir -p "${binary:h}" "$state_dir/logs" "${plist:h}"
  (cd "$source_dir" && go build -o "$binary" .)
  print -- "Built $binary"

  # launchd does not read shell startup files, so the job names every path in full.
  plist_file=$(mktemp "$plist.XXXXXX")
  cat >"$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>
	<key>ProcessType</key>
	<string>Background</string>
	<key>ProgramArguments</key>
	<array>
		<string>$binary</string>
		<string>scan</string>
		<string>--fx-sessions</string>
		<string>$fx_sessions</string>
		<string>--state</string>
		<string>$state_dir</string>
	</array>
	<key>StandardErrorPath</key>
	<string>$state_dir/logs/stderr.log</string>
	<key>StandardOutPath</key>
	<string>$state_dir/logs/stdout.log</string>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>9</integer>
		<key>Minute</key>
		<integer>0</integer>
		<key>Weekday</key>
		<integer>1</integer>
	</dict>
</dict>
</plist>
EOF
  ensure_file "$plist_file" "$plist"

  launchctl bootout "gui/$UID/$label" 2>/dev/null || true
  launchctl bootstrap "gui/$UID" "$plist" ||
    print -u2 -- "WARNING: Could not schedule $label. Run: launchctl bootstrap gui/$UID $plist"
}

if [[ "$os_name" == "Darwin" ]] && (( $+commands[go] )); then
  install_friction_tracker
else
  print -- "Go or launchd is not available - friction-tracker not installed"
fi

source "$repo_root/kubernetes-setup.zsh"
setup_kubernetes

print -- "Dotfiles installed."
if [[ "$MACHINE_TYPE" == "personal" && -z "$agent_overlay" ]]; then
  print -u2 -- "WARNING: Agent instructions contain only the base; the personal overlay was not found."
fi
