# https://stackoverflow.com/a/49105399/1040915
declare -a funcs=(tabname ff grhh grup gca psgrep dps token vif k dc kex)
# AFAIK, there's no way to ensure that these "associative arrays"
# (Dictionaries, basically) have key-sets that match `funcs` -
# nor have I figured out how to do the obvious thing of
# making a single dictionary whose values are a tuple of
# (name, doc, def).
declare -A docs=(
    [tabname]="Change the name of the current tab"
    [ff]="Follow File (tail with an empty screen)"
    [grhh]="Git Reset Hard Head"
    [grup]="Git Reset to UPstream"
    [gca]="Git Commit Amend (update most recent commit's message)"
    [psgrep]="Grep through ps"
    [dps]="Docker ps (pretty-formatted)"
    [token]="Copy Kubernetes Dashboard token"
    [vif]="Find into vim"
    [k]="kubectl shortcut"
    [dc]="docker compose"
    [kex]="Kubectl EXec in the first pod in namespace"
)

declare -A defs=(
    [tabname]='printf "\e]1;$1\a"'
    [ff]="clear; tail -Fn0"
    [grhh]="git reset --hard HEAD"
    [grup]="git reset --hard @{u}"
    [gca]="git commit --amend"
    [psgrep]='ps aux | grep -i $1 | grep -v "grep"'
    [dps]="docker ps --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'"
    [token]=$'kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}" | pbcopy'
    # 0h 0h Oh!
    # TODO - it would be cool to be able to pass options to `find` (even _cooler_ to be able to arbitrarily pass options to either!)
    [vif]='find . -iname "*$1" -print0 | xargs -0 vi -O'
    [k]='kubectl $@'
    [dc]='docker compose $@'
    [kex]="kubectl get pods --no-headers | head -n1 | awk '{print \$1}' | xargs -o -I {} sh -c 'kubectl exec -it {} -- /bin/bash'"
)

# https://unix.stackexchange.com/a/287333/30828
randomlyChosenFunction=$funcs[$(( $RANDOM % ${#funcs[@]} + 1 ))]
echo "Random function to try today is:"
echo -e "\033[1m$randomlyChosenFunction\033[0m: $docs[$randomlyChosenFunction]"


for func in $funcs
do
    # https://stackoverflow.com/a/35545412/1040915
    eval "$(cat <<EOF
$func() {
    $defs[$func]
}
EOF
)"
done
