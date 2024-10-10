#!/bin/bash
set -e

# Variables
SERVICE_ACCOUNT_NAME=flux-reconcile-sa
NAMESPACE=dev
GITHUB_REPO_OWNER=D-o-c-labs
GITHUB_REPO_NAME=Doc-Home-ops
GITHUB_SECRET_NAME=KUBECONFIG

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
  name: doc-home-cluster
contexts:
- context:
    cluster: doc-home-cluster
    user: flux-reconcile-sa
  name: flux@doc-home-cluster
current-context: flux-reconcile-context
users:
- name: flux-reconcile-sa
  user:
    token: ${TOKEN}
EOF
}

# Create kubeconfig
create_kubeconfig

# Encode kubeconfig in base64
KUBECONFIG_BASE64=$(base64 /tmp/kubeconfig | tr -d '\n')

# Create or update GitHub secret
create_or_update_github_secret() {
    # GitHub API endpoint
    API_URL="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/secrets/${GITHUB_SECRET_NAME}"

    # Get public key for secret encryption
    PUBLIC_KEY_INFO=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
        "https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/secrets/public-key")
    
    PUBLIC_KEY=$(echo $PUBLIC_KEY_INFO | jq -r .key)
    KEY_ID=$(echo $PUBLIC_KEY_INFO | jq -r .key_id)

    # Encrypt the secret value
    ENCRYPTED_VALUE=$(echo -n "$KUBECONFIG_BASE64" | openssl base64 -A | openssl enc -aes-256-cbc -md sha256 -pass pass:"$PUBLIC_KEY" | openssl base64 -A)

    # Create or update the secret
    curl -X PUT -sS -H "Authorization: token ${GITHUB_TOKEN}" \
         -H "Accept: application/vnd.github.v3+json" \
         -d "{\"encrypted_value\":\"${ENCRYPTED_VALUE}\", \"key_id\":\"${KEY_ID}\"}" \
         "${API_URL}"
}

# Call the function to create or update the GitHub secret
create_or_update_github_secret
