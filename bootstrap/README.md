# Day 1 — Bootstrap (GitOps controller)

Install **Argo CD** with Helm, then apply repo-creds and repository Secrets. Platform apps are Day 2 ([`../gitops/`](../gitops/README.md)).

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig   # or sensitive/<env>/<cluster_name>/kubeconfig
./bootstrap/bootstrap.sh
```

Kind (Day 0 + this step): `./scripts/bootstrap/up.sh`

After GitOps creates **`argocd-server-tls`**, re-run `./bootstrap/bootstrap.sh` → **https://argocd.dev:8443**.

## How it runs

```text
bootstrap/bootstrap.sh
        │
        └── argocd/install.sh
                  ├── load bootstrap/env/defaults.env
                  ├── load sensitive/bootstrap/bootstrap.env (if present)
                  ├── Helm: argo-cd chart + argocd/values.yaml
                  │         + optional sensitive/bootstrap/values.yaml
                  ├── apply repo-creds.*.yaml  (envsubst if ${VAR} present)
                  └── apply repo.*.yaml
```

- **`bootstrap.sh`** — thin wrapper.
- **`argocd/install.sh`** — only place that sources `env/load.sh`.

Prerequisites: [`../scripts/lib/require-tools.sh`](../scripts/lib/require-tools.sh) (`kubectl`, `helm`, `envsubst`).

## Configuration

| File | Git? | Purpose |
|------|------|---------|
| `argocd/values.yaml` | yes | Helm (ingress host `argocd.dev`, TLS secret name) |
| `argocd/values.example.yaml` | yes | Copy to `sensitive/bootstrap/values.yaml` to override Helm |
| `env/defaults.env` | yes | Chart pin, `GIT_REPO_URL` |
| `env/bootstrap.env.example` | yes | Copy to `sensitive/bootstrap/bootstrap.env` |
| `sensitive/bootstrap/bootstrap.env` | **no** | `GITHUB_PAT`, SSH key, `ARGOCD_ADMIN_PASSWORD` |
| `sensitive/bootstrap/values.yaml` | **no** | Extra Helm values |

```bash
mkdir -p sensitive/bootstrap
cp bootstrap/env/bootstrap.env.example sensitive/bootstrap/bootstrap.env
```

Details: [`env/README.md`](env/README.md). Repo manifests: [`argocd/repos/README.md`](argocd/repos/README.md).

Keep `GIT_REPO_URL` in `defaults.env` and `repo.k8s-platform.yaml` aligned with `gitops/clusters/…` Application `repoURL` values.

TLS Secret **material** comes from GitOps **`argocd-server-tls`**. Helm only sets `secretName`.

## Ingress + TLS (two steps)

```text
GitOps sync                    Bootstrap (Helm)
───────────                    ────────────────
ingress-nginx          →       (routing ready)
cert-manager           →       CRDs + controller
core-certificates      →       ClusterIssuer + Certificate → Secret argocd-server-tls
                               ↓ Certificate Ready
./bootstrap/bootstrap.sh       → ingress uses secretName argocd-server-tls
```

**https://argocd.dev:8443** — add `127.0.0.1 argocd.dev` to `/etc/hosts`. Until the cert is Ready, port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8888:80
```

User **`admin`**. Optional **`ARGOCD_ADMIN_PASSWORD`** in `sensitive/bootstrap/bootstrap.env`. Otherwise:

`kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 --decode; echo`

Day 2: [`../gitops/README.md`](../gitops/README.md) — `./scripts/gitops/start.sh <profile>`.
