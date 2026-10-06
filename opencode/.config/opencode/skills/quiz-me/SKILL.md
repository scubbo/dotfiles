---
name: Quiz Me
description: Given a GitHub Pull Request, generate questions on the PR to ensure the user understands the content.
---

## Workflow

1. Read the PR as provided in the argument. It could be in the format `<owner>/<repo>#<number>`, or full URL `https://github.com/<owner>/<repo>/pull/<number>`.
2. Use the `simple-english` skill in strict mode to generate 3-5 questions that test understanding of the PR context, motivation, effect, and scope. Focus on:
  * What are the roles or responsibilities of (functions/types/classes/files) being introduced/changed? What are some core concepts at play in the PR?
  * What undesirable behaviour is being fixed, or what feature is being added? How will this affect users?
  * What are edge cases to be aware of? Why were particular choices made?
  * How might this go wrong or have unexpected consequences?
3. Present those questions to the user (multiple-choice or freeform answers are both acceptable, as appropriate).
4. Evaluate their answers and rank the user's understanding.
