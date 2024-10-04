---
# md-language-server: https://frontmatter.codes/docs/markdown
---
# CREATE SERVICE ACCOUNT TO MANAGE AUTOMATIC RECONCILIATION

Yes, you can—and it's often recommended—to use a **Service Account** instead of a Kubernetes user for automating tasks like running `flux reconcile` in your GitHub pipeline. Service Accounts are designed for such automation and provide a more secure and manageable way to authenticate and authorize applications interacting with your Kubernetes cluster.

**Here's how you can set this up:**

1. **Create a Service Account**
2. **Define RBAC Permissions (Role and RoleBinding)**
3. **Obtain the Service Account’s Token**
4. **Create a `kubeconfig` File Using the Service Account**
5. **Integrate the `kubeconfig` into Your GitHub Pipeline**

Let's walk through each of these steps in detail.

---

### **1. Create a Service Account**

First, create a dedicated Service Account (e.g., `flux-reconcile-sa`) in the namespace where Flux is installed (commonly `flux-system`).

```yaml
# flux-reconcile-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flux-reconcile-sa
  namespace: flux-system
```

**Apply the Service Account:**

```bash
kubectl apply -f flux-reconcile-serviceaccount.yaml
```

---

### **2. Define RBAC Permissions (Role and RoleBinding)**

Next, define the permissions that this Service Account will have. This involves creating a `Role` with the necessary permissions and a `RoleBinding` to associate the Role with the Service Account.

**a. Role YAML**

```yaml
# flux-reconcile-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: flux-reconcile-role
  namespace: flux-system  # Ensure this matches the Service Account's namespace
rules:
  - apiGroups:
      - kustomize.toolkit.fluxcd.io
    resources:
      - kustomizations
    verbs:
      - get
      - patch
```

**b. RoleBinding YAML**

```yaml
# flux-reconcile-rolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: flux-reconcile-binding
  namespace: flux-system  # Must match the Role's namespace
subjects:
  - kind: ServiceAccount
    name: flux-reconcile-sa  # The Service Account name
    namespace: flux-system
roleRef:
  kind: Role
  name: flux-reconcile-role
  apiGroup: rbac.authorization.k8s.io
```

**Apply the RBAC Configuration:**

```bash
kubectl apply -f flux-reconcile-role.yaml
kubectl apply -f flux-reconcile-rolebinding.yaml
```

---

### **3. Obtain the Service Account’s Token**

Depending on your Kubernetes version, the method to retrieve the Service Account token may vary.

#### **For Kubernetes v1.24 and Newer:**

Kubernetes v1.24+ uses the **TokenRequest API** to issue tokens. You can retrieve a token using `kubectl`:

```bash
# Generate a token for the Service Account
TOKEN=$(kubectl create token flux-reconcile-sa -n flux-system)
```

**Note:** If `kubectl create token` is not available, you may need to upgrade `kubectl` or use an alternative method.

#### **For Kubernetes Versions Prior to v1.24:**

Service Account tokens are automatically created as secrets.

1. **Create a Secret for the Service Account (if not already present):**

    ```yaml
    # flux-reconcile-sa-secret.yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: flux-reconcile-sa-token
      namespace: flux-system
      annotations:
        kubernetes.io/service-account.name: flux-reconcile-sa
    type: kubernetes.io/service-account-token
    ```

    **Apply the Secret:**

    ```bash
    kubectl apply -f flux-reconcile-sa-secret.yaml
    ```

2. **Retrieve the Token:**

    ```bash
    SECRET_NAME=$(kubectl get serviceaccount flux-reconcile-sa -n flux-system -o jsonpath='{.secrets[0].name}')
    TOKEN=$(kubectl get secret $SECRET_NAME -n flux-system -o jsonpath='{.data.token}' | base64 --decode)
    ```

---

### **4. Create a `kubeconfig` File Using the Service Account**

To authenticate with Kubernetes using the Service Account, you'll need to create a `kubeconfig` file that references the Service Account's token and the cluster's CA certificate.

**a. Retrieve the Cluster CA Certificate**

```bash
# Option 1: Retrieve from the Service Account Secret
if [[ -n "$SECRET_NAME" ]]; then
  kubectl get secret $SECRET_NAME -n flux-system -o jsonpath='{.data.ca\.crt}' > ca.crt
else
  # Option 2: Retrieve from the current kubeconfig
  kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 --decode > ca.crt
fi
```

**b. Get the Kubernetes API Server URL**

```bash
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
```

**c. Create the `kubeconfig` File**

You can create the `kubeconfig` manually or use `kubectl` commands to set it up.

**Manual Creation:**

Create a template `kubeconfig` file:

```yaml
# flux-reconcile-kubeconfig.yaml.template
apiVersion: v1
kind: Config
clusters:
  - cluster:
      certificate-authority-data: {{CA_CERT_BASE64}}
      server: {{CLUSTER_SERVER}}
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
      token: {{SERVICE_ACCOUNT_TOKEN}}
```

**Replace Placeholders:**

```bash
# Encode CA certificate in base64
CA_CERT_BASE64=$(cat ca.crt | base64 | tr -d '\n')

# Insert the token and server details
sed -e "s|{{CA_CERT_BASE64}}|$CA_CERT_BASE64|g" \
    -e "s|{{CLUSTER_SERVER}}|$CLUSTER_SERVER|g" \
    -e "s|{{SERVICE_ACCOUNT_TOKEN}}|$TOKEN|g" \
    flux-reconcile-kubeconfig.yaml.template > flux-reconcile-kubeconfig.yaml
```

