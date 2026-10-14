# GitHub commands

These examples support the decisions in `SKILL.md`.
They are separate operations, not a script to execute from top to bottom.
Run write commands only within the explicit permission granted for the selected PR.
If a command fails, read its output before continuing.
Do not use `gh pr create --dry-run` as a safety test.
That command can still push changes.

## Repository and PR

Inspect the local repository before setting command variables:

```sh
git status --short --branch
git remote -v
git branch --show-current
gh auth status
```

Set these values from the inspected repository and the agreed task:

- `repo`: The base repository, in `OWNER/REPO` format.
- `remote`: The remote that accepts pushes to the PR's head repository.
- `branch`: The head branch to push.
- `head_spec`: The branch for same-repository PRs, or `OWNER:BRANCH` for supported fork PRs.
- `base`: The agreed target branch, or the discovered default branch.
- `title` and `body_file`: The PR title and the path to its prepared description.
- `pr`: The PR number from the lookup or creation result.

For another GitHub host, set the correct `GH_HOST` and authentication context before using these examples.
Do not assume that the push remote is also the base repository.
Discover the default branch and find open PR candidates:

```sh
default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
gh pr list --repo "$repo" --state open --head "$branch" \
  --json number,url,headRefName,headRepository,headRepositoryOwner,baseRefName
```

`gh pr list --head` accepts a branch, not `OWNER:BRANCH`.
Compare each candidate's head repository and owner before selecting it.
If more results exist, increase `--limit` or use the paginated API.
If several candidates still match, ask Jack which PR to update.

After tests and diff inspection, push the branch:

```sh
git push --set-upstream "$remote" "HEAD:refs/heads/$branch"
```

Only if no matching PR exists, create one:

```sh
gh pr create --repo "$repo" --base "$base" --head "$head_spec" \
  --title "$title" --body-file "$body_file"
```

The explicit `--head` prevents implicit forking or pushing by `gh pr create`.
Use `--draft` when Jack or repository policy requests a draft.
Organization-owned forks can require a different supported creation method.
If `--head` does not support that fork, ask rather than creating a different PR.
After creation or an update, read the PR metadata:

```sh
gh pr view "$pr" --repo "$repo" \
  --json number,url,state,createdAt,updatedAt,headRefOid,headRefName,headRepository,headRepositoryOwner,baseRefName,statusCheckRollup
```

## CI snapshots and retries

Poll all checks on the selected PR:

```sh
gh pr checks "$pr" --repo "$repo" \
  --json name,state,bucket,link,workflow,startedAt,completedAt
```

Do not add `--required` because that can hide Vade or other optional steps.
The documented pending exit code is 8.
A failing check can also produce a nonzero exit code with usable JSON.
Read the JSON, stderr, and exit code together.
Do not hide authentication or transport errors with `|| true`.
Avoid a blocking `--watch` while the independent `hacker` window is active.

Find `run_id` from the Actions link in the PR's checks.
Make sure that the run belongs to this PR and revision.
Runs for `pull_request` events can use a synthetic merge SHA instead of the branch head SHA.
Do not rely only on `gh run list --commit "$head_sha"`.
For another repository's run, set `run_repo` to its verified `OWNER/REPO`.
For a run in the base repository, set `run_repo` to `repo`.
Read the attempt and failed logs before retrying:

```sh
gh run view "$run_id" --repo "$run_repo" \
  --json databaseId,workflowDatabaseId,attempt,status,conclusion,headSha,event,jobs,url
gh run view "$run_id" --repo "$run_repo" --attempt "$attempt" --log-failed
gh run rerun "$run_id" --repo "$run_repo" --failed
```

Record the original attempt before requesting the retry.
Poll `gh run view` until its attempt increases and the retry finishes.
Do not mistake the original completed attempt for the completed retry.
Read failed logs with the retry's explicit attempt number.
`--failed` also reruns dependencies of failed jobs.
If another actor already requested a retry, inspect that attempt instead of requesting a duplicate.

External checks are not necessarily Actions runs.
Use the provider's documented retry mechanism with the current token's permissions.
GitHub's check-run rerequest endpoint can require the owning GitHub App's token.
If no authorized retry is available, report the blocker without pushing an empty commit.

Compare equivalent default-branch runs:

```sh
gh run list --repo "$repo" --branch "$default_branch" --workflow "$workflow_id" \
  --json databaseId,headSha,event,attempt,status,conclusion,url --limit 30
```

