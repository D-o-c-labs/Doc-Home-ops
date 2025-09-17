# TODO

## Deployments

- [ ] **webtop** - Containerized Linux desktop environment in browser
  - Location: `kubernetes/apps/selfhosted/webtop/`
  - Source: https://github.com/linuxserver/docker-webtop
  - Homepage: https://docs.linuxserver.io/images/docker-webtop/
- [ ] **gitea** - Self-hosted Git service with CI/CD
  - Location: `kubernetes/apps/selfhosted/gitea/` (or `kubernetes/apps/development/gitea/`)
  - Source: https://github.com/go-gitea/gitea
  - Homepage: https://about.gitea.com/
- [ ] **ghostfolio-feeder** - Automated portfolio data sync for Ghostfolio
  - Location: `kubernetes/apps/selfhosted/ghostfolio-feeder/`
  - Source: https://github.com/marco-ragusa/ghostfolio-feeder.git
  - Related: Complements existing ghostfolio deployment
- [ ] **wiki** - Knowledge base and documentation platform
  - Location: `kubernetes/apps/selfhosted/wiki/`
  - Options: Wiki.js (https://js.wiki/), DokuWiki, BookStack, or MediaWiki
  - Recommend Wiki.js for modern features and Git integration

## Notes

Each deployment should follow the existing repository patterns:

- Create `ks.yaml` kustomization in appropriate namespace
- Use bjw-s app-template helm chart (v4.2.0)
- Add to parent `kustomization.yaml`
- Configure volsync for persistent data
- Set up Gateway API routes for external access
- Use external-secrets/onepassword for sensitive data