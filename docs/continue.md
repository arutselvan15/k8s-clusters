# Continue here — session context

Last updated: **2026-09-12**.

This repo builds Kubernetes clusters (Kind, AWS EC2 + kubeadm, OpenStack + kubeadm).

Index: [`docs/README.md`](./README.md) · Model: [`platform-lifecycle.md`](./platform-lifecycle.md)

## Decisions

| Topic | Decision |
|--------|-----------|
| Cloud vs local | Kind for daily/laptop; AWS / OpenStack for real VMs + kubeadm |
| AWS Kubernetes | **Not EKS**; kubeadm on EC2 |
| CLI | `scripts/infra/up.sh` / `down.sh` → `kind` \| `aws` \| `openstack` |
| S3 backup | This repo’s `sensitive/` (kubeconfigs, tfstate, cloud keys) |
| OpenStack network | **Lookup** `network_name`; do **not** create or destroy the tenant net |

## Commands

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig
kubectl get nodes
```

## Open questions / when you return

- [ ] Whether EC2 + kubeadm `kubectl get nodes` works from the laptop
- [ ] Whether OpenStack SSH to tenant fixed IPs works off-VPN
- [ ] Whether to add an AWS cloud controller (LoadBalancer Services on EC2)
