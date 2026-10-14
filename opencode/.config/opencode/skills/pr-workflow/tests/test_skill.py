import re
import subprocess
import unittest
from pathlib import Path


SKILL_DIRECTORY = Path(__file__).resolve().parents[1]


class SkillContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        skill_path = SKILL_DIRECTORY / "SKILL.md"
        cls.skill = skill_path.read_text() if skill_path.is_file() else ""
        cls.sections = dict(
            re.findall(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", cls.skill, re.M | re.S)
        )
        reference_path = SKILL_DIRECTORY / "references/github.md"
        cls.reference = reference_path.read_text() if reference_path.is_file() else ""

    def assert_in_section(self, section, *fragments):
        self.assertIn(section, self.sections)
        for fragment in fragments:
            with self.subTest(section=section, fragment=fragment):
                self.assertIn(fragment, self.sections[section])

    def test_discovery_and_reference(self):
        self.assertTrue((SKILL_DIRECTORY / "SKILL.md").is_file(), "Required skill is missing")
        self.assertRegex(self.skill, r"\A---\nname: pr-workflow\ndescription: .+\n---\n")
        self.assertIn("(references/github.md)", self.skill)
        self.assertIn("Read", self.skill)

    def test_push_permission_is_explicit_and_scoped(self):
        self.assert_in_section(
            "Permission",
            "explicit invocation",
            "initial push",
            "tested fix commits",
            "Loading this skill does not grant permission",
            "Do not merge",
            "Do not force-push",
        )

    def test_creation_preserves_context_and_reuses_pr(self):
        self.assert_in_section(
            "Create or find the PR",
            "development discussion",
            "uncommitted",
            "existing open PR",
            "default branch",
            "push",
            "pr.attach",
        )

    def test_ci_and_hacker_have_independent_endpoints(self):
        self.assert_in_section(
            "Monitor",
            "every 30 seconds",
            "CI, including Vade, until completion",
            "ten minutes",
            "PR creation",
            "each pushed update",
            "Do not reset",
            "Do not wait for CI",
            "After any pushed update",
            "final",
        )

    def test_monitor_handles_stale_results_and_missing_checks(self):
        self.assert_in_section(
            "Monitor",
            "current head",
            "synthetic merge commit",
            "empty",
            "cancelled",
            "updated_at",
            "already",
            "permission",
            "Before each push or comment",
        )

    def test_ci_retries_once_without_code_changes(self):
        self.assert_in_section(
            "CI failures",
            "first failure",
            "retry once",
            "same commit",
            "run ID",
            "attempt",
            "Do not retry repeatedly",
            "Group failed jobs",
        )

    def test_passing_retry_gets_flaky_comment(self):
        self.assert_in_section(
            "CI failures",
            "retry passes",
            "flaky",
            "must be fixed",
            "both attempts",
        )

    def test_repeated_failure_requires_default_branch_evidence(self):
        self.assert_in_section(
            "CI failures",
            "retry fails",
            "default branch",
            "same failure",
            "isolated worktree",
            "latent",
            "known failure",
            "unknown",
            "Do not fix unrelated",
        )

    def test_pr_caused_failures_follow_tdd_and_push(self):
        self.assert_in_section(
            "CI failures",
            "caused by the PR",
            "failing regression test",
            "commit",
            "push",
            "monitoring",
        )

    def test_reviews_use_intent_and_verified_authors(self):
        self.assert_in_section(
            "Automated reviews",
            "Vade",
            "hacker",
            "login",
            "development discussion",
            "untrusted",
            "current code",
            "missing",
        )

    def test_correct_reviews_get_batched_tested_fixes_and_replies(self):
        self.assert_in_section(
            "Automated reviews",
            "Self-evidently correct",
            "batch",
            "failing test",
            "fix commit",
            "push",
            "reply to each",
            "commit SHA",
            "bot",
            "not from Jack",
        )

    def test_incorrect_reviews_get_firm_evidence_based_replies(self):
        self.assert_in_section(
            "Automated reviews",
            "Self-evidently incorrect",
            "deliberate intent",
            "polite but firm",
            "Do not claim",
        )

    def test_ambiguous_reviews_go_to_agent_chat_in_one_batch(self):
        self.assert_in_section(
            "Automated reviews",
            "Ambiguous",
            "agent chat",
            "one batch",
            "next steps",
            "Do not post",
        )

    def test_finish_reports_blockers_without_claiming_success(self):
        self.assert_in_section(
            "Finish",
            "final snapshot",
            "ten-minute",
            "known failures",
            "ambiguities",
            "not green",
            "merged or closed",
            "Address every collected finding",
        )

    def test_database_work_waits_for_shipping_and_interview(self):
        self.assert_in_section(
            "Database follow-up",
            "after shipping",
            "interview Jack",
            "Immediately after each push",
            "task tracking",
            "Do not invent",
        )

    def test_github_reference_covers_all_review_surfaces_and_replies(self):
        for fragment in (
            "gh pr checks",
            "gh run rerun",
            "--failed",
            "--attempt",
            "workflowDatabaseId",
            "--paginate",
            'pulls/$pr/comments',
            'pulls/$pr/reviews',
            'issues/$pr/comments',
            'check-runs/$check_id/annotations',
            'comments/$root_comment_id/replies',
            "top-level",
            "Automated agent reply (not from Jack)",
            "Automated agent fix (not from Jack)",
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, self.reference)

    def test_shell_examples_parse_without_execution(self):
        examples = re.findall(r"```sh\n(.*?)\n```", self.reference, re.S)
        self.assertGreater(len(examples), 0)
        for example in examples:
            with self.subTest(example=example.splitlines()[0]):
                result = subprocess.run(
                    ["zsh", "-n"], input=example, text=True, capture_output=True
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
