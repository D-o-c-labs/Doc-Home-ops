# Kubernetes Cluster Overview

This section details the Kubernetes cluster configuration, primarily managed via GitOps using Flux.

## Core Concepts

*   **GitOps with Flux:** Explain the repository structure, Flux components (Source Controller, Kustomize Controller, Helm Controller), and the reconciliation loop.
*   **Repository Structure:** Describe the layout of the `kubernetes/` directory (e.g., `apps`, `infrastructure`, `flux`).
*   **Secrets Management:** Detail the approach (e.g., SOPS, External Secrets).
*   **Bootstrapping:** How the cluster is initially bootstrapped with Flux.
