"""Local-only integration tests. Git is real; the Rex tab command is recorded."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HELPER = Path(__file__).resolve().parents[1] / "new-worktree-tab.sh"


class WorktreeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="rex worktree tests ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "example repo"
        self.remote = self.root / "origin.git"
        self.wt_root = self.root / "worktrees"
        self.calls = self.root / "rex-calls.jsonl"
        self.log = self.root / "helper.log"
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", REX_TAB_WORKTREE_ROOT=str(self.wt_root),
                        REX_TAB_LOG=str(self.log), REX_TEST_CALLS=str(self.calls))
        self.git("init", "--bare", "--initial-branch=main", str(self.remote))
        self.git("clone", str(self.remote), str(self.repo))
        self.git("config", "user.email", "test@example.invalid", cwd=self.repo)
        self.git("config", "user.name", "Rex Test", cwd=self.repo)
        (self.repo / "file.txt").write_text("initial\n")
        self.git("add", ".", cwd=self.repo)
        self.git("commit", "-m", "initial", cwd=self.repo)
        self.git("push", "-u", "origin", "main", cwd=self.repo)
        self.git("remote", "set-head", "origin", "-a", cwd=self.repo)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        fake_rex = bin_dir / "rex"
        fake_rex.write_text(
            "#!/bin/sh\nexec " + str(Path(os.sys.executable)) + " -c '"
            'import json, os, sys; '
            'f = open(os.environ["REX_TEST_CALLS"], "a"); '
            'f.write(json.dumps(sys.argv[1:]) + "\\n"); f.close(); '
            'print(json.dumps({"window_id": "window:test"})); '
            'sys.exit(int(os.getenv("REX_TEST_FAIL", "0")))'
            "' \"$@\"\n"
        )
        fake_rex.chmod(0o755)
        self.env["PATH"] = str(bin_dir) + os.pathsep + self.env["PATH"]

    def git(self, *args, cwd=None):
        result = subprocess.run(["git", *args], cwd=cwd, env=self.env,
                                text=True, capture_output=True, check=True)
        return result.stdout.strip()

    def run_helper(self, topic, cwd=None, expected=0):
        result = subprocess.run(["bash", str(HELPER), "session:test", str(cwd or self.repo)],
                                input=topic, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def worktree(self, branch):
        return self.wt_root / self.repo.name / branch

    def tab_calls(self):
        if not self.calls.exists():
            return []
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        return [call for call in calls if call[:2] == ["window", "new"]]

    def test_new_topic_creates_branch_and_requests_tab(self):
        self.run_helper("Fix login / redirect\n")
        worktree = self.worktree("Fix-login-redirect")
        self.assertEqual(self.git("branch", "--show-current", cwd=worktree), "Fix-login-redirect")
        self.assertEqual(self.tab_calls(), [["window", "new", "-s", "session:test",
                                            "Fix login / redirect", "-c", str(worktree),
                                            "--focus", "--json"]])
        self.assertIn("result=success", self.log.read_text())

    def test_fetches_latest_default_without_changing_dirty_parent(self):
        seed = self.root / "seed"
        self.git("clone", str(self.remote), str(seed))
        self.git("config", "user.email", "test@example.invalid", cwd=seed)
        self.git("config", "user.name", "Rex Test", cwd=seed)
        (seed / "remote.txt").write_text("new upstream content\n")
        self.git("add", ".", cwd=seed)
        self.git("commit", "-m", "upstream update", cwd=seed)
        self.git("push", cwd=seed)
        self.git("switch", "-c", "parent-topic", cwd=self.repo)
        parent_head = self.git("rev-parse", "HEAD", cwd=self.repo)
        (self.repo / "file.txt").write_text("uncommitted user change\n")
        self.run_helper("fresh\n")
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=self.repo), parent_head)
        self.assertEqual(self.git("branch", "--show-current", cwd=self.repo), "parent-topic")
        self.assertEqual((self.repo / "file.txt").read_text(), "uncommitted user change\n")
        self.assertEqual((self.worktree("fresh") / "remote.txt").read_text(), "new upstream content\n")

    def test_existing_local_branch_keeps_its_history(self):
        self.git("branch", "existing", cwd=self.repo)
        self.run_helper("existing\n")
        self.assertEqual(self.git("branch", "--show-current", cwd=self.worktree("existing")), "existing")

    def test_existing_worktree_reopens_without_fetch(self):
        self.run_helper("existing\n")
        self.git("remote", "set-url", "origin", str(self.root / "missing.git"), cwd=self.repo)
        self.run_helper("existing\n")
        self.assertEqual(len(self.tab_calls()), 2)

    def test_linked_worktree_subdirectory_resolves_main_repo(self):
        self.run_helper("first\n")
        subdir = self.worktree("first") / "subdir"
        subdir.mkdir()
        self.run_helper("second\n", cwd=subdir)
        self.assertTrue((self.worktree("second") / ".git").is_file())

    def test_blank_or_eof_cancels(self):
        for topic in ("\n", ""):
            self.run_helper(topic)
        self.assertFalse(self.tab_calls())
        self.assertIn("result=cancelled", self.log.read_text())

    def test_invalid_topic_fails_without_tab(self):
        for topic in ("!!!\n", "HEAD\n"):
            self.run_helper(topic, expected=1)
        self.assertFalse(self.tab_calls())

    def test_non_repo_prompts_for_repository_path(self):
        self.run_helper(f"{self.repo}\nnew topic\n", cwd=self.root)
        self.assertTrue((self.worktree("new-topic") / ".git").is_file())
        self.assertEqual(len(self.tab_calls()), 1)

    def test_repository_prompt_retries_invalid_paths(self):
        result = self.run_helper(f"missing repo\n{self.repo}\nretry\n", cwd=self.root)
        self.assertIn("Not a Git repository:", result.stderr)
        self.assertTrue((self.worktree("retry") / ".git").is_file())
        self.assertEqual(len(self.tab_calls()), 1)

    def test_repository_prompt_blank_or_eof_cancels(self):
        for input_text in ("\n", "", "missing repo\n"):
            self.run_helper(input_text, cwd=self.root)
        self.assertFalse(self.tab_calls())
        self.assertFalse(self.wt_root.exists())
        self.assertIn("result=cancelled", self.log.read_text())

    def test_repository_prompt_resolves_relative_paths_from_source(self):
        self.run_helper("example repo\nrelative\n", cwd=self.root)
        self.assertTrue((self.worktree("relative") / ".git").is_file())

    def test_repository_prompt_expands_home_prefix(self):
        self.env["HOME"] = str(self.root)
        self.run_helper("~/example repo\nhome-path\n", cwd=self.root)
        self.assertTrue((self.worktree("home-path") / ".git").is_file())

    def test_repository_prompt_does_not_evaluate_shell_input(self):
        marker = self.root / "shell-input-executed"
        self.run_helper(f"$(touch '{marker}')\n\n", cwd=self.root)
        self.assertFalse(marker.exists())
        self.assertFalse(self.tab_calls())

    def test_selected_repository_still_allows_blank_topic_to_cancel(self):
        self.run_helper(f"{self.repo}\n\n", cwd=self.root)
        self.assertFalse(self.tab_calls())
        self.assertFalse(self.wt_root.exists())

    def test_missing_default_branch_fails_without_worktree(self):
        self.git("symbolic-ref", "--delete", "refs/remotes/origin/HEAD", cwd=self.repo)
        result = self.run_helper("topic\n", expected=1)
        self.assertIn("Could not determine origin's default branch", result.stderr)
        self.assertFalse(self.worktree("topic").exists())
        self.assertFalse(self.tab_calls())

    def test_fetch_failure_does_not_create_branch_or_tab(self):
        self.git("remote", "set-url", "origin", str(self.root / "missing.git"), cwd=self.repo)
        result = self.run_helper("topic\n", expected=1)
        self.assertIn("Could not fetch", result.stderr)
        self.assertFalse(self.worktree("topic").exists())
        self.assertFalse(self.tab_calls())

    def test_unrelated_existing_directory_is_rejected(self):
        self.worktree("topic").mkdir(parents=True)
        self.run_helper("topic\n", expected=1)
        self.assertFalse(self.tab_calls())

    def test_branch_checked_out_elsewhere_is_not_forced(self):
        self.git("worktree", "add", "-b", "busy", str(self.root / "elsewhere"), cwd=self.repo)
        self.run_helper("busy\n", expected=1)
        self.assertFalse(self.tab_calls())

    def test_tab_failure_keeps_created_worktree_and_logs_error(self):
        self.env["REX_TEST_FAIL"] = "1"
        result = self.run_helper("topic\n", expected=1)
        self.assertIn("tab could not be opened", result.stderr)
        self.assertTrue((self.worktree("topic") / ".git").is_file())
        self.assertIn("result=failure", self.log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
