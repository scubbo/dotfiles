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
ln -s dotfiles/vimrc .vimrc
ln -s dotfiles/envFolder .env
ln -s dotfiles/bin bin

# Install ReviewBoard - https://w.amazon.com/index.php/BuilderTools/Product/ReviewBoard/UserGuide/Mac
sudo easy_install pip
sudo pip install setuptools --no-use-wheel --upgrade
sudo pip install urllib2_kerberos
sudo pip install simplejson
sudo pip install kerberos
cd /tmp
git clone -b RBTools-0.5 ssh://git.amazon.com:2222/pkg/RBTools
cd RBTools
sudo python setup.py install

# Install AWS CLI - http://docs.aws.amazon.com/cli/latest/userguide/installing.html#install-bundle-other-os
cd /tmp
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
unzip awscli-bundle.zip
sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

echo "Now go to https://w.amazon.com/index.php/BrazilCLI%202.0/Runtimes/Java to install Java"
echo "Now go to https://w.amazon.com/index.php/BrazilCLI_2.0/GettingStarted to install Brazil"
echo "Not go to https://github.com/tonsky/FiraCode to install FiraCode"
echo "Now install IntelliJ - set Fira to the font (Editor -> Font)"
echo "Now go to https://w.amazon.com/index.php/BuilderTools/Product/CodeBrowser/CRUX and install CRUX"
echo "Now go to https://www.dropbox.com and install Dropbow"
