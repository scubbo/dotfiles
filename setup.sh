#!/bin/zsh

set -e

# Install dotfiles
rm -f $HOME/.gitconfig # It might have got added while you were doing other things, and ln would complain
ln -s ~/Code/dotfiles/zshrc $HOME/.zshrc
arch_name=$(uname -m)
if [[ "$arch_name" = "x86_64" ]; then
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

echo "Dotfiles installed. Now to give you some tools!"

echo "Installing brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
echo "And watch"
brew install watch

echo "Now go to https://github.com/tonsky/FiraCode to install FiraCode"
echo "Now install IntelliJ and:"
echo " * Set the license server to https://jetbrains-license-server.corp.amazon.com"
echo " * Set Fira to the font (Editor -> Font)"
echo "Now go to https://tiny.amazon.com/apzht95n and install CRUX"
echo "Now go to https://www.dropbox.com and install Dropbox"
echo "Now go to https://tiny.amazon.com/lxgan6i9 and set up connections to Redshift"
echo "Go to https://www.sublimetext.com/ and install Sublime"
echo "Go to https://www.sublimetext.com/docs/3/osx_command_line.html for instructions on how to set it up for CLI"
