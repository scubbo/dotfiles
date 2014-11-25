#
# .zshrc is sourced in interactive shells.
# It should contain commands to set up aliases,
# functions, options, key bindings, etc.
#

source ~/.zshrc-local

#set timezone
TZ=GB; export TZ;

autoload -U compinit
compinit

#allow tab completion in the middle of a word
setopt COMPLETE_IN_WORD

## never ever beep ever
setopt NO_BEEP

## automatically decide when to page a list of completions
#LISTMAX=0

## disable mail checking
#MAILCHECK=0

autoload -U colors
colors

#colors for vim
export TERM=xterm-256color

autoload -U edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# less options ;)
export LESS="-i"

bindkey '\e[1~'   beginning-of-line  # Linux console
bindkey '\e[H'    beginning-of-line  # xterm
bindkey '\eOH'    beginning-of-line  # gnome-terminal
bindkey '\e[2~'   overwrite-mode     # Linux console, xterm, gnome-terminal
bindkey '\e[3~'   delete-char        # Linux console, xterm, gnome-terminal
bindkey '\e[4~'   end-of-line        # Linux console
bindkey '\e[F'    end-of-line        # xterm
bindkey '\eOF'    end-of-line        # gnome-terminal

alias psgrep="ps aux | grep -v 'grep' | grep "
alias exist="echo 'Do I really need to be told to exist?\nI choose not to. Exiting in 3...';sleep 1;echo '2...';sleep 1;echo '1...';sleep 1;echo 'Goodbye cruel world';exit"

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

alias loglist="ls | perl -pe 's/(.*?)\..*/$1/g' | uniq"

alias ff="clear; tail -fn0"

alias svi='sudo -E vi'

alias pyserv='python -m SimpleHTTPServer'

# Tabname is always handy
tabname () {
	printf "\e]1;$1\a"
}

# make pushd and popd work properly (i.e. silently)
# Doesn't work atm
#push () {
#	pushd $1 > /dev/null
#}
#
#pop () {
#	popd $1 > /dev/null
#}


echo "\n\nHERE IS A PICTURE OF A CAT:\n"
cat-art
echo ""

# Work on this shortcut: git status --porcelain | sed -ne 's/^ M //p' | tr '\n' '\0' | xargs -0 vi

source ~/.env/zshrc
