# Scripts

One folder per platform phase. Shared helpers live in `lib/`.

```text
scripts/
├── lib/                 # require-tools, kubeconfig-setup, cloud env
├── infra/               # Day 0 — cluster
│   ├── up.sh / down.sh  # kind | aws | openstack
│   ├── kind/ aws/ openstack/
│   └── kubeadm/         # Kubernetes on VMs (not Terraform)
├── sensitive/s3.sh      # backup sensitive/ to S3 (init|push|pull|offer)
├── bootstrap/           # Day 1 one-shot (Kind + Argo CD)
│   └── up.sh
└── gitops/              # Day 2
    ├── start.sh         # seed core-apps
    └── chainsaw.sh
```

```bash
./scripts/infra/up.sh kind
./scripts/bootstrap/up.sh
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig
./scripts/gitops/start.sh dev

./scripts/infra/up.sh aws k8s-aws
./scripts/infra/kubeadm/up.sh aws k8s-aws

./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
```

Day 1 on **any** cluster: `./bootstrap/bootstrap.sh` (repo `bootstrap/`, not this folder).

`./scripts/bootstrap/up.sh` is Kind-only convenience (Day 0 Kind + Day 1). After Day 0 up/down (and kubeadm up/reset) you are prompted to push `sensitive/` to S3 with prune.

Docs: [docs/README.md](../docs/README.md) · Inputs: [clusters/README.md](../clusters/README.md) · Secrets: [sensitive/README.md](../sensitive/README.md)
