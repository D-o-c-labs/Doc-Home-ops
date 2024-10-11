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
    CA_CERT=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt | base64 -w 0)
    API_SERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}"

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
KUBECONFIG_BASE64=$(base64 -w 0 < /tmp/kubeconfig)

# Function to create or update GitHub secret
create_or_update_github_secret() {
    # GitHub API endpoints
    PUBLIC_KEY_URL="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/secrets/public-key"
    SECRETS_URL="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/secrets/${GITHUB_SECRET_NAME}"

    # Retrieve the public key for the repository
    PUBLIC_KEY_RESPONSE=$(curl -sSL -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "${PUBLIC_KEY_URL}")

    PUBLIC_KEY=$(echo "${PUBLIC_KEY_RESPONSE}" | jq -r .key)
    KEY_ID=$(echo "${PUBLIC_KEY_RESPONSE}" | jq -r .key_id)

    if [[ "${PUBLIC_KEY}" == "null" || -z "${PUBLIC_KEY}" ]]; then
        echo "Failed to retrieve public key from GitHub."
        echo "Response: ${PUBLIC_KEY_RESPONSE}"
        exit 1
    fi

    # Encrypt the secret using Python and PyNaCl
    ENCRYPTED_VALUE=$(python3 - <<EOF
import base64
from nacl import encoding, public

public_key = base64.b64decode("${PUBLIC_KEY}")
sealed_box = public.SealedBox(public.PublicKey(public_key))
encrypted = sealed_box.encrypt("${KUBECONFIG_BASE64}".encode())
print(base64.b64encode(encrypted).decode())
EOF
)

    if [[ -z "${ENCRYPTED_VALUE}" ]]; then
        echo "Encryption failed."
        exit 1
    fi

    # Prepare the payload
    PAYLOAD=$(jq -n \
        --arg encrypted_value "${ENCRYPTED_VALUE}" \
        --arg key_id "${KEY_ID}" \
        '{ encrypted_value: $encrypted_value, key_id: $key_id }')

    # Create or update the secret
    RESPONSE=$(curl -sSL -X PUT -H "Authorization: token ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "${PAYLOAD}" \
        "${SECRETS_URL}")

    # Check for errors
    MESSAGE=$(echo "${RESPONSE}" | jq -r .message)
    if [[ -n "${MESSAGE}" && "${MESSAGE}" != "null" ]]; then
        echo "GitHub API Error: ${MESSAGE}"
        echo "Full Response: ${RESPONSE}"
        exit 1
    fi

    echo "Secret '${GITHUB_SECRET_NAME}' successfully created/updated."
}

# Create or update the GitHub secret
create_or_update_github_secret
