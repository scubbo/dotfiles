#!/bin/zsh

set -e

# Install dotfiles
ln -s ~/Code/dotfiles/zshrc $HOME/.zshrc
arch_name=$(uname -m)
if [[ "$arch_name" == "x86_64" ]]; then
  # OK, I know this doesn't _necessarily_ mean it's a Mac - but, on all machines I'll be running
  # this on, it's a fair bet!
  # TODO - do this on hostname as well/instead
  ln -s ~/Code/dotfiles/zshrc-local-mactop $HOME/.zshrc-local
  ln -s ~/Code/dotfiles/gitconfig-personal $HOME/.gitconfig-local
elif [[ "$arch_name" = "aarch64" ]]; then
  ln -s ~/Code/dotfiles/zshrc-local-pi $HOME/.zshrc-local
  ln -s ~/Code/dotfiles/gitconfig-personal $HOME/.gitconfig-local
elif [[ "$arch_name" = "arm64" ]]; then
  ln -s ~/Code/dotfiles/zshrc-work-mactop $HOME/.zshrc-local
  ln -s ~/Code/dotfiles/gitconfig-professional $HOME/.gitconfig-local
else
  echo "Unrecognized architecture: $arch_name"
  exit 1
fi

ln -s ~/Code/dotfiles/gitignore_global $HOME/.gitignore_global
rm -f $HOME/.gitconfig # It might have got added while you were doing other things, and ln would complain
ln -s ~/Code/dotfiles/gitconfig $HOME/.gitconfig
ln -s ~/Code/dotfiles/vimrc $HOME/.vimrc
ln -s ~/Code/dotfiles/envFolder $HOME/.env
ln -s ~/Code/dotfiles/bin $HOME/bin
ln -s ~/Code/dotfiles/screenrc $HOME/.screenrc
ln -s ~/Code/dotfiles/.claude $HOME/.claude

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
  if [ -d "$EXTENSIONS_DIR_PATH" && ! -L "$EXTENSIONS_DIR_PATH" ]; then
    rm -rf "$EXTENSIONS_DIR_PATH"
    ln -s VSCode/extensions "$EXTENSIONS_DIR_PATH"
  fi

else
  echo "VSCode is not installed - settings and keybindings not installed"
fi

echo "Dotfiles installed."
