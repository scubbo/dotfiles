Resolve merge conflicts in all files except `pnpm-lock.yaml`.
Then run `pnpm install` to regenerate `pnpm-lock.yaml`.
Then run typecheck and test (using `turbo`) for all affected packages. If that passes, add `pnpm-lock.yaml` and commit the merge.
