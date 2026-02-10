# Authoring Guidelines

Use this guide to keep documentation clear, current, and consistent.

## Principles

1. Write for operations first: explain what to do, when, and why.
2. Prefer concrete commands and paths over abstract guidance.
3. Keep docs close to the implementation they describe.
4. Update docs in the same pull request as infrastructure changes.

## Structure conventions

- One topic per page.
- Start with intent and scope.
- Add operational steps in numbered order.
- Include validation steps and rollback notes for risky changes.

## Style conventions

- Use lowercase-kebab-case filenames.
- Use two-space indentation in YAML examples.
- Use fenced code blocks with shell examples when possible.
- Reference repo paths explicitly (for example `kubernetes/apps/selfhosted/n8n/`).

## Change checklist

1. Update relevant page content.
2. Ensure nav in `mkdocs.yml` includes new pages.
3. Verify links and command snippets are still valid.
4. Run local docs validation when tooling is available:

```bash
mkdocs build --clean --strict
```

## Public content policy

This wiki is public and intentionally mirrors repository detail. Internal hostnames, CIDRs, and operational topology may appear in docs where useful for accuracy.
