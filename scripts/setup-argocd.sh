#!/usr/bin/env bash
# scripts/setup-argocd.sh
# ─────────────────────────────────────────────────────────────────────────────
# Installs ArgoCD on a target GKE cluster, configures repository access,
# sets up notifications, and registers all three Application manifests.
#
# Usage:
#   export GCP_PROJECT_ID=my-project-id
#   export TARGET_CLUSTER=gitops-dev-cluster   # cluster to install ArgoCD on
#   export GITHUB_REPO=https://github.com/YOUR_ORG/gitops-pipeline.git
#   export GITHUB_TOKEN=ghp_xxxx               # PAT with repo read access
#   ./scripts/setup-argocd.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
ZONE="${GCP_ZONE:-us-central1-a}"
TARGET_CLUSTER="${TARGET_CLUSTER:-gitops-dev-cluster}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO (full https URL)}"
GITHUB_TOKEN="${GITHUB_TOKEN:?Set GITHUB_TOKEN (PAT with repo read)}"
ARGOCD_VERSION="v2.9.3"
ARGOCD_NAMESPACE="argocd"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${GREEN}━━━ $* ━━━${NC}"; }

# ── 1. Connect to target cluster ──────────────────────────────────────────────
section "Connecting to cluster: ${TARGET_CLUSTER}"
gcloud container clusters get-credentials "${TARGET_CLUSTER}" \
  --zone="${ZONE}" --project="${PROJECT_ID}" --quiet
info "kubectl context set to: $(kubectl config current-context)"

# ── 2. Install ArgoCD ─────────────────────────────────────────────────────────
section "Installing ArgoCD ${ARGOCD_VERSION}"
kubectl create namespace "${ARGOCD_NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply \
  -n "${ARGOCD_NAMESPACE}" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

info "Waiting for ArgoCD pods to be ready..."
kubectl rollout status deployment/argocd-server \
  -n "${ARGOCD_NAMESPACE}" --timeout=300s
info "ArgoCD installed and running."

# ── 3. Patch ArgoCD server to LoadBalancer (for initial setup) ────────────────
section "Exposing ArgoCD UI"
kubectl patch svc argocd-server \
  -n "${ARGOCD_NAMESPACE}" \
  -p '{"spec": {"type": "LoadBalancer"}}'

info "Waiting for external IP..."
for i in $(seq 1 20); do
  ARGOCD_IP=$(kubectl get svc argocd-server \
    -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "${ARGOCD_IP}" ]; then
    info "ArgoCD UI available at: https://${ARGOCD_IP}"
    break
  fi
  echo "  Attempt ${i}/20 — waiting 10s..."
  sleep 10
done

# ── 4. Get initial admin password ─────────────────────────────────────────────
section "Retrieving admin credentials"
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" \
  get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
info "ArgoCD admin password retrieved."
warn "⚠️  Change this password immediately after first login!"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"

# ── 5. Login with ArgoCD CLI ──────────────────────────────────────────────────
section "Logging in with ArgoCD CLI"
if ! command -v argocd &>/dev/null; then
  warn "argocd CLI not found — installing..."
  curl -sSL -o /usr/local/bin/argocd \
    "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
  chmod +x /usr/local/bin/argocd
fi

argocd login "${ARGOCD_IP}" \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure
info "Logged in to ArgoCD at ${ARGOCD_IP}"

# ── 6. Register GitHub repository ────────────────────────────────────────────
section "Registering GitHub repository"
argocd repo add "${GITHUB_REPO}" \
  --username "git" \
  --password "${GITHUB_TOKEN}" \
  --name "gitops-pipeline"
info "Repository registered: ${GITHUB_REPO}"

# ── 7. Apply ArgoCD Project and Applications ──────────────────────────────────
section "Applying ArgoCD Project"
kubectl apply -f argocd/projects/gitops-project.yaml

section "Applying ArgoCD Applications"
kubectl apply -f argocd/applications/dev-app.yaml
kubectl apply -f argocd/applications/staging-app.yaml
kubectl apply -f argocd/applications/prod-app.yaml
info "Applications registered — ArgoCD will begin syncing shortly."

# ── 8. Change admin password ──────────────────────────────────────────────────
section "Change admin password"
NEW_PASSWORD=$(openssl rand -base64 20)
argocd account update-password \
  --current-password "${ARGOCD_PASSWORD}" \
  --new-password "${NEW_PASSWORD}"
info "Admin password updated."
warn "New ArgoCD admin password: ${NEW_PASSWORD}"
warn "⚠️  Save this in a password manager immediately!"

# ── Done ──────────────────────────────────────────────────────────────────────
section "ArgoCD Setup Complete"
cat <<EOF

  ArgoCD UI  : https://${ARGOCD_IP}
  Username   : admin
  Password   : ${NEW_PASSWORD}

  Applications registered:
    • gitops-demo-dev     (auto-sync: ON,  branch: dev)
    • gitops-demo-staging (auto-sync: ON,  branch: main)
    • gitops-demo-prod    (auto-sync: OFF, manual trigger required)

  Next step: run ./scripts/setup-secrets.sh to add GitHub Secrets.
EOF
