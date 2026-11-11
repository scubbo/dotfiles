# Says when a friction-tracker digest is waiting to be read.
#
# Agents also load the shell startup files, and they capture the output of every
# command they run. A reminder there would cost tokens each time and help no
# one, so it is printed only when the output goes to a terminal.
if [[ -o interactive && -t 1 ]] && (( $+commands[friction-tracker] )); then
  friction-tracker unread
fi
