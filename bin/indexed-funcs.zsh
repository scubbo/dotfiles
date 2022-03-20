# https://stackoverflow.com/a/49105399/1040915
declare -a funcs=(psearch tabnamenew)
# AFAIK, there's no way to ensure that these "associative arrays"
# (Dictionaries, basically) have key-sets that match `funcs` - 
# nor have I figured out how to do the obvious thing of
# making a single dictionary whose values are a tuple of
# (name, doc, def).
declare -A docs=(
    [psearch]="Search ps"
    [tabnamenew]="Change the name of the current tab"
)

declare -A defs=(
    [psearch]="ps aux | grep -i $1 | grep -v 'grep'"
    [tabnamenew]='printf "\e]1;$1\a"'
)

# https://unix.stackexchange.com/a/287333/30828
randomlyChosenFunction=$funcs[$(( $RANDOM % ${#funcs[@]} + 1 ))]
echo "Random function to try today is:"
echo "$randomlyChosenFunction"
echo "DOCS: $docs[$randomlyChosenFunction]"


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