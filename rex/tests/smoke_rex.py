"""Check the popup and real Rex tab creation in a disposable session."""
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import time

from test_worktree import HELPER, WorktreeTests


REX = shutil.which("rex")
CONFIG = HELPER.parent / "init.lua"


def rex(*args, as_json=True, env=None):
    result = subprocess.run([REX, "--autostart=false", *args],
                            check=True, text=True, capture_output=True, env=env)
    return json.loads(result.stdout) if as_json else result.stdout


def wait_for(check):
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for Rex")


def placed_blocks(session_id):
    view = rex("session", "inspect", session_id, "--json")
    return [block["block_id"] for window in view["windows"]
            for layer in window["layers"] for block in layer["blocks"]]


def main():
    fixture = WorktreeTests()
    session_id = None
    app_selected = False
    client_id = rex("client", "inspect", "--json")["client"]["client_id"]
    caller = rex("whoami", "--json")
    try:
        fixture.setUp()
        fixture.env["PATH"] = os.environ["PATH"]  # Use real Rex, not the unit-test stub.
        fixture.env["REX_CLIENT"] = client_id
        config_home = fixture.root / "config"
        helper = config_home / "rex" / "new-worktree-tab.sh"
        helper.parent.mkdir(parents=True)
        helper.write_text(
            f"export REX_TAB_WORKTREE_ROOT={shlex.quote(str(fixture.wt_root))}\n"
            f"export REX_TAB_LOG={shlex.quote(str(fixture.log))}\n"
            f"exec bash {shlex.quote(str(HELPER))} \"$@\"\n"
        )
        action_env = dict(os.environ, XDG_CONFIG_HOME=str(config_home))
        created = rex("new", "rex-worktree-smoke", "-c", str(fixture.repo), "--json",
                      "--shell=none", "--", "/bin/bash", "--noprofile", "--norc")
        session_id = created["session_id"]
        source = created["initial_windows"][0]["block_ids"][0]

        def source_ready():
            process = rex("block", "call", "-s", session_id, "-b", source, "process")
            cwd = process.get("foreground", {}).get("cwd")
            return cwd and Path(cwd).resolve() == fixture.repo.resolve()

        wait_for(source_ready)
        rex("-C", client_id, "do", "session.select", f"session_id={session_id}",
            f"window_id={created['initial_windows'][0]['window_id']}", as_json=False)
        app_selected = True
        popup = rex("-C", client_id, "do", str(CONFIG), "--action", "new_worktree_tab",
                    "-s", session_id, "-b", source, "--json", env=action_env)
        popup_block = popup["block_ids"][0]
        capture = wait_for(lambda: (
            text if "Topic:" in (text := rex("capture", "-s", session_id,
                                             "-b", popup_block, "--trim", "--unwrap", as_json=False))
            else None
        ))
        assert str(fixture.repo.resolve()) in capture, capture
        view = rex("session", "inspect", session_id, "--json")
        layer = next(layer for window in view["windows"] for layer in window["layers"]
                     if layer["layer_id"] == popup["layer_id"])
        assert layer["kind"] == "floating", layer
        assert layer["bounds"] == [0.2, 0.35, 0.6, 0.3], layer
        rex("send-key", "-s", session_id, "-b", popup_block, "enter", as_json=False)
        wait_for(lambda: popup_block not in placed_blocks(session_id))
        print("PASS: action opens a 60% × 30% topic popup in the source repo; Enter cancels it")

        outside = rex("window", "new", "-s", session_id, "outside-repo", "-c", str(fixture.root),
                      "--json", "--shell=none", "--", "/bin/bash", "--noprofile", "--norc")
        outside_block = outside["block_ids"][0]

        def outside_ready():
            process = rex("block", "call", "-s", session_id, "-b", outside_block, "process")
            cwd = process.get("foreground", {}).get("cwd")
            return cwd and Path(cwd).resolve() == fixture.root.resolve()

        wait_for(outside_ready)
        rex("-C", client_id, "do", "session.select", f"session_id={session_id}",
            f"window_id={outside['window_id']}", as_json=False)
        popup = rex("-C", client_id, "do", str(CONFIG), "--action", "new_worktree_tab",
                    "-s", session_id, "-b", outside_block, "--json", env=action_env)
        popup_block = popup["block_ids"][0]

        def popup_contains(text):
            return text in rex("capture", "-s", session_id, "-b", popup_block,
                               "--trim", "--unwrap", as_json=False)

        wait_for(lambda: popup_contains("Repository path (blank to cancel):"))
        rex("send", "-s", session_id, "-b", popup_block, str(fixture.repo), as_json=False)
        rex("send-key", "-s", session_id, "-b", popup_block, "enter", as_json=False)
        wait_for(lambda: popup_contains("Topic:"))
        assert popup_contains("Repo: " + str(fixture.repo.resolve()))
        rex("send", "-s", session_id, "-b", popup_block, "popup topic", as_json=False)
        rex("send-key", "-s", session_id, "-b", popup_block, "enter", as_json=False)
        wait_for(lambda: popup_block not in placed_blocks(session_id))
        view = rex("session", "inspect", session_id, "--json")
        popup_window = next(window for window in view["windows"] if window["label"] == "popup topic")
        assert view["active_window_id"] == popup_window["window_id"], (
            "Closing the topic popup restored focus to the source tab", view
        )
        print("PASS: submitting the repository and topic keeps the worktree tab focused after the popup closes")

        marker = "qzxj"
        for key in marker:
            rex("-C", client_id, "do", "pane.send_key", f"key={key}", as_json=False)

        def received_marker():
            for block_id in (popup_window["focused_block_id"], outside_block):
                text = rex("capture", "-s", session_id, "-b", block_id,
                           "--trim", "--unwrap", as_json=False)
                if marker in text:
                    return block_id
            return None

        receiving_block = wait_for(received_marker)
        rex("-C", client_id, "do", "pane.send_key", "key=ctrl+u", as_json=False)
        assert receiving_block == popup_window["focused_block_id"], (
            "Rex.app kept keyboard input in the source tab instead of selecting the worktree tab",
            receiving_block, popup_window["focused_block_id"],
        )
        print("PASS: Rex.app sends keyboard input to the worktree tab after the popup closes")

        result = subprocess.run(["bash", str(HELPER), session_id, str(fixture.root)],
                                input=f"{fixture.repo}\nsmoke topic\n", env=fixture.env,
                                check=True, capture_output=True, text=True)
        assert "Branch: smoke-topic" in result.stdout, result.stdout
        view = rex("session", "inspect", session_id, "--json")
        assert len(view["windows"]) == 4, view
        window = next(window for window in view["windows"] if window["label"] == "smoke topic")
        assert view["active_window_id"] == window["window_id"], view

        def worktree_ready():
            process = rex("block", "call", "-s", session_id, "-b",
                          window["focused_block_id"], "process")
            cwd = process.get("foreground", {}).get("cwd")
            return cwd and Path(cwd).resolve() == fixture.worktree("smoke-topic").resolve()

        wait_for(worktree_ready)
        print("PASS: helper creates a real worktree and focuses a labelled tab in the same session")

        failed = subprocess.run(
            ["bash", str(HELPER), session_id, str(fixture.repo),
             "client:00000000-0000-0000-0000-000000000000"],
            input="missing client\n", env=fixture.env, capture_output=True, text=True,
        )
        assert failed.returncode == 1, failed.stdout + failed.stderr
        assert "Rex.app could not select it" in failed.stderr, failed.stderr
        assert (fixture.worktree("missing-client") / ".git").is_file()
        assert "result=failure" in fixture.log.read_text()
        print("PASS: a client-selection failure keeps the worktree and reports failure")
    finally:
        try:
            if app_selected and caller.get("session_id") and caller.get("window_id"):
                rex("-C", client_id, "do", "session.select",
                    f"session_id={caller['session_id']}",
                    f"window_id={caller['window_id']}", as_json=False)
        finally:
            if session_id:
                # Only the session this test created, never a user's existing session.
                rex("kill", session_id, as_json=False)
            fixture.doCleanups()
            print("Cleaned up the temporary Rex session and local Git fixtures")


if __name__ == "__main__":
    main()