Set `workflow_id` from the failing run's `workflowDatabaseId`, not from a guessed check name.
Read the matching job's logs before calling a failure pre-existing.
If this list lacks equivalent evidence, use an isolated local reproducer as described in `SKILL.md`.
Do not alter the main worktree or launch default-branch workflows without separate permission.

## Review snapshots

Read every page from all three comment surfaces:

```sh
gh api --paginate "repos/$repo/pulls/$pr/comments?per_page=100"
gh api --paginate "repos/$repo/pulls/$pr/reviews?per_page=100"
gh api --paginate "repos/$repo/issues/$pr/comments?per_page=100"
```

Read `user.login`, IDs, bodies, timestamps, links, and commit or location fields where available.
Review objects also contain their submitted time and reviewed commit.
`gh pr view --comments` alone does not include every inline review observation.
Findings can also appear in Vade's logs, summary, or annotations.

For Vade's check output, identify the check's actual commit from the PR's status data.
Set `check_sha` to that commit, including a synthetic merge commit when applicable.
Set `check_repo` to the verified repository that owns the check.
List its checks and select `check_id` using the name and actual App identity:

```sh
gh api --paginate "repos/$check_repo/commits/$check_sha/check-runs?per_page=100"
gh api "repos/$check_repo/check-runs/$check_id"
gh api --paginate "repos/$check_repo/check-runs/$check_id/annotations?per_page=100"
```

Read the check's `output.summary`, `output.text`, `details_url`, and annotations even when its conclusion is successful.
An Actions step can put its review output in the run logs instead.
Do not interpret a completed Vade check as proof that it has no findings.

## Replies and comments

Write each response into `reply_file` using actual newlines.
For an inline finding, set `root_comment_id` to the original top-level review comment's ID.
If the finding is a reply, follow `in_reply_to_id` to the top-level comment.
GitHub does not support replies to replies.
Post into the original thread:

```sh
gh api --method POST "repos/$repo/pulls/$pr/comments/$root_comment_id/replies" \
  -F "body=@$reply_file"
```

For a CI result, review summary, or conversation comment, post a PR comment:

```sh
gh pr comment "$pr" --repo "$repo" --body-file "$reply_file"
```

Link the original observation when a direct thread reply is unavailable.
Do not edit or delete Jack's comments.
Use these templates with actual evidence in place of the angle-bracket fields.
Do not post a template with unfilled fields.

### Flaky result

```text
Automated agent reply (not from Jack).

<Test or step> failed in <original attempt link> and passed on the same commit in <retry attempt link>.
This is a flaky result. The flaky test or step must be fixed.
<Observed evidence, without an unproven root cause.>
```

### Known failure

```text
Automated agent reply (not from Jack).

<Failure> persists after one retry: <PR attempt link>.
The same failure exists on the default branch at <SHA>: <matching run or reproduction evidence>.
This is a known failure, not a defect introduced or worsened by this PR. CI remains failing.
```

### Fixed finding or PR-caused CI failure

```text
Automated agent reply (not from Jack).
Automated agent fix (not from Jack): a bot automatically created commit <SHA/link>.

<Finding or failure> is addressed by <specific change>.
Validation: <regression test and required test results>.
<CI is pending, or its observed result. Do not claim success before it finishes.>
```

### Incorrect finding

```text
Automated agent reply (not from Jack).

Thank you for the review. I am not applying this suggestion because <specific intent or disproving evidence>.
<Concise explanation of the deliberate design or the relevant code/test.>
This response is the agent's assessment, not a personal review or rejection by Jack.
```

## Command sources and validation

Consult the installed CLI's `--help` before changing these commands.
The command reference uses `gh` 2.102.0 and OpenCode V2's directory-based skills.
The instruction-contract tests read the actual documents and parse shell examples without executing them.
They do not prove that an agent follows the skill or that GitHub integrations complete successfully.

Run them from the dotfiles repository root:

```sh
python3 opencode/.config/opencode/skills/pr-workflow/tests/test_skill.py
```

The relevant published references are:

- [OpenCode V2 skills](https://opencode.ai/v2/docs/skills)
- [GitHub CLI PR checks](https://cli.github.com/manual/gh_pr_checks)
- [GitHub CLI run rerun](https://cli.github.com/manual/gh_run_rerun)
- [GitHub review-comment replies](https://docs.github.com/en/rest/pulls/comments#create-a-reply-for-a-review-comment)
- [GitHub check runs](https://docs.github.com/en/rest/checks/runs)
