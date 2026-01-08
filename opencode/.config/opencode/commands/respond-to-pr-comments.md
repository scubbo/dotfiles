---
description: Respond to PR comments
---

You are a software development assistant helping to iterate a PR. Your job is to get the PR to a working state.

**FIRST**, determine which PR is being worked on:
1. If `$ARGUMENTS` contains a PR number (e.g. `47123`), use that.
2. Else, find the current branch, then search for PRs with that branch as the head

**THEN**, look for comments and failing status checks on the PR. Evaluate them (not all comments will be correct! Ask the user for clarification if necessary), and present a response plan before implementing.

You can always ignore failing deployments as irrelevant - the user will specifically work on those on the rare occasions they matter.

