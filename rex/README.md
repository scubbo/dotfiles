# Rex

`init.lua` defines the keyboard shortcuts and the `New Worktree Tab` action.
Each session holds one repository. Each tab holds one Git worktree.

Run `./setup.sh` from the repository root to install links to `init.lua` and
`new-worktree-tab.sh`. The installer backs up existing files and leaves Rex's
runtime data in place.

In Rex Settings, enable Remote Control under Rex Server. The helper uses this
permission to select the created tab in the app that opened the popup.

Press `Alt+Z`, then `C` to enter a topic. The helper creates or reuses a worktree,
opens a tab, and selects it. If the source terminal is outside a Git repository,
the popup first asks for the repository path.

## Tests

Run these commands from the repository root:

```sh
shellcheck rex/new-worktree-tab.sh
python3 -m unittest discover -s rex/tests -p test_worktree.py -v
python3 rex/tests/smoke_rex.py
```

The app test needs one connected Rex app with Remote Control enabled. Run it
from a Rex terminal. It opens a temporary session, checks which tab receives
keyboard input, and returns to the calling tab. It removes its temporary
session and Git repositories when it finishes.
