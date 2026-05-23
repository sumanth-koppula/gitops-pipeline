#!/usr/bin/env bash
# scripts/rollback.sh
# ─────────────────────────────────────────────────────────────────────────────
# Emergency rollback script.
# Supports two strategies:
#   1. Kubernetes rollback  — kubectl rollout undo (fastest, ~30s)
#   2. GitOps rollback      — revert kustomization.yaml image tag to previous
#                             commit and let ArgoCD re-sync (preferred for audit)
#
# Usage:
#   ./scripts/rollback.sh --env prod --strategy gitops
#   ./scripts/rollback.sh --env staging --strategy k8s
#   ./scripts/rollback.sh --env dev --strategy k8s --confirm
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
ENVIRONMENT=""
STRATEGY="gitops"          # gitops | k8s
CONFIRM=false
DRY_RUN=false
GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-us-central1-a}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)         ENVIRONMENT="$2"; shift 2 ;;
    --strategy)    STRATEGY="$2";    shift 2 ;;
    --confirm)     CONFIRM=true;     shift   ;;
    --dry-run)     DRY_RUN=true;     shift   ;;
    *) error "Unknown argument: $1" ;;
  esac
done

[[ -n "${ENVIRONMENT}" ]] || error "Usage: $0 --env <dev|staging|prod> [--strategy gitops|k8s] [--confirm] [--dry-run]"
[[ "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]] || error "Environment must be: dev, staging, or prod"
[[ "${STRATEGY}" =~ ^(gitops|k8s)$ ]] || error "Strategy must be: gitops or k8s"

NAMESPACE="gitops-${ENVIRONMENT}"
DEPLOYMENT="gitops-demo"
OVERLAY_PATH="k8s/overlays/${ENVIRONMENT}"

declare -A CLUSTERS=(
  ["dev"]="gitops-dev-cluster"
  ["staging"]="gitops-staging-cluster"
  ["prod"]="gitops-prod-cluster"
)
CLUSTER_NAME="${CLUSTERS[$ENVIRONMENT]}"

# ── Show current state ────────────────────────────────────────────────────────
section "Rollback: ${ENVIRONMENT} | Strategy: ${STRATEGY}"

if [[ -n "${GCP_PROJECT_ID}" ]]; then
  gcloud container clusters get-credentials "${CLUSTER_NAME}" \
    --zone="${ZONE}" --project="${GCP_PROJECT_ID}" --quiet
fi

echo ""
info "Current deployment state:"
kubectl get deployment "${DEPLOYMENT}" \
  -n "${NAMESPACE}" \
  -o jsonpath='  Image:    {.spec.template.spec.containers[0].image}{"\n"}  Replicas: {.status.readyReplicas}/{.spec.replicas}{"\n"}'
echo ""

info "Rollout history (last 5):"
kubectl rollout history deployment/"${DEPLOYMENT}" \
  -n "${NAMESPACE}" | tail -6

# ── Confirmation ──────────────────────────────────────────────────────────────
if [[ "${CONFIRM}" != "true" ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}⚠️  You are about to rollback the ${ENVIRONMENT^^} environment.${NC}"
  echo -e "   Strategy: ${STRATEGY}"
  echo -n "   Type 'yes' to confirm: "
  read -r ANSWER
  [[ "${ANSWER}" == "yes" ]] || { info "Rollback cancelled."; exit 0; }
fi

# ── Strategy: Kubernetes native rollback ──────────────────────────────────────
if [[ "${STRATEGY}" == "k8s" ]]; then
  section "Kubernetes Rollback (kubectl rollout undo)"

  warn "NOTE: This is a quick fix. ArgoCD will re-sync and overwrite this change."
  warn "      Use --strategy gitops to make the rollback persist in Git."

  if [[ "${DRY_RUN}" == "true" ]]; then
    info "[DRY RUN] Would run: kubectl rollout undo deployment/${DEPLOYMENT} -n ${NAMESPACE}"
  else
    kubectl rollout undo deployment/"${DEPLOYMENT}" -n "${NAMESPACE}"
    info "Rollback triggered. Monitoring rollout..."
    kubectl rollout status deployment/"${DEPLOYMENT}" \
      -n "${NAMESPACE}" --timeout=120s
    info "Rollback complete."
    echo ""
    info "New state:"
    kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
      -o jsonpath='  Image: {.spec.template.spec.containers[0].image}{"\n"}'
  fi

# ── Strategy: GitOps rollback (revert kustomization image tag) ────────────────
elif [[ "${STRATEGY}" == "gitops" ]]; then
  section "GitOps Rollback (revert image tag in Git → ArgoCD re-syncs)"

  # Find the previous image tag from git log
  CURRENT_COMMIT=$(git rev-parse HEAD)
  KUSTOMIZATION_FILE="${OVERLAY_PATH}/kustomization.yaml"

  info "Scanning git log for previous image tag in ${KUSTOMIZATION_FILE}..."

  PREV_TAG=""
  PREV_COMMIT=""
  while IFS= read -r COMMIT; do
    if [[ "${COMMIT}" == "${CURRENT_COMMIT}" ]]; then
      continue
    fi
    CONTENT=$(git show "${COMMIT}:${KUSTOMIZATION_FILE}" 2>/dev/null || true)
    TAG=$(echo "${CONTENT}" | grep 'newTag:' | awk '{print $2}' | tr -d '"' | head -1)
    if [[ -n "${TAG}" && "${TAG}" != "$(grep 'newTag:' "${KUSTOMIZATION_FILE}" | awk '{print $2}' | tr -d '"')" ]]; then
      PREV_TAG="${TAG}"
      PREV_COMMIT="${COMMIT}"
      break
    fi
  done < <(git log --format="%H" -- "${KUSTOMIZATION_FILE}")

  [[ -n "${PREV_TAG}" ]] || error "Could not find a previous image tag in git history for ${KUSTOMIZATION_FILE}"

  info "Current tag : $(grep 'newTag:' "${KUSTOMIZATION_FILE}" | awk '{print $2}')"
  info "Rollback to : ${PREV_TAG}  (from commit ${PREV_COMMIT:0:7})"

  if [[ "${DRY_RUN}" == "true" ]]; then
    info "[DRY RUN] Would update ${KUSTOMIZATION_FILE} → newTag: ${PREV_TAG} and git push"
  else
    cd "${OVERLAY_PATH}"
    kustomize edit set image "${DEPLOYMENT}=$(grep 'newName:' kustomization.yaml | awk '{print $2}'):${PREV_TAG}"
    cd - >/dev/null

    git add "${KUSTOMIZATION_FILE}"
    git commit -m "revert(${ENVIRONMENT}): rollback to ${PREV_TAG}

    Emergency rollback from $(git rev-parse --short HEAD)
    Operator: $(git config user.email || echo 'unknown')
    Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    git push

    info "Git updated. ArgoCD will auto-sync within 3 minutes."
    info "Force sync now: argocd app sync gitops-demo-${ENVIRONMENT}"
  fi
fi

# ── Post-rollback health check ────────────────────────────────────────────────
if [[ "${DRY_RUN}" != "true" ]]; then
  section "Post-Rollback Health Check"
  sleep 10
  READY=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  DESIRED=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
  info "Pods ready: ${READY}/${DESIRED}"
  [[ "${READY}" == "${DESIRED}" ]] && info "✅ Rollback successful!" || warn "⚠️  Pods not fully ready yet — check with: kubectl get pods -n ${NAMESPACE}"
fi

section "Rollback Complete"
