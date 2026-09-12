# Scripts

One folder per platform phase. Shared helpers live in `lib/`.

```text
scripts/
├── lib/                 # require-tools, kubeconfig-setup, cloud env
├── infra/               # Day 0 — cluster
│   ├── up.sh / down.sh  # kind | aws | openstack
│   ├── kind/ aws/ openstack/
│   └── kubeadm/         # Kubernetes on VMs (not Terraform)
├── bootstrap/           # Day 1 one-shot (Kind + Argo CD)
│   └── up.sh
└── gitops/              # Day 2
    ├── start.sh         # seed core-apps
    └── chainsaw.sh
```

```bash
./scripts/infra/up.sh kind
./scripts/bootstrap/up.sh
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
./scripts/gitops/start.sh dev

./scripts/infra/up.sh aws default
./scripts/infra/kubeadm/up.sh default

./scripts/infra/down.sh kind
./scripts/infra/down.sh aws default -y
```

Day 1 on **any** cluster: `./bootstrap/bootstrap.sh dev` (repo `bootstrap/`, not this folder).

`scripts/bootstrap/up.sh` is Kind-only convenience (Day 0 Kind + Day 1).

Docs: [docs/README.md](../docs/README.md) · Inputs: [config/README.md](../config/README.md) · Outputs: [clusters/README.md](../clusters/README.md)
