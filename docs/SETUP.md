# Setup Guide — GitOps CI/CD Pipeline

Complete one-time setup from zero to a fully working pipeline.

---

## Prerequisites

Install these tools before starting:

```bash
# gcloud CLI
curl https://sdk.cloud.google.com | bash && exec -l $SHELL
gcloud init

# kubectl
gcloud components install kubectl

# Helm 3
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/

# ArgoCD CLI
brew install argocd           # macOS
# or
sudo snap install argocd      # Linux

# GitHub CLI
brew install gh               # macOS
# or
sudo apt install gh           # Ubuntu/Debian

gh auth login                 # Authenticate gh CLI
```

---

## Step 1 — Fork & Clone the Repository

```bash
# Fork on GitHub then:
git clone https://github.com/YOUR_ORG/gitops-pipeline.git
cd gitops-pipeline

# Set up branch structure
git checkout -b dev
git push origin dev
# 'main' already exists as default branch
```

---

## Step 2 — Bootstrap GCP Resources

```bash
export GCP_PROJECT_ID="your-gcp-project-id"
export GCP_REGION="us-central1"
export GCP_ZONE="us-central1-a"

./scripts/setup-gcp.sh
```

This script:
- Enables all required GCP APIs (GKE, GCR, Cloud Build, IAM, etc.)
- Creates three GKE clusters: `gitops-dev-cluster`, `gitops-staging-cluster`, `gitops-prod-cluster`
- Creates a `github-actions-cicd` GCP service account with least-privilege roles
- Exports the service account key to `./sa-key-github-actions-cicd.json`
- Creates Kubernetes namespaces: `gitops-dev`, `gitops-staging`, `gitops-prod`

> **Estimated time:** 15–20 minutes (GKE cluster creation)

---

## Step 3 — Install ArgoCD

```bash
export GCP_PROJECT_ID="your-gcp-project-id"
export TARGET_CLUSTER="gitops-dev-cluster"       # Install ArgoCD here
export GITHUB_REPO="https://github.com/YOUR_ORG/gitops-pipeline.git"
export GITHUB_TOKEN="ghp_yourPersonalAccessToken" # repo read scope

./scripts/setup-argocd.sh
```

This script:
- Installs ArgoCD v2.9 into the `argocd` namespace
- Exposes the ArgoCD UI via LoadBalancer (external IP)
- Registers your GitHub repository
- Applies all ArgoCD Application manifests (dev, staging, prod)
- Changes the initial admin password

Save the output — it contains your ArgoCD IP and new password.

---

## Step 4 — Configure GitHub Secrets

```bash
export GITHUB_REPO="YOUR_ORG/gitops-pipeline"
export GCP_PROJECT_ID="your-gcp-project-id"
export SA_KEY_FILE="./sa-key-github-actions-cicd.json"
export STAGING_URL="https://gitops-demo.staging.example.com"
export PROD_URL="https://gitops-demo.example.com"

./scripts/setup-secrets.sh
```

Then **manually** set up the `production` GitHub Environment:

1. Go to `Settings → Environments` in your GitHub repo
2. Create environment named **`production`**
3. Add required reviewers (your release managers)
4. Enable "Prevent self-review"
5. Restrict to branches matching `release/*`

---

## Step 5 — Update Placeholder Values

Replace all `YOUR_GCP_PROJECT_ID` and `YOUR_ORG` placeholders:

```bash
# Replace project ID in all files
find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.sh" \) \
  -exec sed -i 's/YOUR_GCP_PROJECT_ID/your-actual-project-id/g' {} +

# Replace GitHub org
find . -type f \( -name "*.yaml" -o -name "*.yml" \) \
  -exec sed -i 's/YOUR_ORG/your-actual-org/g' {} +

# Update service account email in serviceaccount.yaml
find . -name "serviceaccount.yaml" \
  -exec sed -i 's/YOUR_GCP_PROJECT_ID/your-actual-project-id/g' {} +
```

Commit the changes:

```bash
git add -A
git commit -m "chore: configure project-specific values"
git push origin dev
git push origin main
```

---

## Step 6 — Trigger Your First Pipeline

```bash
# Trigger dev pipeline
git checkout dev
echo "// First deploy $(date)" >> app/src/index.js
git add -A
git commit -m "feat: initial gitops deployment"
git push origin dev
```

Watch it run:
- GitHub Actions: `https://github.com/YOUR_ORG/gitops-pipeline/actions`
- ArgoCD UI: `https://ARGOCD_IP` (login with admin / your password)

---

## Step 7 — Verify Deployments

```bash
# Check dev namespace
kubectl get pods -n gitops-dev
kubectl get svc  -n gitops-dev

# Port-forward to test locally
kubectl port-forward svc/gitops-demo 8080:80 -n gitops-dev

# Hit the app
curl http://localhost:8080/health
curl http://localhost:8080/api/v1/info
```

---

## Step 8 — First Production Release

```bash
# Create a release branch
git checkout main
git pull origin main
git checkout -b release/1.0.0
git push origin release/1.0.0
```

This triggers the prod pipeline. After tests pass, it waits for **manual approval** in GitHub Actions. Go to Actions → approve the deployment → ArgoCD syncs production.

---

## Troubleshooting

**ArgoCD shows "OutOfSync":**
```bash
argocd app sync gitops-demo-dev
```

**Pods crash-looping:**
```bash
kubectl describe pod -l app=gitops-demo -n gitops-dev
kubectl logs -l app=gitops-demo -n gitops-dev --previous
```

**GCR authentication fails in GitHub Actions:**
- Verify `GCP_SA_KEY` secret is the full JSON content (not the filename)
- Check SA has `roles/storage.admin` on the project

**ArgoCD not detecting changes:**
- ArgoCD polls every 3 minutes by default
- Force sync: `argocd app sync gitops-demo-dev`
- Check webhook config: `argocd app get gitops-demo-dev`
