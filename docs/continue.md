# Continue here — session context

Use this file when resuming work (solo or with an AI assistant). Paste or link: **“Read `docs/continue.md` and continue from Next steps.”**

Last updated: **2026-09-12** (reusable infra / common bootstrap + GitOps).

---

## Project goal

**k8s-platform** — one platform you can stand up on any Day 0 environment:

| Layer | Reuse | Environments |
|-------|--------|----------------|
| **Day 0 `infra/`** | Dispatcher + kubeadm scripts | **Kind**, **AWS EC2**, **OpenStack** |
| **Day 1 `bootstrap/`** | Same Argo CD install | All clusters |
| **Day 2 `gitops/`** | Same app catalog; grows over time | All clusters |

Index: [`docs/README.md`](./README.md) · Model: [`platform-lifecycle.md`](./platform-lifecycle.md)

---

## Decisions

| Topic | Decision |
|--------|-----------|
| Reuse | Infra is env-specific; bootstrap and GitOps are **common**. New apps go in `gitops/`, not a per-cloud copy. |
| Cloud vs local | Kind for daily/$0; AWS / OpenStack for real VMs + kubeadm. |
| AWS Kubernetes | **Not EKS**; kubeadm on EC2. |
| Day 0 CLI | `scripts/infra/up.sh` / `down.sh` → `kind` \| `aws` \| `openstack`. Terraform envs: `kind`, `ec2`, `openstack`. |
| kubeadm | Same args as Day 0: `kubeadm/up.sh aws k8s-aws`. Inventory-only; same scripts on AWS and OpenStack. |
| S3 backup | Bucket in `clusters/backup.yaml`. Dispatchers prompt y/N then `push --prune`. |
| OpenStack network | **Lookup** `network_name`; do **not** create or destroy the tenant net. |
| Ingress on cloud | Kind uses `hostPort`; cloud typically needs `LoadBalancer` (AWS CCM not in repo yet). Same GitOps app, different values. |

---

## What is in the repo

### Common (Day 1–2)

- Bootstrap: `./bootstrap/bootstrap.sh dev`
- GitOps seed: `./scripts/gitops/start.sh dev` → `gitops/clusters/dev/`
- Apps: ingress-nginx, cert-manager, core-certificates, kyverno, core-policies
- Guides: [bootstrap/](./bootstrap/), [gitops/](./gitops/)

### Day 0 environments

| Env | Code | Guide |
|-----|------|--------|
| Kind | [`infra/terraform/environments/kind/`](../infra/terraform/environments/kind/) | [infra/kind.md](./infra/kind.md) |
| AWS | [`environments/ec2/`](../infra/terraform/environments/ec2/) + kubeadm | [infra/aws.md](./infra/aws.md), [aws-kubeadm.md](./infra/aws-kubeadm.md) |
| OpenStack | [`environments/openstack/`](../infra/terraform/environments/openstack/) + kubeadm | [infra/openstack.md](./infra/openstack.md) |

### Not done yet

- AWS Cloud Controller Manager (LoadBalancer Services on EC2)
- Cluster-specific Helm overlays where Kind `hostPort` is wrong for cloud (same GitOps apps)

---

## Commands

```bash
# Day 0 — one of
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

# Day 1 + 2 — same
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig   # or sensitive/<env>/<cluster_name>/kubeconfig
./bootstrap/bootstrap.sh dev
git push origin main
./scripts/gitops/start.sh dev
```

Kind one-shot Day 0+1: `./scripts/bootstrap/up.sh`

---

## How to resume with an assistant

1. Open this file and the layer you are in: [infra](./infra/), [bootstrap](./bootstrap/), or [gitops](./gitops/).
2. Say the environment (kind / aws / openstack) and whether `kubectl get nodes` already works.
3. Prefer adding GitOps apps over new Day 0 or bootstrap scripts.

---

## Related files

| File | Role |
|------|------|
| [`README.md`](./README.md) | Docs index |
| [`platform-lifecycle.md`](./platform-lifecycle.md) | Three-layer model |
| [`infra/README.md`](../infra/README.md) | Day 0 dispatcher |
| [`bootstrap/README.md`](../bootstrap/README.md) | Day 1 runbook |
| [`gitops/README.md`](../gitops/README.md) | Day 2 runbook |
| [`.gitignore`](../.gitignore) | Commits `clusters/`; ignores `sensitive/**` (S3) and tfstate |

---

## Open questions / when you return

- [ ] Whether EC2 + kubeadm `kubectl get nodes` works from the laptop.
- [ ] Whether OpenStack SSH to tenant fixed IPs works off-VPN.
- [ ] Whether to add AWS CCM (infra) vs only GitOps value overlays for ingress.
- [ ] Next GitOps app after current core (storage, observability, ESO, …).

Update the checklist as you progress.
