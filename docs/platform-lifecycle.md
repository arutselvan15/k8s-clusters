# Platform lifecycle

One platform, three ways to get a cluster. **Bootstrap and GitOps are reused.**

```text
┌─────────────────────────────────────────────────────────┐
│  Day 0  infra/     kind  ·  aws (ec2)  ·  openstack     │  env-specific
└────────────────────────────┬────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Day 1  bootstrap/     Argo CD + Git repo Secrets       │  common
└────────────────────────────┬────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────┐
│  Day 2  gitops/        Apps from Git (keeps growing)    │  common
└─────────────────────────────────────────────────────────┘
```

Index: [README.md](./README.md) · Resume: [continue.md](./continue.md)

## What each layer owns

| Phase | Question | What is reusable | What varies |
|-------|----------|------------------|-------------|
| **Day 0** | Is there a cluster? | Dispatcher `scripts/infra/up.sh`; kubeadm scripts for VMs | Terraform env: Kind vs EC2 vs OpenStack |
| **Day 1** | Can Git manage the cluster? | `bootstrap/` — same Helm install and repo Secrets | Overlay values (hostname, ingress) if a cluster needs them |
| **Day 2** | What runs on the cluster? | `gitops/` apps, App of Apps, sync waves | Cluster folder / Helm values (e.g. Kind `hostPort` vs cloud `LoadBalancer`) |

Kubeconfig path is the only required switch after Day 0: `sensitive/kind/kubeconfig`, or `sensitive/<env>/<cluster_name>/kubeconfig` for AWS/OpenStack.

## What does not belong where

- **Day 0:** VMs, VPC, Kind cluster, kubeadm — not Argo CD, not ingress, not apps.
- **Day 1:** Argo CD Helm release and clone credentials — not cert-manager, not app stacks.
- **Day 2:** Every platform app (ingress, cert-manager, certificates, Kyverno, later storage, observability, …) — not Terraform, not `kind create`.

## Environments (Day 0)

| Environment | Dispatcher | After Terraform | Kubeconfig |
|-------------|------------|-----------------|------------|
| `kind` | `./scripts/infra/up.sh kind` | Cluster is ready | `sensitive/kind/kubeconfig` |
| `ec2` | `./scripts/infra/up.sh aws k8s-aws` | `./scripts/infra/kubeadm/up.sh aws k8s-aws` | `sensitive/<env>/<cluster_name>/kubeconfig` |
| `openstack` | `./scripts/infra/up.sh openstack k8s-ocp` | `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` | `sensitive/<env>/<cluster_name>/kubeconfig` |

Day 1 / Day 2 currently use profile **`dev`**: `./bootstrap/bootstrap.sh dev`, `./scripts/gitops/start.sh dev`, `gitops/clusters/dev/`. That is the GitOps cluster name, not a second Kind cluster.

Bootstrap pins: `bootstrap/env/defaults.env` + gitignored `bootstrap.env` (loaded in `install.sh` only).

## Shared workflow

```bash
# 1. Day 0 — one environment
./scripts/infra/up.sh kind          # or aws|openstack <cluster> (+ kubeadm)
source scripts/lib/kubeconfig-setup.sh sensitive/<env>/<cluster_name>/kubeconfig

# 2. Day 1 — same on every cluster
./bootstrap/bootstrap.sh dev

# 3. Day 2 — same seed; apps live in gitops/
git push origin main
./scripts/gitops/start.sh dev
```

Kind-only shortcut for steps 1–2: `./scripts/bootstrap/up.sh`

**Kind UI (after cert Ready):** `127.0.0.1 argocd.dev` in `/etc/hosts` → **https://argocd.dev:8443**. Re-run `./bootstrap/bootstrap.sh dev` when `argocd-server-tls` is Ready. See [bootstrap/README.md](../bootstrap/README.md) and [gitops/README.md](../gitops/README.md).

Teardown Day 0 only (`gitops/` and `bootstrap/` stay in Git):

```bash
./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
./scripts/infra/down.sh openstack k8s-ocp -y   # does not delete the existing tenant network
```

OpenStack Terraform **looks up** `network_name`; destroy does **not** delete that network.

## Adding the next app

GitOps is the growth path. Pattern: [gitops/](./gitops/) — values under `gitops/apps/<name>/`, Application under `gitops/clusters/dev/core/applications/`, push, let Argo sync. Do not add a second bootstrap or a cloud-specific GitOps tree for each new component.
