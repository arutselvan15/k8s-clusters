# Day 1 — Bootstrap (Argo CD)

**Common on every environment.** Question: “Can we manage the cluster from Git?”

Day 1 installs the **GitOps controller** and gives it permission to clone your platform repo. It does **not** install ingress-nginx, cert-manager, or app stacks — those are [gitops](../gitops/).

## Chicken and egg

Argo CD syncs from Git, but Argo CD itself must exist first. So:

- **Day 1 (shell + Helm):** install Argo CD, apply repo Secrets
- **Day 2 (Git + one seed apply):** everything else

```text
Human + Helm          →  Argo CD running
Human + kubectl       →  repo-creds + repository Secrets
Git + scripts/gitops/start.sh    →  Applications sync platform
```

## What runs

```text
./bootstrap/bootstrap.sh
        └── bootstrap/argocd/install.sh
              ├── load bootstrap/env/defaults.env + sensitive/bootstrap/bootstrap.env
              ├── helm upgrade --install argo-cd (values.yaml + optional sensitive/bootstrap/values.yaml)
              ├── apply argocd/repos/repo-creds.*.yaml
              └── apply argocd/repos/repo.*.yaml
```

Env is loaded **only** in `install.sh`, not in `bootstrap.sh`.

## Configuration map

| Concern | Where |
|---------|--------|
| Chart version | `bootstrap/env/defaults.env` → `ARGO_CD_CHART_VERSION` |
| Helm values | `bootstrap/argocd/values.yaml` + optional `sensitive/bootstrap/values.yaml` |
| Git URL (must match GitOps) | `GIT_REPO_URL` in defaults + `bootstrap/argocd/repos/repo.k8s-platform.yaml` |
| Private GitHub | `sensitive/bootstrap/bootstrap.env` → PAT or SSH templates in `repos/` |

## What deliberately stays in bootstrap (not GitOps)

| Item | Reason |
|------|--------|
| Argo CD Helm release | Controller must exist before any Application |
| Repository / repo-creds Secrets | Argo needs clone access before first sync |
| Enabling Argo **ingress** in Helm | Chart is Day 1; **TLS Secret contents** are Day 2 GitOps ([cert-manager](../gitops/cert-manager.md), [argocd-tls](../gitops/argocd-tls.md)) |

Platform apps belong in **`gitops/`**, not in bootstrap scripts.

## Verify Day 1

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/<env>/<cluster_name>/kubeconfig
kubectl get pods -n argocd
```

Before Day 2 sync, UI access is usually port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8888:80
```

Admin user: **`admin`**. Password from `ARGOCD_ADMIN_PASSWORD` in `sensitive/bootstrap/bootstrap.env`, or:

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 --decode; echo
```

## Checklist

- [ ] Difference between Day 1 and Day 2
- [ ] Why `GIT_REPO_URL` must match `gitops/.../repoURL`
- [ ] Why ingress can be “configured” in Helm but not usable until GitOps ingress + certs sync

**Next:** [Day 2 — GitOps (common)](../gitops/README.md)