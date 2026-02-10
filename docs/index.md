# Doc Home Ops Wiki

This wiki is the public reference for the `doc-home-ops` homelab platform. It documents a Talos-based Kubernetes cluster managed through GitOps with Flux.

## What this site covers

- Talos lifecycle and node configuration patterns.
- Kubernetes architecture, app domains, and infrastructure controllers.
- Operational runbooks for rollout, rollback, backup, restore, and incident response.
- Troubleshooting guides for common Flux, Helm, and network issues.

## Operating model

- Git is the source of truth.
- Documentation lives in `docs/` in the same repository as infrastructure.
- Every documentation update is versioned and reviewed like code.
- The site is built with MkDocs and published by GitHub Pages.

## Publication details

- Canonical URL: `https://docs.d-o-c.cloud`
- Redirect URL: `https://docs.piscio.net` -> canonical URL
- Deployment trigger: push to `main` when docs-related files change

## Fast links

- [Talos overview](talos/index.md)
- [Kubernetes overview](kubernetes/index.md)
- [Kubernetes applications](kubernetes/apps/index.md)
- [Kubernetes infrastructure](kubernetes/infrastructure/index.md)
- [Runbooks](runbooks/flux-reconciliation.md)
- [Troubleshooting](troubleshooting/flux-drift.md)
