# Operations Runbook — GitOps CI/CD Pipeline

Day-2 operational guide: how to deploy, rollback, scale, debug, and maintain the pipeline.

---

## Deployment Workflows

### Normal Deploy — Dev
Push any change to the `dev` branch:
```bash
git checkout dev
# make changes
git push origin dev
# Pipeline: lint → test → build → push GCR → update manifest → ArgoCD syncs
```

### Normal Deploy — Staging
Merge a PR into `main`:
```bash
gh pr merge 42 --squash    # or via GitHub UI
# Pipeline: test → security scan → build → push GCR → update manifest → ArgoCD syncs → smoke test
```

### Production Release
```bash
git checkout main && git pull
git checkout -b release/1.2.3
git push origin release/1.2.3
# Pipeline: full test → security → build → MANUAL APPROVAL → update manifest
# ArgoCD syncs only after manual sync trigger (prod is NOT auto-synced)
```

Trigger ArgoCD prod sync after approval:
```bash
argocd app sync gitops-demo-prod --revision HEAD
argocd app wait gitops-demo-prod --health --timeout 300
```

---

## Rollback Procedures

### Option A — GitOps Rollback (Preferred — creates audit trail)
```bash
export GCP_PROJECT_ID=your-project-id

# Staging rollback
./scripts/rollback.sh --env staging --strategy gitops

# Prod rollback (requires confirmation)
./scripts/rollback.sh --env prod --strategy gitops --confirm
```

### Option B — Kubernetes Rollback (Fastest — ~30 seconds, but ArgoCD will overwrite it)
```bash
# Get rollout history
kubectl rollout history deployment/gitops-demo -n gitops-prod

# Roll back one revision
kubectl rollout undo deployment/gitops-demo -n gitops-prod

# Roll back to specific revision
kubectl rollout undo deployment/gitops-demo -n gitops-prod --to-revision=3

# Monitor
kubectl rollout status deployment/gitops-demo -n gitops-prod
```

> After a k8s rollback, **pause ArgoCD auto-sync** to prevent it from re-applying the bad version:
```bash
argocd app patch gitops-demo-prod --patch '{"spec":{"syncPolicy":null}}' --type merge
```

### Option C — ArgoCD History Rollback (Roll back to any previous Git commit)
```bash
# List sync history
argocd app history gitops-demo-prod

# Rollback to specific history ID
argocd app rollback gitops-demo-prod <HISTORY_ID>
```

---

## Scaling

### Manual Scale (temporary — HPA will take over)
```bash
kubectl scale deployment/gitops-demo --replicas=5 -n gitops-prod
```

### Update HPA limits (permanent — via Git)
Edit `k8s/overlays/prod/hpa-patch.yaml`, commit, and push. ArgoCD will apply it.

### Check current HPA state
```bash
kubectl get hpa gitops-demo-hpa -n gitops-prod
kubectl describe hpa gitops-demo-hpa -n gitops-prod
```

---

## Debugging

### Check pod status
```bash
ENV=prod   # or dev, staging
NS="gitops-${ENV}"

kubectl get pods     -n $NS -l app=gitops-demo
kubectl get events   -n $NS --sort-by=.metadata.creationTimestamp | tail -20
kubectl top pods     -n $NS -l app=gitops-demo
```

### Read logs
```bash
# All pods (live)
kubectl logs -n gitops-prod -l app=gitops-demo -f --max-log-requests=10

# Crashed pod
kubectl logs -n gitops-prod -l app=gitops-demo --previous

# Specific pod
kubectl logs -n gitops-prod POD_NAME
```

### Exec into a running pod
```bash
POD=$(kubectl get pod -n gitops-prod -l app=gitops-demo -o name | head -1)
kubectl exec -it $POD -n gitops-prod -- sh
```

### Describe a pod for scheduling/probe failures
```bash
kubectl describe pod -l app=gitops-demo -n gitops-prod
```

---

## ArgoCD Operations

### Force sync an application
```bash
argocd app sync gitops-demo-dev      # dev
argocd app sync gitops-demo-staging  # staging
argocd app sync gitops-demo-prod     # prod (manual trigger)
```

### Check sync status
```bash
argocd app list
argocd app get gitops-demo-prod
```

### Pause auto-sync (e.g., during an incident)
```bash
argocd app patch gitops-demo-staging \
  --patch '{"spec":{"syncPolicy":{"automated":null}}}' \
  --type merge
```

### Resume auto-sync
```bash
argocd app patch gitops-demo-staging \
  --patch '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' \
  --type merge
```

### Refresh ArgoCD cache (force re-poll Git)
```bash
argocd app get gitops-demo-dev --refresh
```

---

## Updating the Application

### Bump Node.js version
1. Update `FROM node:20-alpine` → `FROM node:22-alpine` in `app/Dockerfile`
2. Update `node-version: '20'` → `'22'` in all `.github/workflows/*.yml`
3. Update `"node": ">=20.0.0"` in `app/package.json`
4. Commit, push to `dev`, test, then promote to `main` → `release/x.y.z`

### Add a new environment variable
1. Add to `k8s/base/configmap.yaml` (default value)
2. Override per environment in `k8s/overlays/*/configmap-patch.yaml`
3. Reference in `k8s/base/deployment.yaml` under `env[].valueFrom.configMapKeyRef`
4. Commit and push — ArgoCD applies automatically

### Rotate the GCP Service Account Key
```bash
# Create new key
gcloud iam service-accounts keys create new-key.json \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

# Update GitHub secret
gh secret set GCP_SA_KEY --repo=YOUR_ORG/gitops-pipeline < new-key.json

# List and delete old keys
gcloud iam service-accounts keys list \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

gcloud iam service-accounts keys delete OLD_KEY_ID \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

rm new-key.json
```

---

## Monitoring & Alerting

### GCP Cloud Monitoring dashboards
Navigate to: GCP Console → Monitoring → Dashboards
- GKE Workloads → Filter by namespace `gitops-prod`
- Container logs: Logging → `resource.type=k8s_container AND resource.labels.namespace_name=gitops-prod`

### Key metrics to watch
| Metric | Warning | Critical |
|--------|---------|----------|
| Pod restarts | > 3/hour | > 10/hour |
| CPU utilization | > 70% | > 90% |
| Memory utilization | > 80% | > 95% |
| HTTP 5xx rate | > 1% | > 5% |
| p99 latency | > 500ms | > 2s |
| HPA at maxReplicas | Any | Sustained > 5min |

---

## Cost Management

### Resize dev cluster overnight (save ~60% compute cost)
```bash
# Scale down dev cluster nodes to 0 (off-hours)
gcloud container clusters resize gitops-dev-cluster \
  --node-pool=default-pool --num-nodes=0 \
  --zone=us-central1-a --project=YOUR_PROJECT

# Scale back up
gcloud container clusters resize gitops-dev-cluster \
  --node-pool=default-pool --num-nodes=1 \
  --zone=us-central1-a --project=YOUR_PROJECT
```

### Clean up old GCR images
```bash
# Delete images older than 30 days (keep tagged ones)
gcloud container images list-tags gcr.io/PROJECT_ID/gitops-demo \
  --filter="NOT tags:*" \
  --format="get(digest)" | \
  xargs -I {} gcloud container images delete \
    "gcr.io/PROJECT_ID/gitops-demo@{}" --force-delete-tags --quiet
```
