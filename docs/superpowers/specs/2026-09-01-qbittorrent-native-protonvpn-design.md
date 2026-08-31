# qBittorrent Native ProtonVPN Design

## Goal

Make the qBittorrent VPN sidecar resilient to retired or unavailable static Proton VPN servers and expose the real VPN state through Kubernetes health probes.

## Configuration

Gluetun will use its native `protonvpn` provider with WireGuard, select Italian port-forwarding-capable servers, and continue using the existing dynamic qBittorrent port synchronization container.

The Gluetun environment will:

- set `VPN_SERVICE_PROVIDER` to `protonvpn`;
- set `SERVER_COUNTRIES` to `Italy`;
- set `PORT_FORWARD_ONLY` and `VPN_PORT_FORWARDING` to `on`;
- retain the existing DNS, firewall, interface, and control-server settings;
- remove the custom-provider endpoint port and port-forwarding provider override.

The existing `envFrom` reference to `qbittorrent-secret` will remain. The ExternalSecret will export only the Proton WireGuard private key needed by the native provider. Static endpoint IP, server public key, and tunnel address entries will be removed. The qBittorrent cross-seed API key and Gluetun control-server API key remain in the shared Secret.

## Health and Recovery

The restartable Gluetun init container will receive startup, readiness, and liveness exec probes that run `/gluetun-entrypoint healthcheck`.

- The startup probe allows up to 150 seconds for initial connection establishment.
- The readiness probe removes the pod from Ready state shortly after VPN health is lost.
- The liveness probe allows Gluetun's internal recovery loop roughly 60 seconds before Kubernetes restarts the Gluetun container.

The shared network namespace and Gluetun firewall continue to prevent qBittorrent from bypassing the VPN while Gluetun reconnects.

## Validation

Validation will cover:

- YAML linting for the changed manifests;
- Flux-local rendering of the qBittorrent Kustomization;
- inspection of the rendered StatefulSet to confirm native ProtonVPN settings, the absence of static endpoint settings, and all three exec probes;
- inspection of the rendered ExternalSecret to confirm only the required Proton WireGuard private key remains.

No live-cluster mutation is part of the pull request workflow. Flux will apply the merged manifests through the normal reconciliation path.
