#!/bin/zsh

set -e

# Detect machine type
current_hostname=$(hostname)
arch_name=$(uname -m)

if [[ "$current_hostname" == "MacBookPro.avril" ]]; then
  MACHINE_TYPE="personal"
  ln -sf ~/Code/dotfiles/zshrc-local-mactop $HOME/.zshrc-local
  ln -sf ~/Code/dotfiles/gitconfig-personal $HOME/.gitconfig-local
elif [[ "$current_hostname" == "Mac.avril" ]]; then
  MACHINE_TYPE="work"
  ln -sf ~/Code/dotfiles/zshrc-work-mactop $HOME/.zshrc-local
  ln -sf ~/Code/dotfiles/gitconfig-professional $HOME/.gitconfig-local
elif [[ "$arch_name" == "aarch64" ]]; then
  MACHINE_TYPE="personal"
  ln -sf ~/Code/dotfiles/zshrc-local-pi $HOME/.zshrc-local
  ln -sf ~/Code/dotfiles/gitconfig-personal $HOME/.gitconfig-local
else
  echo "Unrecognized machine: hostname=$current_hostname, arch=$arch_name"
  exit 1
fi

# Install dotfiles
ln -sf ~/Code/dotfiles/zshrc $HOME/.zshrc
ln -sf ~/Code/dotfiles/gitignore_global $HOME/.gitignore_global
ln -sf ~/Code/dotfiles/gitconfig $HOME/.gitconfig
ln -sf ~/Code/dotfiles/vimrc $HOME/.vimrc
ln -sfn ~/Code/dotfiles/envFolder $HOME/.env
ln -sfn ~/Code/dotfiles/bin $HOME/bin
ln -sf ~/Code/dotfiles/screenrc $HOME/.screenrc
ln -sf ~/Code/dotfiles/tmux.conf $HOME/.tmux.conf
# Generate ~/.claude/CLAUDE.md from base + machine-specific overlay
mkdir -p $HOME/.claude
CLAUDE_WARNING="<!-- GENERATED FILE - DO NOT EDIT DIRECTLY -->\n<!-- Edit CLAUDE-base.md and CLAUDE-work.md (or CLAUDE-personal.md) in dotfiles repo -->\n\n"
CLAUDE_BASE=~/Code/dotfiles/.claude/CLAUDE-base.md

if [[ "$MACHINE_TYPE" == "work" ]]; then
  CLAUDE_OVERLAY=~/Code/dotfiles/.claude/CLAUDE-work.md
else
  CLAUDE_OVERLAY=~/Code/dotfiles-private/.claude/CLAUDE-personal.md
  if [[ ! -f "$CLAUDE_OVERLAY" ]]; then
    echo "ERROR: Personal machine detected but $CLAUDE_OVERLAY not found."
    echo "Please clone dotfiles-private repo to ~/Code/dotfiles-private"
    exit 1
  fi
fi

echo -e "$CLAUDE_WARNING" > $HOME/.claude/CLAUDE.md
cat "$CLAUDE_OVERLAY" >> $HOME/.claude/CLAUDE.md
echo "" >> $HOME/.claude/CLAUDE.md
cat "$CLAUDE_BASE" >> $HOME/.claude/CLAUDE.md
mkdir -p ~/.cursor
if [[ -d "$HOME/.cursor/commands" ]]; then
  echo "Cannot link ~/.cursor/commands - already exists"
else
  ln -s ~/Code/dotfiles/cursor/commands $HOME/.cursor/commands
fi

# Install Sublime keybindings, if sublime is present
SUBLIME_KEYMAPPING_DIR="$HOME/Library/Application Support/Sublime Text"
SUBLIME_KEYMAPPING_FILE="$SUBLIME_KEYMAPPING_DIR/Default (OSX).sublime-keymap"
if [ -d "$SUBLIME_KEYMAPPING_DIR" ]; then
  if [ -e "$SUBLIME_KEYMAPPING_FILE" ]; then
    echo "User key-mapping file for Sublime already exists, not overwriting"
  else
    ln -s ~/Code/dotfiles/sublime-keymapping.json "$SUBLIME_KEYMAPPING_DIR/Default (OSX).sublime-keymap"
  fi
else
  echo "Sublime is not currently installed - Sublime key-mappings not installed"
fi

VSCODE_APP_DIR="$HOME/Library/Application Support/Code/User"
if [ -d "$VSCODE_APP_DIR" ]; then

  # Exists and is a regular file - i.e. is not a symlink
  SETTINGS_FILE_PATH="$VSCODE_APP_DIR/settings.json"
  if [ -f "$SETTINGS_FILE_PATH" ]; then
    rm -f "$SETTINGS_FILE_PATH"
    ln -s VSCode/settings.json "$SETTINGS_FILE_PATH"
  fi

  KEYBINDINGS_FILE_PATH="$VSCODE_APP_DIR/keybindings.json"
  if [ -f "$KEYBINDINGS_FILE_PATH" ]; then
    rm -f "$KEYBINDINGS_FILE_PATH"
    ln -s VSCode/keybindings.json "$KEYBINDINGS_FILE_PATH"
  fi

  EXTENSIONS_DIR_PATH="$HOME/.vscode/extensions"
  if [[ -d "$EXTENSIONS_DIR_PATH" && ! -L "$EXTENSIONS_DIR_PATH" ]]; then
    rm -rf "$EXTENSIONS_DIR_PATH"
    ln -s VSCode/extensions "$EXTENSIONS_DIR_PATH"
  fi

else
  echo "VSCode is not installed - settings and keybindings not installed"
fi

echo "Dotfiles installed."