**Alternatively, Using `kubectl`:**

```bash
# Define variables
KUBECONFIG_FILE=flux-reconcile-kubeconfig.yaml
CLUSTER_NAME=flux-cluster
CONTEXT_NAME=flux-reconcile-context
USER_NAME=flux-reconcile-sa

# Set cluster details
kubectl config set-cluster $CLUSTER_NAME \
  --certificate-authority=ca.crt \
  --embed-certs=true \
  --server=$CLUSTER_SERVER \
  --kubeconfig=$KUBECONFIG_FILE

# Set user credentials
kubectl config set-credentials $USER_NAME \
  --token=$TOKEN \
  --kubeconfig=$KUBECONFIG_FILE

# Set context
kubectl config set-context $CONTEXT_NAME \
  --cluster=$CLUSTER_NAME \
  --user=$USER_NAME \
  --kubeconfig=$KUBECONFIG_FILE

# Set current context
kubectl config use-context $CONTEXT_NAME --kubeconfig=$KUBECONFIG_FILE
```

---

### **5. Integrate the `kubeconfig` into Your GitHub Pipeline**

Store the generated `kubeconfig` securely in GitHub Secrets and use it in your GitHub Actions workflow.

**a. Encode the `kubeconfig` for Storage**

```bash
BASE64_KUBECONFIG=$(cat flux-reconcile-kubeconfig.yaml | base64 | tr -d '\n')
```

**b. Add the `kubeconfig` as a GitHub Secret**

1. Navigate to your GitHub repository.
2. Go to **Settings** > **Secrets and variables** > **Actions**.
3. Click on **New repository secret**.
4. Name the secret, e.g., `FLUX_KUBECONFIG`.
5. Paste the `BASE64_KUBECONFIG` value.
6. Save the secret.

**c. Update Your GitHub Actions Workflow**

Modify your GitHub Actions workflow to decode the `kubeconfig` and use it in the `flux reconcile` step.

```yaml
jobs:
  reconcile:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        cluster: your-cluster-name  # Adjust as needed
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Kubeconfig
        id: kubeconfig
        run: |
          echo "${{ secrets.FLUX_KUBECONFIG }}" | base64 --decode > /tmp/flux-kubeconfig.yaml
          echo "filePath=/tmp/flux-kubeconfig.yaml" >> $GITHUB_OUTPUT

      - name: Install Flux CLI
        run: |
          curl -s https://fluxcd.io/install.sh | sudo bash

      - name: Sync Kustomization
        env:
          KUBECONFIG: "${{ steps.kubeconfig.outputs.filePath }}"
        run: |
          flux \
            --context "flux-reconcile-context@flux-cluster" \
            --namespace flux-system \
            reconcile kustomization cluster \
            --with-source
```

**Explanation of the Workflow Steps:**

1. **Checkout code:** Retrieves your repository's code.
2. **Set up Kubeconfig:**
   - Decodes the base64-encoded `kubeconfig` from GitHub Secrets.
   - Writes it to a temporary file (e.g., `/tmp/flux-kubeconfig.yaml`).
   - Sets an output variable `filePath` pointing to the `kubeconfig` file.
3. **Install Flux CLI:** Installs the `flux` command-line tool.
4. **Sync Kustomization:**
   - Uses the `KUBECONFIG` environment variable to specify the `kubeconfig` file.
   - Runs the `flux reconcile` command to synchronize the kustomization.

**Important Considerations:**

- **Context Name:** Ensure that the `--context` parameter in the `flux` command matches the context name defined in your `kubeconfig`. In this example, it's `flux-reconcile-context@flux-cluster`.
  
- **Security:**
  - **Least Privilege:** The Service Account is granted only the permissions necessary to run `flux reconcile`. Avoid granting broader permissions.
  - **Protect Secrets:** Ensure that the `kubeconfig` stored in GitHub Secrets is kept secure and is only accessible to trusted workflows.
  - **Rotate Credentials:** Periodically rotate the Service Account tokens and update the GitHub Secrets accordingly to maintain security.

- **Automate Token Refresh (if applicable):** For Kubernetes versions supporting bound tokens with expiration, consider implementing a mechanism to refresh the tokens and update the `kubeconfig` accordingly. Tools like **Cert-Manager** can help automate certificate and token management.

---

### **Summary**

By using a **Service Account** coupled with a tailored **kubeconfig**, you can securely and efficiently run `flux reconcile` operations from your GitHub pipeline. This approach leverages Kubernetes-native authentication mechanisms and adheres to best practices by ensuring that the automated tasks have precisely the permissions they need—no more, no less.

**Benefits of Using a Service Account:**

- **Security:** Reduces the risk associated with using personal user credentials in automation.
- **Manageability:** Simplifies permission management through Kubernetes RBAC.
- **Scalability:** Easily extendable to multiple environments or clusters by creating corresponding Service Accounts and `kubeconfigs`.

Implementing this setup aligns with the principle of **least privilege**, ensuring that automated processes have just enough access to perform their tasks without exposing your cluster to unnecessary risks.

---

**References:**

- [Kubernetes Service Accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [FluxCD Documentation](https://fluxcd.io/docs/)
- [GitHub Actions Secrets](https://docs.github.com/en/actions/security-guides/encrypted-secrets)

If you have any further questions or need clarification on any of the steps, feel free to ask!
