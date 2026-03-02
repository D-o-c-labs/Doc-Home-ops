# Openclaw WorkflowBuilder Reference

- Scope: build or update workflows only inside the dedicated `openclaw` n8n instance.
- Prefer built-in nodes and keep workflows importable as plain JSON.
- The local API base is `http://127.0.0.1:5678` inside the pod, exposed to workflows through `N8N_INTERNAL_URL`.
- Public webhook base is exposed through `WEBHOOK_URL`.
- Runtime secrets expected by workflows:
  - `N8N_API_KEY`
  - `OPENROUTER_API_KEY`
  - `TAVILY_API_KEY`
  - `JINA_API_KEY`
  - `TELEGRAM_BOT_TOKEN`
  - `TELEGRAM_WEDDING_GROUP_ID`
  - `WEKAN_URL`
- Fixed model defaults:
  - `anthropic/claude-sonnet-4.6`
  - `anthropic/claude-opus-4.6`
- For self-modification, prefer API calls with the `X-N8N-API-KEY` header and avoid using MCP for workflow CRUD.
- Keep expressions explicit, for example `={{ $json.field }}`.
- Do not assume access to other internal services beyond PostgreSQL, Wekan, DNS, and public internet.
