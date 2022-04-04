# https://stackoverflow.com/a/49105399/1040915
declare -a funcs=(psearch tabname ff grhh grup)
# AFAIK, there's no way to ensure that these "associative arrays"
# (Dictionaries, basically) have key-sets that match `funcs` -
# nor have I figured out how to do the obvious thing of
# making a single dictionary whose values are a tuple of
# (name, doc, def).
declare -A docs=(
    [psearch]="Search ps"
    [tabname]="Change the name of the current tab"
    [ff]="Follow File (tail with an empty screen)"
    [grhh]="Git Reset Hard Head"
    [grup]="Git Reset to UPstream"
)

declare -A defs=(
    [psearch]="ps aux | grep -i $1 | grep -v 'grep'"
    [tabname]='printf "\e]1;$1\a"'
    [ff]="clear; tail -Fn0"
    [grhh]="git reset --hard HEAD"
    [grup]="git reset --hard @{u}"
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
