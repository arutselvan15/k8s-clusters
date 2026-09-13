# Continue here — session context

Last updated: **2026-09-12** (split: **k8s-clusters** Day 0, **k8s-gitops** Day 1–2).

---

## Project goal

One platform, two repos:

| Layer | Repo | Environments |
|-------|------|----------------|
| **Day 0 `infra/`** | **k8s-clusters** | Kind, AWS EC2, OpenStack |
| **Day 1 `bootstrap/`** | **k8s-gitops** | All clusters |
| **Day 2 `gitops/`** | **k8s-gitops** | All clusters |

Index: [`docs/README.md`](./README.md) · Model: [`platform-lifecycle.md`](./platform-lifecycle.md)

---

## Decisions

| Topic | Decision |
|--------|-----------|
| Reuse | Infra is env-specific; bootstrap and GitOps are **common** in k8s-gitops. |
| Argo clone URL | Applications `repoURL` = `k8s-gitops` GitHub remote, not this repo. |
| Cloud vs local | Kind for daily/$0; AWS / OpenStack for real VMs + kubeadm. |
| AWS Kubernetes | **Not EKS**; kubeadm on EC2. |
| Day 0 CLI | `scripts/infra/up.sh` / `down.sh` → `kind` \| `aws` \| `openstack`. |
| S3 backup | This repo’s `sensitive/` (kubeconfigs, tfstate, cloud keys). Bootstrap secrets stay in k8s-gitops. |
| OpenStack network | **Lookup** `network_name`; do **not** create or destroy the tenant net. |

---

## Commands

```bash
# Day 0 — this repo
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig

# Day 1 + 2 — k8s-gitops
cd ../k8s-gitops
./bootstrap/bootstrap.sh
git push origin main
./scripts/gitops/start.sh dev
```

---

## Open questions / when you return

- [ ] Whether EC2 + kubeadm `kubectl get nodes` works from the laptop.
- [ ] Whether OpenStack SSH to tenant fixed IPs works off-VPN.
- [ ] Whether to add AWS CCM (infra) vs only GitOps value overlays for ingress.
- [ ] Next GitOps app after current core (storage, observability, ESO, …).
