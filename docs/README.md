# Docs

**This repo** is Day 0 (a Kubernetes API). Argo CD and apps are **[k8s-gitops](../../k8s-gitops)**.

```text
Day 0   infra/        kind | aws (ec2) | openstack     ← this repo
Day 1   bootstrap/    Argo CD + repo access            ← k8s-gitops
Day 2   gitops/       platform apps from Git           ← k8s-gitops
```

**Resume:** [continue.md](./continue.md)

```text
docs/
├── README.md
├── continue.md
├── platform-lifecycle.md
├── prerequisites.md
└── infra/                 # Day 0 — pick an environment
```

| If you need… | Read |
|--------------|------|
| Why the three layers exist | [platform-lifecycle.md](./platform-lifecycle.md) |
| Tools and kubeconfig habit | [prerequisites.md](./prerequisites.md) |
| Build a cluster | [infra/](./infra/) — Kind, AWS EC2, or OpenStack |
| Lab inputs vs generated outputs | [clusters/README.md](../clusters/README.md) · [sensitive/README.md](../sensitive/README.md) |
| Install Argo CD / apps | [k8s-gitops](../../k8s-gitops) |

---

## One flow, two repos

```bash
# Day 0 — this repo
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws        && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp  && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig

# Day 1–2 — k8s-gitops
cd ../k8s-gitops
./bootstrap/bootstrap.sh
git push origin main
./scripts/gitops/start.sh dev
```

Day 1–2: **[k8s-gitops](../../k8s-gitops)**.
