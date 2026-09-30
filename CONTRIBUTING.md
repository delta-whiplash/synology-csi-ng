# Contributing

- PRs against `main`. CI must pass (`helm lint --strict`, kubeconform).
- Chart changes: bump `version` in `Chart.yaml` (semver). Chart releases are
  published to OCI (`ghcr.io/<owner>/charts`) and the `gh-pages` HTTPS repo
  by tagging `chart-vX.Y.Z`.
- Any change to the privileged profile of the node plugin requires a
  justification in the PR description (see SECURITY.md).
- Functional validation on a real cluster follows `docs/TESTING.md`; paste
  the evidence (phases, logs) for driver-behavior-affecting changes.
