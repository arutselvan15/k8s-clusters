# Argo CD repository Secrets — applied by `argocd/install.sh` after Helm.

| Glob | Role |
|------|------|
| `repo-creds.*.yaml` | Credential templates (`repo-creds` Secret type) |
| `repo.*.yaml` | Repository entries (`repository` Secret type) |

Manifests with **`${VAR}`** placeholders are rendered with **`envsubst`** using `bootstrap/env/defaults.env` plus **`sensitive/bootstrap/bootstrap.env`**. Plain YAML is applied with `kubectl apply`.

| File | Notes |
|------|--------|
| `repo.k8s-platform.yaml` | Platform Git repo (committed URL) |
| `repo-creds.github.pat.yaml` | `${GITHUB_PAT}` for `https://github.com/*` |
| `repo-creds.github.ssh.yaml` | `${GITHUB_SSH_PRIVATE_KEY_B64}` for SSH |

Verify: `argocd repo list` or Argo CD UI → Settings → Repositories.
