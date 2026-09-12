# Bootstrap environment

Loaded **only** by [`../argocd/install.sh`](../argocd/install.sh) via `load.sh`.

| File | In Git | Purpose |
|------|--------|---------|
| `defaults.env` | yes | `ARGO_CD_CHART_VERSION`, `GIT_REPO_URL` |
| `bootstrap.env.example` | yes | Template — copy to `sensitive/bootstrap/bootstrap.env` |
| `load.sh` | yes | Sources defaults, then `sensitive/bootstrap/bootstrap.env` |

Secrets (`GITHUB_PAT`, `GITHUB_SSH_PRIVATE_KEY_B64`, `ARGOCD_ADMIN_PASSWORD`) live in **`sensitive/bootstrap/bootstrap.env`**, not under `bootstrap/env/`. Optional Helm overrides: **`sensitive/bootstrap/values.yaml`**.

```bash
mkdir -p sensitive/bootstrap
cp bootstrap/env/bootstrap.env.example sensitive/bootstrap/bootstrap.env
# edit secrets — never commit that file
./bootstrap/bootstrap.sh
```

Kubeconfig is separate: `source scripts/lib/kubeconfig-setup.sh <file>`.
