#!/bin/zsh

set -e

# Install dotfiles
cd ~
git clone git@github.com:scubbo/dotfiles.git
rm .gitconfig # It might have got added while you were doing other things, and ln would complain
ln -s dotfiles/zshrc .zshrc
ln -s dotfiles/zshrc-local-mactop .zshrc-local
ln -s dotfiles/gitignore_global .gitignore_global
ln -s dotfiles/gitconfig .gitconfig
ln -s dotfiles/gitconfig-work .gitconfig-work
ln -s dotfiles/vimrc .vimrc
ln -s dotfiles/envFolder .env
ln -s dotfiles/bin bin

echo "Dotfiles installed. Now to give you some tools!"

echo "First of all, we install toolbox"
mwinit
kinit

# Yes, this is pretty insecure. But, what else were you gonna do -
# visually verify that the downloaded file "looks correct"? I doubt it :P
#
# from https://w.amazon.com/bin/view/BuilderToolbox/GettingStarted
/usr/bin/curl --negotiate -fLSsu: 'https://drive.corp.amazon.com/view/BuilderToolbox/toolbox-install.sh' -o /tmp/toolbox-install.sh && /bin/bash /tmp/toolbox-install.sh

echo "Then, install brazil"
toolbox install brazilcli

echo "And bats-cli"
toolbox install batscli

# See above...
echo "And install brew"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
echo "Install the Amazon tap"
brew tap amazon/amazon "ssh://git.amazon.com/pkg/HomebrewAmazon"
echo "And NinjaDevSync"
brew install ninja-dev-sync
echo "And watch"
brew install watch


echo "Creating case-Sensitive Volumes"
cd ~
git clone ssh://git.amazon.com/pkg/MacOSEncryptedVolumeTools
MacOSEncryptedVolumeTools/bin/create-encrypted-apfs-volume workplace
MacOSEncryptedVolumeTools/bin/create-encrypted-apfs-volume brazil-pkg-cache
brazil prefs --global --key packagecache.cacheRoot --value /Volumes/brazil-pkg-cache/
ln -s /Volumes/workplace ~/workplace
rm -rf MacOSEncryptedVolumeTools

# Install AWS CLI - http://docs.aws.amazon.com/cli/latest/userguide/installing.html#install-bundle-other-os
cd /tmp
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip awscli-bundle.zip
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

echo "In System Preferences, tweak things how you prefer:"
echo " * Dock -> Automatically hide and show the Dock"
echo " * Mouse -> Tracking Speed -> 7"
echo "Go to https://www.iterm2.com/downloads.html to install iTerm"
echo "Now go to https://tiny.amazon.com/zigp89oi/ to install Java"
echo "Now go to https://github.com/tonsky/FiraCode to install FiraCode"
echo "Now install IntelliJ and:"
echo " * Set the license server to https://jetbrains-license-server.corp.amazon.com"
echo " * Set Fira to the font (Editor -> Font)"
echo "Now go to https://tiny.amazon.com/apzht95n and install CRUX"
echo "Now go to https://www.dropbox.com and install Dropbox"
echo "Now go to https://tiny.amazon.com/lxgan6i9 and set up connections to Redshift"
echo "Go to https://www.sublimetext.com/ and install Sublime"
echo "Go to https://www.sublimetext.com/docs/3/osx_command_line.html for instructions on how to set it up for CLI"
echo "Install Firefox, set as default, set search keywords"
echo "Install Outlook - use Self-Service to get a License. Change settings to prevent read-on-preview"
