# Scripts

```text
scripts/
├── lib/                 # require-tools, kubeconfig-setup, cloud env
├── infra/               # cluster create / destroy
│   ├── up.sh / down.sh  # kind | aws | openstack
│   ├── kind/ aws/ openstack/
│   └── kubeadm/         # Kubernetes on VMs (not Terraform)
└── sensitive/s3.sh      # backup sensitive/ to S3 (init|push|pull|offer)
```

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig

./scripts/infra/up.sh aws k8s-aws
./scripts/infra/kubeadm/up.sh aws k8s-aws

./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
```

After up/down (and kubeadm up/reset) you are prompted to push `sensitive/` to S3 with prune.

Docs: [docs/README.md](../docs/README.md) · Inputs: [clusters/README.md](../clusters/README.md) · Secrets: [sensitive/README.md](../sensitive/README.md)
