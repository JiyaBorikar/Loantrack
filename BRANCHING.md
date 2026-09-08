# LoanTrack Git Branching Strategy

LoanTrack uses a lightweight feature-branch workflow with `main` and
`develop` as the two long-lived branches.

## Branches

- `main` contains stable, release-ready code. Direct commits to `main` are
  not allowed.
- `develop` is the integration branch where completed features are combined
  and tested before release. Direct commits to `develop` are not allowed.
- `feature/*` branches are created from `develop` for individual pieces of
  work. Each assignment part is developed on its own feature branch.

## Pull Requests

When work on a feature is complete, the feature branch is pushed to GitHub
and merged into `develop` through a Pull Request. Each Pull Request should
have a meaningful description and include review of the changed code before
merging.

Once `develop` contains a tested and deployable release, it can be merged
into `main` through a Pull Request. Release tags are created on the
release-ready commit.

The branch history is intentionally retained rather than squashed so that
the development process remains visible and traceable.

## Why This Model

This workflow separates ongoing integration work from production-ready
code. Feature branches keep individual changes isolated, while Pull Requests
provide a natural point for review and verification. Keeping `main`
deployable also makes it safer to release a known-good version.

For a team of five shipping daily, I would recommend this model with a
small adjustment: keep feature branches short-lived and merge frequently.
For low-risk, continuously deployed work, a simpler trunk-based workflow
could also be considered. However, for a small team that still wants clear
review boundaries and a stable release branch, the LoanTrack model provides
a reasonable balance between control and development speed.