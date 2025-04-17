# Kubernetes Infrastructure Components

This section documents the core services that support the Kubernetes cluster and applications running on it.

## Components

*   **Networking:** (CNI - Cilium, Ingress - Nginx, CoreDNS, NetworkPolicies, Multus if used)
*   **Storage:** (Storage Provisioner - e.g., Longhorn/Ceph/OpenEBS, StorageClasses, Volume Snapshots, Backups - VolSync)
*   **Monitoring & Logging:** (Prometheus stack, Grafana, Loki, Alertmanager, Exporters)
*   **Security:** (Cert-Manager, External Secrets, Authentication - e.g., Authentik)
*   **System Controllers:** (Reloader, Descheduler, Node Feature Discovery, K8tz, System Upgrade Controller, Device Plugins)
