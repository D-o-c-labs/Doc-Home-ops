<!-- Generated: 2026-11-03 | Files scanned: 72 ks.yaml + namespace kustomizations | Token estimate: ~950 -->

# Application Stacks

72 stack directories under `kubernetes/apps/<ns>/<app>/` (68 registered, 4 commented out). Chart is bjw-s app-template unless noted.

## Stacks by namespace

| Namespace             | Stacks                                                                                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| actions-runner-system | actions-runner-controller (gha-runner-scale-set charts)                                                                                                      |
| authentik             | authentik (upstream chart, SSO)                                                                                                                              |
| cert-manager          | cert-manager, cert-manager-issuers                                                                                                                           |
| database              | crunchy-postgres-operator (operator, cluster, secretstore, userinit-controller, pgadmin), emqx (operator + cluster)                                          |
| downloads             | autobrr, bazarr, cross-seed, flaresolverr, jellyseerr, maintainerr, notifiarr, prowlarr, qbittorrent, radarr, sabnzbd, sonarr, tqm, unpackerr                |
| external-secrets      | external-secrets (+ onepassword-store), onepassword-connect                                                                                                  |
| flux-system           | flux-operator, flux-instance                                                                                                                                 |
| home-automation       | esphome, home-assistant, openwakeword, piper, speech-to-phrase, whisper, zigbee2mqtt                                                                         |
| kube-system           | cilium (+ config, netpols), coredns, metrics-server                                                                                                          |
| media                 | jellyfin, jellyplex-watched, plex (+ trakt-sync, auto-languages, image-cleanup, kometa), tautulli                                                            |
| network               | cloudflared, envoy-gateway (+ config), external-dns (cloudflare, internal), multus (+ networks)                                                              |
| observability         | blackbox-exporter, fluent-bit, grafana, kromgo, kube-prometheus-stack, kube-state-metrics, node-exporter, silence-operator, smartctl-exporter, victoria-logs |
| openebs               | openebs                                                                                                                                                      |
| rook-ceph             | rook-ceph (operator, ceph-csi-drivers, cluster)                                                                                                              |
| selfhosted            | actual-budget (+ actual-ai, actual-api), ghostfolio (+ redis), mealie, metamcp, n8n, splitpro                                                                |
| system                | descheduler, generic-device-plugin, intel-device-plugins (operator, gpu), node-feature-discovery, reloader, spegel, volsync                                  |
| system-controllers    | k8tz, snapshot-controller                                                                                                                                    |
| system-upgrade        | tuppr (+ upgrades)                                                                                                                                           |

## Not running

- Commented out in `selfhosted/kustomization.yaml`: fork-democracy, hermes, mcpjungle, openclaw.
- `replicas: 0` while the Synology NAS is down: downloads/{bazarr, cross-seed, qbittorrent, sabnzbd, unpackerr}.
- `replicas: 0`: home-automation/{openwakeword, piper, speech-to-phrase, whisper}.
- tqm: CronJobs `suspend: true`.

## dependsOn graph (Flux Kustomizations)

```text
onepassword-connect → onepassword-store ─┬→ almost every stack with an ExternalSecret
external-secrets ───┘                    │
volsync@system ──────────────────────────┴→ every stack using components/volsync
openebs → crunchy-postgres-operator → crunchy-postgres-operator-cluster
          → n8n, metamcp, (mcpjungle, hermes)       [cluster]
          → mealie, splitpro                         [operator only]
emqx-operator → emqx-cluster → zigbee2mqtt
multus → multus-networks → esphome, home-assistant
rook-ceph → ceph-csi-drivers → rook-ceph-cluster → piper, whisper, speech-to-phrase
cert-manager → cert-manager-issuers → envoy-gateway-config
cert-manager → k8tz
envoy-gateway → envoy-gateway-config
victoria-logs + kube-prometheus-stack → fluent-bit, grafana
kube-prometheus-stack → smartctl-exporter
silence-operator → silence-operator-silences
node-feature-discovery → node-feature-discovery-rules
tuppr → tuppr-upgrades
actual-budget → actual-ai, actual-api
```

## Exposure

- `envoy-external` (public via Cloudflare tunnel): jellyseerr, notifiarr, prowlarr, radarr, sonarr, jellyfin, plex, tautulli, actual-budget, ghostfolio, mealie, metamcp, n8n, splitpro, home-assistant.
- `envoy-internal` (LAN only): autobrr, bazarr, maintainerr, qbittorrent, sabnzbd, esphome, home-assistant, zigbee2mqtt, blackbox-exporter, grafana, kromgo, n8n.
- n8n and home-assistant attach routes to both gateways.

## Key files

- `kubernetes/apps/<ns>/kustomization.yaml`: stack registry for the namespace.
- `kubernetes/apps/selfhosted/n8n/`: reference layout.
- `kubernetes/apps/downloads/{radarr,sonarr}/app/scripts/`: custom import/reconcile scripts (ConfigMap via kustomize).
