# TODO

## Deployments

- [ ] **webtop** - Containerized Linux desktop environment in browser
  - Location: `kubernetes/apps/selfhosted/webtop/`
  - Source: [linuxserver/docker-webtop](https://github.com/linuxserver/docker-webtop)
  - Homepage: [docs.linuxserver.io/images/docker-webtop](https://docs.linuxserver.io/images/docker-webtop/)
- [ ] **gitea** - Self-hosted Git service with CI/CD
  - Location: `kubernetes/apps/selfhosted/gitea/` (or `kubernetes/apps/development/gitea/`)
  - Source: [go-gitea/gitea](https://github.com/go-gitea/gitea)
  - Homepage: [about.gitea.com](https://about.gitea.com/)
- [ ] **ghostfolio-feeder** - Automated portfolio data sync for Ghostfolio
  - Location: `kubernetes/apps/selfhosted/ghostfolio-feeder/`
  - Source: [marco-ragusa/ghostfolio-feeder](https://github.com/marco-ragusa/ghostfolio-feeder.git)
  - Related: Complements existing ghostfolio deployment
- [ ] **wiki** - Public documentation wiki with MkDocs on GitHub Pages
  - Location: `docs/`, `mkdocs.yml`, `.github/workflows/deploy-mkdocs.yml`
  - Deployment: GitHub Pages via official GitHub actions
  - Canonical URL: `https://docs.d-o-c.cloud`
  - Redirect URL: `https://docs.piscio.net` -> `https://docs.d-o-c.cloud`
  - Notes: Same repo, terminal theme, no Kubernetes wiki service

## Notes

Each deployment should follow the existing repository patterns:

- Create `ks.yaml` kustomization in appropriate namespace
- Use bjw-s app-template helm chart (v4.2.0)
- Add to parent `kustomization.yaml`
- Configure volsync for persistent data
- Set up Gateway API routes for external access
- Use external-secrets/onepassword for sensitive data

## Documentation TODO

- [ ] Expand docs content in `docs/` for Talos, Kubernetes, runbooks, and troubleshooting
- [ ] Keep docs deploy on push to `main` for docs-related changes only
- [ ] Maintain public content posture (no redaction of internal details)
