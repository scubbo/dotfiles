#
# .zshrc is sourced in interactive shells.
# It should contain commands to set up aliases,
# functions, options, key bindings, etc.
#

source ~/.zshrc-local

#set timezone
TZ='America/Los_Angeles'; export TZ;

autoload -U compinit
compinit

#allow tab completion in the middle of a word
setopt COMPLETE_IN_WORD

## never ever beep ever
setopt NO_BEEP

autoload -U colors
colors

#colors for vim
export TERM=xterm-256color

# less options ( don't you mean fewer? https://xkcd.com/326/ ;) )
export LESS="-iR"
# and grep options
export GREP_OPTIONS="--color=auto"
export EDITOR=vi

bindkey '\e[1~'   beginning-of-line  # Linux console
bindkey '\e[H'    beginning-of-line  # xterm
bindkey '\eOH'    beginning-of-line  # gnome-terminal
bindkey '\e[2~'   overwrite-mode     # Linux console, xterm, gnome-terminal
bindkey '\e[3~'   delete-char        # Linux console, xterm, gnome-terminal
bindkey '\e[4~'   end-of-line        # Linux console
bindkey '\e[F'    end-of-line        # xterm
bindkey '\eOF'    end-of-line        # gnome-terminal

function pskill() {
    psgrep $1 | perl -pe 's/\S*\s*(\S*).*/$1/' | xargs kill -9
}
alias exist="echo 'Do I really need to be told to exist?\nI choose not to. Exiting in 3...';sleep 1;echo '2...';sleep 1;echo '1...';sleep 1;echo 'Goodbye cruel world';exit"
alias loglist="ls | perl -pe 's/(.*?)\..*/$1/g' | uniq"
alias svi='sudo -E vi'
alias pyserv='python -m SimpleHTTPServer'
alias please='sudo'
alias guom='git branch --set-upstream-to origin/mainline'
alias sqp='git sqa; git push -f'
alias vi='vim -O'
alias cdup='cd `findup Config`'
alias lcm='git log -1 --format=%B | grep -v "^cr" | pbcopy'
# https://apple.stackexchange.com/questions/110343/copy-last-command-in-terminal -
# `echo "!!" | pbcopy` works on command line, but not from zshrc (copies literal "!!")
alias copylast='fc -ln -1 | awk '{$1=$1}1' | pbcopy '
alias runlast='sudo chmod +x "$_"; $_'
alias dr='docker compose run --rm'

function sgrep() {
        grep -ir "$1" . | grep -v -e 'build' -e '.git' -e '^Binary'
}

function projbranch() {
    echo $(($(find $LOCATION -maxdepth 1 -type d| wc -l)-1))
    for i in *;
    do
        packageName=$i;
        pushd $i >/dev/null;
        branchName=git symbolic-ref HEAD 2>/dev/null | perl -pe 's:/refs/heads/::';
        popd >/dev/null
    done
}

psearch () {
    ps aux | grep -i $1 | grep -v 'grep'
}


source $HOME/bin/indexed-funcs.zsh

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html
export AWS_PAGER="";

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

###
# Path Alterations
###
# Visual Studio Code
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
# Use curl from Homebrew
export PATH=/usr/local/opt/curl/bin:$PATH
# And bin from homeir
export PATH=$HOME/bin:$PATH

# Must come after adding `$HOME/bin` to `$PATH`
echo "\nHERE IS A PICTURE OF A CAT:\n"
# http://stackoverflow.com/a/677212/1040915
if hash cat-art 2>/dev/null; then
  cat-art
else
  echo "You do not have cat-art installed, you heathen!"
fi
echo ""


#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

export PATH="$HOME/.local/bin:$PATH"
