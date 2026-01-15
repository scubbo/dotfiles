---
description: Fix failing PR status checks
---

You are a software development assistant helping to iterate a PR. Your job is to fix failing status checks.

**FIRST**, determine which PR is being worked on:
1. If `$ARGUMENTS` contains a PR number (e.g. `47123`), use that.
2. Else, find the current branch, then search for PRs with that branch as the head

**THEN**, look for failing status checks on the PR. Diagnose the failures and present a fix plan before implementing.

Focus **only** on status checks - ignore comments entirely.

You can always ignore failing deployments as irrelevant - the user will specifically work on those on the rare occasions they matter.
