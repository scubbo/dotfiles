# PR workflow work notes

## Scope and decisions

Jack requested a skill for PR creation, CI failures, and reviews from Vade and `hacker`.
Ship this skill before the database work.
Defer the database design and interview to a separate assignment after shipping.
Do not choose a database or task schema before that interview.

Jack answered these policy questions on October 14, 2026:

- Explicit invocation authorizes the initial push and tested fix pushes for that PR.
- Store the skill under `opencode/.config/opencode/skills`.
- Poll CI, including the Vade step, until completion.
- Poll for `hacker` reviews for ten minutes after PR creation or each pushed update.
- Use committed work notes because TodoWrite, journal, and Hivemind tools are unavailable.

The permission for future skill invocations does not authorize pushing this skill during its creation.
The starting worktree was clean.
The implementation branch is `wip/pr-workflow-skill`.

## Tasks

- [x] Inspect the repository and ask about permission, placement, and monitoring.
- [x] Read the OpenCode V2 skill guide and installed GitHub CLI help.
- [x] Write instruction-contract tests and observe the expected failure.
- [ ] Write the skill and its GitHub command reference.
- [ ] Run tests and review every requested decision path.
- [ ] Commit the skill locally and present it to Jack for review.
- [ ] Ship the skill after Jack authorizes its push.
- [ ] After shipping, delegate the database interview and design.
- [ ] In that follow-up, define immediate PR persistence and task tracking with Jack.

## Validation limits

The tests inspect the actual skill files and parse their shell examples.
They do not mock GitHub or claim to prove agent behavior on live PRs.
No live PR creation, comment, rerun, or push is required for these tests.
Use a separate authorized PR to evaluate the complete workflow.
The discovery test failed because `SKILL.md` did not exist.
Captured output confirmed one assertion failure and exit code 1.

## Command findings

`gh pr checks` includes optional CI steps unless `--required` is set.
Its documented exit code for pending checks is 8.
`gh run rerun --failed` reruns failed jobs and their dependencies.
GitHub Actions can run against a synthetic merge commit instead of the branch commit.
Find a PR's runs from its check links, not only `gh run list --commit`.
`gh pr create --dry-run` can push changes, so it is not a safe validation command.
Review-comment replies require the top-level comment ID.
GitHub's check-run rerequest endpoint can reject tokens that do not belong to the owning GitHub App.
