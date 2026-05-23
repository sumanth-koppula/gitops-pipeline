# GitOps CI/CD Pipeline — Complete Implementation Guide

## Objective

Build a production-grade **GitOps CI/CD pipeline** where:
- A `git push` triggers automated build, test, and deployment
- Docker images are built and pushed to **Google Container Registry (GCR)**
- **ArgoCD** watches the Git repo and auto-syncs Kubernetes manifests to **GKE**
- Branch strategy maps directly to environments: `dev` → Dev cluster, `main` → Staging, `release/*` → Production

---

## Architecture

```
Developer
    │
    ▼ git push
┌─────────────────────────────────────────────────────────┐
│                    GitHub Repository                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │ app/     │  │ k8s/     │  │ .github/workflows/   │  │
│  │ (source) │  │(manifests│  │  (CI/CD pipelines)   │  │
│  └──────────┘  └──────────┘  └──────────────────────┘  │
└─────────────────────────────────────────────────────────┘
    │                               │
    │ Trigger                       │ Sync Watch
    ▼                               ▼
┌──────────────┐           ┌───────────────────┐
│GitHub Actions│           │      ArgoCD        │
│  (CI/CD)     │           │  (GitOps Operator) │
│              │           │                   │
│ 1. Lint      │           │ Polls Git every   │
│ 2. Test      │           │ 3 mins for drift  │
│ 3. Build     │           │ Auto-syncs state  │
│ 4. Push →GCR │           └─────────┬─────────┘
│ 5. Update    │                     │
│    manifests │                     │ kubectl apply
└──────────────┘                     ▼
    │                      ┌─────────────────────┐
    │                      │   GKE Cluster        │
    ▼                      │                     │
┌──────────┐               │  ┌───────────────┐  │
│   GCR    │◄──────────────│  │  Dev NS       │  │
│ (Images) │  image pull   │  │  Staging NS   │  │
└──────────┘               │  │  Prod NS      │  │
                           │  └───────────────┘  │
                           └─────────────────────┘
```

### Branch → Environment Strategy

| Branch        | Environment | Auto-Deploy | Approval Required |
|---------------|-------------|-------------|-------------------|
| `dev`         | Development | ✅ Yes       | ❌ No              |
| `main`        | Staging     | ✅ Yes       | ❌ No              |
| `release/*`   | Production  | ❌ No        | ✅ Yes (Manual)    |

---

## Folder Structure

```
gitops-pipeline/
├── README.md
│
├── app/                            # Node.js Application
│   ├── src/
│   │   ├── index.js                # App entrypoint
│   │   ├── routes/
│   │   │   ├── health.js           # Health & readiness probes
│   │   │   └── api.js              # Business logic routes
│   │   └── middleware/
│   │       └── logger.js           # Request logging
│   ├── tests/
│   │   ├── health.test.js
│   │   └── api.test.js
│   ├── package.json
│   ├── Dockerfile                  # Multi-stage Docker build
│   └── .dockerignore
│
├── .github/
│   └── workflows/
│       ├── ci-dev.yml              # Dev branch pipeline
│       ├── ci-main.yml             # Main branch (staging) pipeline
│       ├── ci-release.yml          # Release branch (prod) pipeline
│       └── pr-checks.yml           # PR validation workflow
│
├── k8s/                            # Kubernetes Manifests (Kustomize)
│   ├── base/                       # Shared base manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── hpa.yaml
│   │   ├── configmap.yaml
│   │   ├── serviceaccount.yaml
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── dev/
│       │   ├── kustomization.yaml
│       │   ├── deployment-patch.yaml
│       │   └── configmap-patch.yaml
│       ├── staging/
│       │   ├── kustomization.yaml
│       │   ├── deployment-patch.yaml
│       │   └── configmap-patch.yaml
│       └── prod/
│           ├── kustomization.yaml
│           ├── deployment-patch.yaml
│           ├── configmap-patch.yaml
│           └── hpa-patch.yaml
│
├── argocd/                         # ArgoCD Configurations
│   ├── projects/
│   │   └── gitops-project.yaml     # AppProject definition
│   └── applications/
│       ├── dev-app.yaml
│       ├── staging-app.yaml
│       └── prod-app.yaml
│
├── helm/                           # Helm Charts (alternative to Kustomize)
│   └── gitops-app/
│       ├── Chart.yaml
│       ├── values.yaml             # Default values
│       ├── values-dev.yaml
│       ├── values-staging.yaml
│       ├── values-prod.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── hpa.yaml
│           ├── ingress.yaml
│           └── _helpers.tpl
│
├── scripts/
│   ├── setup-gcp.sh                # GCP project bootstrap
│   ├── setup-argocd.sh             # ArgoCD installation
│   ├── setup-secrets.sh            # GitHub Secrets configuration
│   └── rollback.sh                 # Emergency rollback
│
└── docs/
    ├── SETUP.md                    # One-time setup guide
    ├── RUNBOOK.md                  # Operational runbook
    └── SECRETS.md                  # Required secrets reference
```

---

## Prerequisites

| Tool           | Version  | Purpose                          |
|----------------|----------|----------------------------------|
| gcloud CLI     | latest   | GCP authentication & GKE access  |
| kubectl        | v1.28+   | Kubernetes cluster management    |
| helm           | v3.12+   | Helm chart deployment            |
| argocd CLI     | v2.9+    | ArgoCD management                |
| docker         | v24+     | Local image building             |
| node.js        | v20 LTS  | Application runtime              |

---

## Quick Start

```bash
# 1. Clone and bootstrap
git clone https://github.com/YOUR_ORG/gitops-pipeline.git
cd gitops-pipeline

# 2. Set up GCP resources
chmod +x scripts/*.sh
./scripts/setup-gcp.sh

# 3. Install ArgoCD
./scripts/setup-argocd.sh

# 4. Configure GitHub Secrets
./scripts/setup-secrets.sh

# 5. Deploy ArgoCD Applications
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/

# 6. Push code — pipeline triggers automatically!
git checkout -b dev
git push origin dev
```
# GitOps Pipeline - P3 Project
