"""Check that fork_agent_pane copies a live fx conversation into a split pane.

Real fx and real Rex run against a disposable fx profile and Rex session.
Seeding the conversation sends one short model request.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from smoke_rex import CONFIG, REX, rex, wait_for


FX = shutil.which("fx")
ACTION = ("do", str(CONFIG), "--action", "fork_agent_pane")


def main():
    # fx reports every record as corrupt when FX_HOME goes through a symlink,
    # and macOS temporary directories do.
    root = Path(tempfile.mkdtemp(prefix="rex-fork-agent-smoke-")).resolve()
    fx_home = root / "fx-home"
    workspace = root / "workspace"
    workspace.mkdir()
    fx_env = dict(os.environ, FX_HOME=str(fx_home))
    session_id = None

    def fx(*args):
        result = subprocess.run([FX, *args], check=True, text=True, capture_output=True,
                                env=fx_env, cwd=workspace)
        return json.loads(result.stdout)

    def live_conversations():
        return {session["id"] for session in fx("sessions", "--live", "--all", "--json")["sessions"]}

    def history(conversation_id):
        return fx("session", "--id", conversation_id, "--json")["history"]

    def foreground(block_id):
        return rex("block", "call", "-s", session_id, "-b", block_id, "process").get("foreground", {})

    def windows_by_block():
        view = rex("session", "inspect", session_id, "--json")
        return {block["block_id"]: window["window_id"] for window in view["windows"]
                for layer in window["layers"] for block in layer["blocks"]}

    def refused(block_id):
        before = windows_by_block()
        result = subprocess.run([REX, "--autostart=false", *ACTION, "-s", session_id, "-b", block_id],
                                text=True, capture_output=True)
        assert result.returncode != 0, result.stdout
        assert windows_by_block() == before, "A refused fork still changed the layout"
        return result.stderr

    try:
        fx("ask", "--json", "Reply with the single word ready.")
        [source_id] = [session["id"] for session in fx("sessions", "--all", "--json")["sessions"]]

        created = rex("new", "rex-fork-agent-smoke", "-c", str(workspace), "--json", "--shell=none",
                      "--", "env", f"FX_HOME={fx_home}", FX, "--resume", source_id)
        session_id = created["session_id"]
        source_block = created["initial_windows"][0]["block_ids"][0]
        wait_for(lambda: source_id in live_conversations())
        source_pid = foreground(source_block)["pid"]

        forked = rex(*ACTION, "-s", session_id, "-b", source_block, "--json")
        fork_id, fork_block = forked["fx_session_id"], forked["block_id"]
        assert fork_id != source_id, forked
        wait_for(lambda: {source_id, fork_id} <= live_conversations())
        assert foreground(source_block)["pid"] == source_pid, "The source agent was restarted"
        print("PASS: the source agent keeps running and the fork runs as a second live conversation")

        windows = windows_by_block()
        assert windows[fork_block] == windows[source_block], windows
        assert fork_block != source_block, forked
        fork_process = foreground(fork_block)
        assert fork_process["name"] == "fx", fork_process
        assert Path(fork_process["cwd"]).resolve() == workspace, fork_process
        print("PASS: the fork runs in a new pane of the source tab, in the source workspace")

        assert history(source_id), "The seeded conversation has no history"
        assert history(fork_id) == history(source_id)
        print("PASS: the fork starts with the source conversation's history")

        shell = rex("window", "new", "-s", session_id, "not-an-agent", "-c", str(workspace), "--json",
                    "--shell=none", "--", "/bin/bash", "--noprofile", "--norc")
        shell_block = shell["block_ids"][0]
        wait_for(lambda: foreground(shell_block).get("name") == "bash")
        assert "is running bash, not fx" in (error := refused(shell_block)), error
        print("PASS: a pane that is not running fx is refused without opening a pane")

        unsaved = rex("window", "new", "-s", session_id, "unsaved", "-c", str(workspace), "--json",
                      "--shell=none", "--", "env", f"FX_HOME={fx_home}", FX)
        unsaved_block = unsaved["block_ids"][0]
        wait_for(lambda: foreground(unsaved_block).get("name") == "fx")
        assert "has no saved conversation" in (error := refused(unsaved_block)), error
        print("PASS: an fx that has not saved a conversation is refused without opening a pane")
    finally:
        try:
            if session_id:
                # Only the session this test created, never a user's existing session.
                rex("kill", session_id, as_json=False)
        finally:
            shutil.rmtree(root)
            print("Cleaned up the temporary Rex session and fx profile")


if __name__ == "__main__":
    main()
