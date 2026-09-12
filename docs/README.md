# Docs

Reusable platform: **infra changes per environment**; **bootstrap and GitOps stay the same**.

```text
Day 0   infra/        kind | aws (ec2) | openstack     ← env-specific
Day 1   bootstrap/    Argo CD + repo access            ← common
Day 2   gitops/       platform apps from Git           ← common, grows
```

After any Day 0 cluster is up, point `KUBECONFIG` at it and run the **same** Day 1 and Day 2 commands. GitOps is the catalog of apps; add a new app there once and every environment can sync it.

**Resume:** [continue.md](./continue.md)

```text
docs/
├── README.md
├── continue.md
├── platform-lifecycle.md
├── prerequisites.md
├── infra/                 # Day 0 — pick an environment
├── bootstrap/             # Day 1 — common
└── gitops/                # Day 2 — common apps
```

| If you need… | Read |
|--------------|------|
| Why the three layers exist | [platform-lifecycle.md](./platform-lifecycle.md) |
| Tools and kubeconfig habit | [prerequisites.md](./prerequisites.md) |
| Build a cluster | [infra/](./infra/) — Kind, AWS EC2, or OpenStack |
| Lab inputs vs generated outputs | [clusters/README.md](../clusters/README.md) · [sensitive/README.md](../sensitive/README.md) |
| Install Argo CD | [bootstrap/](./bootstrap/) |
| Platform apps (ingress, certs, policy, …) | [gitops/](./gitops/) |
| Commands next to the code | [scripts/README.md](../scripts/README.md), [infra/README.md](../infra/README.md), [bootstrap/README.md](../bootstrap/README.md), [gitops/README.md](../gitops/README.md) |

---

## One flow, three environments

```bash
# Day 0 — choose one
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws        && ./scripts/infra/kubeadm/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp  && ./scripts/infra/kubeadm/up.sh openstack k8s-ocp

# Same from here on (kubeconfig path is the only difference)
source scripts/lib/kubeconfig-setup.sh sensitive/kind/kubeconfig   # or sensitive/<env>/<cluster_name>/kubeconfig
./bootstrap/bootstrap.sh dev
git push origin main
./scripts/gitops/start.sh dev
```

Kind convenience (Day 0 Kind + Day 1): `./scripts/bootstrap/up.sh`

---

## GitOps grows here

Do **not** fork bootstrap or GitOps per cloud. New platform software is another Application under `gitops/` (values + Application YAML + sync-wave). Current apps and how to add the next one: [gitops/](./gitops/).
