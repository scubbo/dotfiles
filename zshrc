#
# .zshrc is sourced in interactive shells.
# It should contain commands to set up aliases,
# functions, options, key bindings, etc.
#

DOTFILES_USE_SOCKET_FIREWALL=0
source ~/.zshrc-local

# Make user-installed tools available to optional integrations below.
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

#set timezone
TZ='America/Los_Angeles'; export TZ;

#allow tab completion in the middle of a word
setopt COMPLETE_IN_WORD

## never ever beep ever
setopt NO_BEEP

autoload -U colors
colors

# less options ( don't you mean fewer? https://xkcd.com/326/ ;) )
export LESS="-iR"
alias grep='grep --color=auto'
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
alias pyserv='python -m http.server'
alias please='sudo'
alias guom='git branch --set-upstream-to origin/mainline'
alias sqp='git sqa; git push -f'
alias vi='vim -O'
alias cdup='cd `findup Config`'
if [[ "$OSTYPE" == darwin* ]]; then
  alias lcm='git log -1 --format=%B | grep -v "^cr" | pbcopy'
  alias copylast='fc -ln -1 | awk '\''{$1=$1}1'\'' | pbcopy '
elif (( $+commands[wl-copy] )); then
  alias lcm='git log -1 --format=%B | grep -v "^cr" | wl-copy'
  alias copylast='fc -ln -1 | awk '\''{$1=$1}1'\'' | wl-copy '
fi
alias runlast='sudo chmod +x "$_"; $_'
alias dr='docker compose run --rm'
if [[ "$OSTYPE" == darwin* ]]; then
  alias zed="open -a /Applications/Zed.app"
  alias flush_cache="sudo dscacheutil -flushcache ;sudo killall -HUP mDNSResponder"
fi
alias oc="opencode2"

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

# Courtesy of https://gist.github.com/johnlindquist/4deb59e4d74a36c8a4cc2362663f8299
funced () {
	[[ -z "$1" ]] && {
		echo "Usage: funced <function_name>"
		return 1
	}
	local func="$1"
	[[ $(whence -w "$func" 2>/dev/null) != *function* ]] && {
		echo "'$func' is not a function"
		return 1
	}
	local file="${functions_source[$func]}"
	[[ -z "$file" || ! -f "$file" ]] && {
		echo "Can't find source file for '$func'"
		return 1
	}
	local line=$(grep -n -m1 -E "^\s*(function\s+)?${func}\s*\(|eval\s+[\"']${func}\s*\(" "$file" | cut -d: -f1)
	[[ -z "$line" ]] && line=1
	local editor_name="${EDITOR_CMD:t}"
	case "$editor_name" in
		(zed) "$EDITOR_CMD" "$file:$line" ;;
		(cursor | code | code-insiders) "$EDITOR_CMD" -g "$file:$line" ;;
		(micro) "$EDITOR_CMD" "+$line" "$file" ;;
		(vim | nvim) "$EDITOR_CMD" "+$line" "$file" ;;
		(*) "$EDITOR_CMD" "$file:$line" ;;
	esac
}

function mc () {
  mkdir -p "$1" && cd "$1";
}


source $HOME/bin/indexed-funcs.zsh

autoload -U compinit && compinit
autoload -U +X bashcompinit && bashcompinit
if (( $+commands[terraform] )); then
  complete -o nospace -C "${commands[terraform]}" terraform
fi

if (( $+commands[fnm] )); then
  eval "$(fnm env --use-on-cd)"
fi

# https://docs.aws.amazon.com/cli/latest/userguide/cli-usage-pagination.html
export AWS_PAGER="";

if (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

###
# Path Alterations
###
if [[ "$OSTYPE" == darwin* ]]; then
  export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
fi

# Must come after adding `$HOME/bin` to `$PATH`
echo "\nHERE IS A PICTURE OF A CAT:\n"
# http://stackoverflow.com/a/677212/1040915
if (( $+commands[cat-art] && $+commands[perl] )); then
  cat-art
else
  echo "You do not have cat-art installed, you heathen!"
fi
echo ""


# Must come after adding `$HOME/.local/bin` to `$PATH`
source $HOME/bin/friction-tracker-reminder.zsh

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Added by Hades
export PATH="$PATH:$HOME/.hades/bin"

export PATH="$HOME/.openharness/bin:$HOME/.opencode/bin:$PATH"

if [[ "$DOTFILES_USE_SOCKET_FIREWALL" == 1 ]]; then
# BEGIN: socket firewall aliases (managed by Iru)
alias npm="sfw npm"
alias pnpm="sfw pnpm"
alias bun="sfw bun"
# END: socket firewall aliases (managed by Iru)
fi
unset DOTFILES_USE_SOCKET_FIREWALL

# Added by MDM Homebrew Postinstall Automation
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
