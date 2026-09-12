# Day 2 — GitOps

Platform workloads are declared in Git and synced by **Argo CD** (installed in Day 1). Shell scripts do not install ingress, cert-manager, or apps after bootstrap.

Full reference for this repo: concepts below, then step-by-step **Deploy dev core**.

---

## Three Argo CD building blocks

| Kind | Example in this repo | Purpose |
|------|----------------------|---------|
| **AppProject** | `applications/core.appproject.yaml` → AppProject **`core`** | **Policy** for platform apps. Synced by **`core-apps`** (wave `-1`). |
| **Application (App of Apps)** | `core.application.yaml` → **`core-apps`** | Syncs **`core/applications/`**. Started by **`./scripts/gitops/start.sh <profile>`** (Day 2 — not bootstrap). |
| **Application (platform app)** | `ingress-nginx.application.yaml` | Helm chart + values → target namespace. |
| **Application (platform TLS)** | `core-certificates.application.yaml` | cert-manager CRs from **`core/certificates/`** (separate Git path, project **`core`**). |
| **Application (platform policy)** | `core-policies.application.yaml` | Kyverno **ClusterPolicy** CRs from **`core/policies/`**. |

**Analogy:** **`core-apps`** = register what runs (Applications + AppProject). **`core-certificates`** = deliver infra TLS. **`core-policies`** = admission policies. Certificate and policy YAML live under **`core/certificates/`** and **`core/policies/`** but are **not** on the **`core-apps`** source path.

---

## How sync flows (dev)

```text
You (once)                Argo CD                         Cluster
─────────                 ───────                         ───────
./scripts/gitops/start.sh dev
        │
        ▼
                    Application "core-apps"
                    (project: default)
                    source: gitops/clusters/dev/core/applications/
        │
        ├── wave -1   AppProject "core"     (core.appproject.yaml)
        ├── wave 10   Application "ingress-nginx"
        ├── wave 20   Application "cert-manager"
        ├── wave 25   Application "core-certificates"
        │             source: gitops/clusters/dev/core/certificates/
        ├── wave 30   Application "kyverno"
        │             Helm chart + gitops/apps/kyverno/values.yaml
        └── wave 35   Application "core-policies"
                      source: gitops/clusters/dev/core/policies/
```

| Application | Git path | Argo UI resources |
|-------------|----------|-------------------|
| **`core-apps`** | `core/applications/` | AppProject **`core`** + child **Application** CRs only |
| **`core-certificates`** | `core/certificates/` | **ClusterIssuer**, **Certificate**, future infra TLS |
| **`core-policies`** | `core/policies/` | **ClusterPolicy** and other Kyverno policy CRs |

**`gitops/apps/`** holds Helm **values** only. Child apps use multi-source `$values/gitops/apps/...`.

**`gitops/chainsaw/`** holds [Kyverno Chainsaw](https://kyverno.github.io/chainsaw/) e2e tests for policies (not synced by Argo CD). See [`chainsaw/README.md`](chainsaw/README.md).

---

## Repository layout

```text
gitops/
├── apps/
│   ├── ingress-nginx/values.yaml
│   ├── cert-manager/values.yaml
│   └── kyverno/values.yaml
├── chainsaw/                          # Chainsaw e2e tests (local/CI, not Argo)
│   └── disallow-latest-tag/
└── clusters/dev/
    ├── core.application.yaml          # seed → core-apps
    └── core/
        ├── applications/              # core-apps source (only this path)
        │   ├── core.appproject.yaml
        │   ├── ingress-nginx.application.yaml
        │   ├── cert-manager.application.yaml
        │   ├── core-certificates.application.yaml
        │   ├── kyverno.application.yaml
        │   └── core-policies.application.yaml
        ├── certificates/              # core-certificates source only
        │   ├── clusterissuer-selfsigned.yaml
        │   └── argocd-server-certificate.yaml
        └── policies/                  # core-policies source only
            └── disallow-latest-tag.yaml
```

---

## Prerequisites

1. **Day 1 done** — Argo CD running (`./scripts/bootstrap/up.sh`, or `./scripts/infra/up.sh kind` then `./bootstrap/bootstrap.sh dev`).
2. **Git repo registered** — `argocd/install.sh` applies repo Secrets ([`../bootstrap/env/`](../bootstrap/env/)).
3. **`KUBECONFIG`** set ([`../scripts/lib/kubeconfig-setup.sh`](../scripts/lib/kubeconfig-setup.sh)).
4. **Push to Git** — Argo clones remote, not your working tree.

---

## Deploy dev core (step by step)

### 1. Align Git URLs

Match **`repoURL`** in `core.application.yaml`, each platform Application’s `ref: values` source, and **`applications/core.appproject.yaml`** → `sourceRepos`.

### 2. Push Git

```bash
git add gitops/
git commit -m "Day 2: core platform gitops"
git push
```

### 3. Start GitOps (Day 2)

```bash
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
./scripts/gitops/start.sh dev
```

Equivalent: `kubectl apply -f gitops/clusters/dev/core.application.yaml`. Safe to re-run.

Do **not** hand-apply files under `core/applications/` or `core/certificates/`.

### 4. Verify

```bash
kubectl get applications -n argocd
# core-apps, ingress-nginx, cert-manager, core-certificates, kyverno, core-policies (Synced)
kubectl get certificate -n argocd argocd-server-tls
```

Add **`127.0.0.1 argocd.dev`** to `/etc/hosts`. When the Certificate is **Ready**, run **`./bootstrap/bootstrap.sh dev`**, then open **https://argocd.dev:8443**.

### 5. Migrate old layouts

```bash
kubectl delete application dev-root core-root platform-certificates argocd-certificates -n argocd --ignore-not-found
kubectl apply -f gitops/clusters/dev/core.application.yaml
kubectl annotate application core-apps -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

---

## Troubleshooting

### Certs listed under **`core-apps`**

Old **`core-apps`** path was `core/` with `recurse`. **Fix:** path must be **`core/applications/`** only; certs in **`core/certificates/`**. Re-apply seed, hard-refresh, sync with prune.

### CRD not found on sync

Do not add cert YAML under **`applications/`**. Use **`core-certificates`** → **`core/certificates/`**.

---

## Add another core component

1. `gitops/apps/<name>/values.yaml`
2. `gitops/clusters/dev/core/applications/<name>.application.yaml` (`project: core`, sync-wave)
3. Update **`applications/core.appproject.yaml`** if new repo or namespace
4. Push — **`core-apps`** picks up the new Application

### Add a core infra certificate

1. Add YAML under **`gitops/clusters/dev/core/certificates/`** (never under **`applications/`**).
2. Align **`secretName`** / DNS with the consumer (e.g. [`bootstrap/argocd/values/overlays/dev.yaml`](../bootstrap/argocd/values/overlays/dev.yaml)).
3. Push — **`core-certificates`** syncs only.

---

## What stays outside GitOps

| Phase | Installed by |
|--------|----------------|
| Cluster (Day 0) | Kind / Terraform |
| Argo CD (Day 1) | `bootstrap.sh` → `argocd/install.sh` |
| Seed **`core-apps`** | [`../scripts/gitops/start.sh`](../scripts/gitops/start.sh) `<profile>` |

See also: [`../docs/README.md`](../docs/README.md), [`../docs/platform-lifecycle.md`](../docs/platform-lifecycle.md), [Day 1 bootstrap](../bootstrap/README.md), [GitOps notes](../docs/gitops/).
