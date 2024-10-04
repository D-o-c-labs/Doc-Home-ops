#!/bin/bash
set -e

# Variables
SERVICE_ACCOUNT_NAME=flux-reconcile-sa
NAMESPACE=flux-system
KUBECONFIG_SECRET_NAME=flux-kubeconfig

# Function to create kubeconfig
create_kubeconfig() {
    TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    CA_CERT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | base64 | tr -d '\n')
    API_SERVER=https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}

    cat <<EOF > /tmp/kubeconfig
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT}
    server: ${API_SERVER}
    name: flux-cluster
contexts:
- context:
    cluster: flux-cluster
    user: flux-reconcile-sa
    name: flux-reconcile-context
current-context: flux-reconcile-context
users:
- name: flux-reconcile-sa
    user:
    token: ${TOKEN}
EOF
}

# Create kubeconfig
create_kubeconfig

# Create or update the Secret with the kubeconfig
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
    name: ${KUBECONFIG_SECRET_NAME}
    namespace: ${NAMESPACE}
type: Opaque
data:
    kubeconfig: $(base64 /tmp/kubeconfig | tr -d '\n')
EOF
