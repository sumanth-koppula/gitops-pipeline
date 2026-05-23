# Secrets Reference

Every secret used by this pipeline, what it is, where it's used, and how to rotate it.

---

## GitHub Actions Secrets

Set these at: `github.com/YOUR_ORG/gitops-pipeline → Settings → Secrets and variables → Actions`

| Secret Name       | Required | Description                                        | Used In Workflows              |
|-------------------|----------|----------------------------------------------------|--------------------------------|
| `GCP_SA_KEY`      | ✅ Yes    | GCP Service Account JSON key (full file contents)  | ci-dev, ci-main, ci-release    |
| `GCP_PROJECT_ID`  | ✅ Yes    | GCP project ID string (e.g. `my-project-123`)      | ci-dev, ci-main, ci-release    |
| `STAGING_URL`     | ✅ Yes    | Base URL of staging app for smoke tests            | ci-main                        |
| `PROD_URL`        | ✅ Yes    | Base URL of production app for verification        | ci-release                     |
| `SLACK_WEBHOOK_URL` | ⚪ Optional | Slack incoming webhook URL for deploy alerts    | All (if configured)            |

---

## Secret Details

### `GCP_SA_KEY`
**What:** JSON key for the `github-actions-cicd` GCP Service Account.

**Format:**
```json
{
  "type": "service_account",
  "project_id": "YOUR_PROJECT",
  "private_key_id": "abc123...",
  "private_key": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "client_email": "github-actions-cicd@YOUR_PROJECT.iam.gserviceaccount.com",
  ...
}
```

**Permissions granted:**
- `roles/storage.admin` — push/pull GCR images
- `roles/container.developer` — deploy to GKE
- `roles/iam.serviceAccountUser` — impersonate service accounts
- `roles/secretmanager.secretAccessor` — read Secret Manager values

**Rotation (every 90 days):**
```bash
# 1. Create new key
gcloud iam service-accounts keys create new-key.json \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

# 2. Update GitHub secret
gh secret set GCP_SA_KEY --repo=YOUR_ORG/gitops-pipeline < new-key.json

# 3. List all keys and delete the old one
gcloud iam service-accounts keys list \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

gcloud iam service-accounts keys delete OLD_KEY_ID \
  --iam-account=github-actions-cicd@PROJECT_ID.iam.gserviceaccount.com

# 4. Delete local copy
rm new-key.json
```

---

### `GCP_PROJECT_ID`
**What:** Your GCP project's ID string (not the numeric project number).
**Example:** `my-startup-prod-12345`
**Where to find:** GCP Console → top navigation dropdown, or `gcloud config get-value project`
**Rotation:** Does not rotate — changes only if you move to a new GCP project.

---

### `STAGING_URL`
**What:** The base HTTPS URL of the staging application, used for smoke tests after deploy.
**Example:** `https://gitops-demo.staging.example.com`
**Used by:** `ci-main.yml` smoke test step — hits `/health`, `/health/ready`, `/api/v1/info`
**Update:** If your staging domain changes, update this secret.

---

### `PROD_URL`
**What:** The base HTTPS URL of the production application, used for post-deploy verification.
**Example:** `https://gitops-demo.example.com`
**Used by:** `ci-release.yml` verify step
**Update:** If your prod domain changes, update this secret.

---

## GitHub Environment Secrets (`production`)

The `production` GitHub Environment has additional protection settings beyond secrets.

**Setup:** `Settings → Environments → production`

**Required configuration:**
- ✅ Required reviewers: add release managers (minimum 1 person)
- ✅ Prevent self-review: enabled
- ✅ Deployment branches: restrict to `release/*`

---

## ArgoCD Repository Secret

ArgoCD stores the GitHub repo access token as a Kubernetes secret in the `argocd` namespace.

**View:**
```bash
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

**Rotate GitHub PAT used by ArgoCD:**
```bash
# Generate new PAT at: github.com → Settings → Developer settings → Personal access tokens
# Required scope: repo (read)

argocd repo update https://github.com/YOUR_ORG/gitops-pipeline.git \
  --username git \
  --password NEW_GITHUB_PAT
```

---

## Secrets NOT Stored in This Repo

The following must never be committed to Git:

| Item                        | Where to store              |
|-----------------------------|-----------------------------|
| GCP SA key files (`*.json`) | GitHub Secrets only         |
| ArgoCD admin password       | Password manager            |
| GitHub Personal Access Tokens | GitHub Secrets / Vault    |
| TLS private keys            | Kubernetes Secrets (cert-manager manages) |
| Database passwords          | GCP Secret Manager + K8s ExternalSecrets |

---

## Secret Scanning

This repo has GitHub Secret Scanning enabled. If a secret is accidentally committed:

1. **Immediately revoke** the leaked credential at its source (GCP, GitHub, etc.)
2. Run `git filter-repo` or BFG to purge it from history
3. Force-push the cleaned history
4. Issue a new credential and update the GitHub Secret

```bash
# Install git-filter-repo
pip install git-filter-repo

# Remove file containing secret from all history
git filter-repo --path sa-key.json --invert-paths

# Or remove a specific string pattern
git filter-repo --replace-text <(echo 'LEAKED_VALUE==>REDACTED')
```
