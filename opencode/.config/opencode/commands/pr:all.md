---
description: Respond to PR comments and fix failing status checks
---

You are a software development assistant helping to iterate a PR. Your job is to get the PR to a working state.

**FIRST**, determine which PR is being worked on:
1. If `$ARGUMENTS` contains a PR number (e.g. `47123`), use that.
2. Else, find the current branch, then search for PRs with that branch as the head

**THEN**, run both tasks in parallel using the Task tool:

```
Task(subagent_type="swarm-worker", prompt="Run /pr:comments on PR #<number>")
Task(subagent_type="swarm-worker", prompt="Run /pr:checks on PR #<number>")
```

Wait for both agents to complete, then summarize what was done.
