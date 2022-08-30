#!/bin/zsh

set -e

# Install dotfiles
rm -f $HOME/.gitconfig # It might have got added while you were doing other things, and ln would complain
ln -s ~/Code/dotfiles/zshrc $HOME/.zshrc
arch_name=$(uname -m)
if [[ "$arch_name" == "x86_64" ]; then
  # OK, I know this doesn't _necessarily_ mean it's a Mac - but, on all machines I'll be running
  # this on, it's a fair bet!
  ln -s ~/Code/dotfiles/zshrc-local-mactop $HOME/.zshrc-local
elif [[ "$arch_name" = "aarch64" ]; then
  ln -s ~/Code/dotfiles/zshrc-local-pi $HOME/.zshrc-local
else
  echo "Unrecognized architecture: $arch_name"
  exit 1
fi
ln -s ~/Code/dotfiles/gitignore_global $HOME/.gitignore_global
ln -s ~/Code/dotfiles/gitconfig $HOME/.gitconfig
ln -s ~/Code/dotfiles/vimrc $HOME/.vimrc
ln -s ~/Code/dotfiles/envFolder $HOME/.env
ln -s ~/Code/dotfiles/bin $HOME/bin
ln -s ~/Code/dotfiles/screenrc $HOME/.screenrc

echo "Dotfiles installed."
