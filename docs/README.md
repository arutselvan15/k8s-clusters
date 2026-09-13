# Docs

How to get a working Kubernetes API from this repo.

```text
docs/
├── README.md
├── continue.md
├── platform-lifecycle.md
├── prerequisites.md
└── infra/                 # Kind, AWS EC2, OpenStack
```

| If you need… | Read |
|--------------|------|
| Environments and kubeconfig paths | [platform-lifecycle.md](./platform-lifecycle.md) |
| Tools and local secrets | [prerequisites.md](./prerequisites.md) |
| Build a cluster | [infra/](./infra/) |
| Inputs vs outputs | [clusters/README.md](../clusters/README.md) · [sensitive/README.md](../sensitive/README.md) |

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws        && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp  && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
kubectl get nodes
```

**Resume:** [continue.md](./continue.md)
