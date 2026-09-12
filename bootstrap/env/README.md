# Bootstrap environment

Loaded **only** by [`../argocd/install.sh`](../argocd/install.sh) via `load.sh`.

| File | In Git | Purpose |
|------|--------|---------|
| `defaults.env` | yes | `ARGO_CD_CHART_VERSION`, default `ARGOCD_OVERLAY`, `GIT_REPO_URL` |
| `bootstrap.env.example` | yes | Template for local overrides |
| `bootstrap.env` | **no** | `GITHUB_PAT`, `GITHUB_SSH_PRIVATE_KEY_B64`, `ARGOCD_ADMIN_PASSWORD`, etc. |
| `load.sh` | yes | `set -a`; sources `defaults.env`, then `bootstrap.env` if present |

`load.sh` exports variables so **`envsubst`** in `install.sh` can render `${VAR}` in [`../argocd/repos/`](../argocd/repos/) manifests.

```bash
cp bootstrap/env/bootstrap.env.example bootstrap/env/bootstrap.env
# edit secrets — never commit bootstrap.env
./bootstrap/bootstrap.sh dev
```

Overlay resolution (in `install.sh`): CLI argument → `ARGOCD_OVERLAY` from env → `dev`.

Kubeconfig is not stored here — use `source scripts/lib/kubeconfig-setup.sh <file>`.
