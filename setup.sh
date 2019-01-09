# Set up workspace
sudo mkdir /localWorkspace
cd /localWorkspace
sudo chown jackjack: .
# Examples here are from TAPS. Replace this with whichever packages you care about
#brazil ws --create --name AIVTitleActionPresentationService --root AIVTitleActionPresentationService
#cd AIVTitleActionPresentationService
#brazil ws --use -p AIVTitleActionPresentationService
#brazil ws --use -p AIVOfferPersonalization
#brazil ws --use -p AIVAcquisitionVendingLibrary

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

# Install AWS CLI - http://docs.aws.amazon.com/cli/latest/userguide/installing.html#install-bundle-other-os
cd /tmp
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip awscli-bundle.zip
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

echo "Now go to https://tiny.amazon.com/zigp89oi/ to install Java"
echo "Now go to https://tiny.amazon.com/1b2yj1y5p/ to install Brazil"
echo "Not go to https://github.com/tonsky/FiraCode to install FiraCode"
echo "Now install IntelliJ - set Fira to the font (Editor -> Font)"
echo "Now go to https://tiny.amazon.com/apzht95n and install CRUX"
echo "Now go to https://www.dropbox.com and install Dropbow"
echo "Now go to https://tiny.amazon.com/lxgan6i9 and set up connections to Redshift"
