# Rex

`init.lua` defines the keyboard shortcuts and the `New Worktree Tab` and
`Fork Agent into Split Pane` actions.
Each session holds one repository. Each tab holds one Git worktree.

Run `./setup.sh` from the repository root to install links to `init.lua` and
`new-worktree-tab.sh`. The installer backs up existing files and leaves Rex's
runtime data in place.

In Rex Settings, enable Remote Control under Rex Server. The helper uses this
permission to select the created tab in the app that opened the popup.

Press `Alt+Z`, then `C` to enter a topic. The helper creates or reuses a worktree,
opens a tab, and selects it. If the source terminal is outside a Git repository,
the popup first asks for the repository path.

Press `Alt+Z`, then `F` in a pane that runs fx to fork its conversation. The
action copies the conversation and opens the copy in a pane on the right, in
the same tab. The original agent keeps running. `rex do fork_agent_pane` does
the same from a terminal in the pane.

The copy ends at the last finished turn. A turn that is still running stays
out of the copy, and so do the conversation's subagents. The action fails
without opening a pane when the pane doesn't run fx, when the conversation
has no finished turn, or when one fx has several conversations open.

fx has no command that forks a conversation from outside its shell. The action
uses `fx session recover`, which copies a conversation into a new one and
leaves the source unchanged.

## Tests

Run these commands from the repository root:

```sh
shellcheck rex/new-worktree-tab.sh
python3 -m unittest discover -s rex/tests -p test_worktree.py -v
python3 rex/tests/smoke_rex.py
python3 rex/tests/smoke_fork_agent_pane.py
```

`smoke_rex.py` needs one connected Rex app with Remote Control enabled. Run it
from a Rex terminal. It opens a temporary session, checks which tab receives
keyboard input, and returns to the calling tab. It removes its temporary
session and Git repositories when it finishes.

`smoke_fork_agent_pane.py` needs a running Rex server and a signed-in fx. It
runs fx with a temporary `FX_HOME`, so it doesn't read or change your saved
conversations. It sends one short model request to create the conversation
that it forks. It removes its temporary session and fx profile when it
finishes.
