#!/usr/bin/env bash
# scripts/setup-gcp.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-time GCP bootstrap: enables APIs, creates GKE clusters,
# GCR repository, and the CI/CD service account with least-privilege IAM.
#
# Usage:
#   export GCP_PROJECT_ID=my-project-id
#   export GCP_REGION=us-central1
#   ./scripts/setup-gcp.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Config (override via env vars) ───────────────────────────────────────────
PROJECT_ID="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID}"
REGION="${GCP_REGION:-us-central1}"
ZONE="${GCP_ZONE:-us-central1-a}"
SA_NAME="github-actions-cicd"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Cluster configs per environment
declare -A CLUSTERS=(
  ["dev"]="gitops-dev-cluster"
  ["staging"]="gitops-staging-cluster"
  ["prod"]="gitops-prod-cluster"
)
declare -A NODE_COUNTS=( ["dev"]="1" ["staging"]="2" ["prod"]="3" )
declare -A MACHINE_TYPES=( ["dev"]="e2-small" ["staging"]="e2-medium" ["prod"]="e2-standard-2" )

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
section() { echo -e "\n${GREEN}━━━ $* ━━━${NC}"; }

# ── 1. Set active project ─────────────────────────────────────────────────────
section "Setting active project"
gcloud config set project "${PROJECT_ID}"
info "Project: ${PROJECT_ID}"

# ── 2. Enable required APIs ───────────────────────────────────────────────────
section "Enabling GCP APIs"
APIS=(
  container.googleapis.com          # GKE
  containerregistry.googleapis.com  # GCR
  cloudbuild.googleapis.com         # Cloud Build
  iam.googleapis.com                # IAM
  iamcredentials.googleapis.com     # Workload Identity
  secretmanager.googleapis.com      # Secret Manager
  monitoring.googleapis.com         # Cloud Monitoring
  logging.googleapis.com            # Cloud Logging
)
for API in "${APIS[@]}"; do
  info "Enabling ${API}..."
  gcloud services enable "${API}" --project="${PROJECT_ID}" --quiet
done
info "All APIs enabled."

# ── 3. Create GCR Repository ─────────────────────────────────────────────────
section "Configuring GCR"
# GCR is enabled automatically when containerregistry.googleapis.com is on.
# Push a dummy tag to initialise the registry bucket:
info "GCR registry: gcr.io/${PROJECT_ID}/gitops-demo"
info "Registry will be created automatically on first image push."

# ── 4. Create CI/CD Service Account ──────────────────────────────────────────
section "Creating CI/CD Service Account"
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" &>/dev/null; then
  warn "Service account ${SA_EMAIL} already exists — skipping creation."
else
  gcloud iam service-accounts create "${SA_NAME}" \
    --project="${PROJECT_ID}" \
    --display-name="GitHub Actions CI/CD"
  info "Created service account: ${SA_EMAIL}"
fi

# Roles needed by GitHub Actions
ROLES=(
  roles/storage.admin               # Push/pull GCR images
  roles/container.developer         # Deploy to GKE
  roles/iam.serviceAccountUser      # Impersonate service accounts
  roles/secretmanager.secretAccessor # Read secrets
)
for ROLE in "${ROLES[@]}"; do
  info "Granting ${ROLE}..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --quiet
done

# ── 5. Export Service Account Key ────────────────────────────────────────────
section "Exporting Service Account Key"
KEY_FILE="./sa-key-${SA_NAME}.json"
gcloud iam service-accounts keys create "${KEY_FILE}" \
  --iam-account="${SA_EMAIL}" \
  --project="${PROJECT_ID}"
info "Key saved to: ${KEY_FILE}"
warn "⚠️  Add the contents of ${KEY_FILE} as the GitHub secret GCP_SA_KEY"
warn "⚠️  Then DELETE this file — never commit it to Git!"

# ── 6. Create GKE Clusters ────────────────────────────────────────────────────
section "Creating GKE Clusters"
for ENV in dev staging prod; do
  CLUSTER_NAME="${CLUSTERS[$ENV]}"
  info "Creating ${ENV} cluster: ${CLUSTER_NAME}..."

  if gcloud container clusters describe "${CLUSTER_NAME}" \
      --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
    warn "Cluster ${CLUSTER_NAME} already exists — skipping."
    continue
  fi

  gcloud container clusters create "${CLUSTER_NAME}" \
    --project="${PROJECT_ID}" \
    --zone="${ZONE}" \
    --num-nodes="${NODE_COUNTS[$ENV]}" \
    --machine-type="${MACHINE_TYPES[$ENV]}" \
    --enable-autoupgrade \
    --enable-autorepair \
    --enable-ip-alias \
    --workload-pool="${PROJECT_ID}.svc.id.goog" \
    --release-channel="regular" \
    --disk-type="pd-standard" \
    --disk-size="50GB" \
    --quiet

  info "Cluster ${CLUSTER_NAME} created."
done

# ── 7. Create Kubernetes Namespaces ───────────────────────────────────────────
section "Creating Namespaces"
for ENV in dev staging prod; do
  CLUSTER_NAME="${CLUSTERS[$ENV]}"
  gcloud container clusters get-credentials "${CLUSTER_NAME}" \
    --zone="${ZONE}" --project="${PROJECT_ID}" --quiet

  NS="gitops-${ENV}"
  kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -
  info "Namespace '${NS}' ready on cluster '${CLUSTER_NAME}'."
done

# ── Done ──────────────────────────────────────────────────────────────────────
section "GCP Setup Complete"
cat <<EOF
Next steps:
  1. Add GCP_SA_KEY (contents of ${KEY_FILE}) to GitHub Secrets
  2. Add GCP_PROJECT_ID=${PROJECT_ID} to GitHub Secrets
  3. Run ./scripts/setup-argocd.sh to install ArgoCD
  4. Delete ${KEY_FILE} from your local machine!
EOF
