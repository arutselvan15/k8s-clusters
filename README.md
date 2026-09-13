# k8s-clusters

Day 0 cluster build (Kind, AWS EC2, OpenStack + kubeadm). Day 1 Argo CD and Day 2 apps live in sibling **[k8s-gitops](../k8s-gitops)**.

| Path | Role |
|------|------|
| [clusters/](clusters/README.md) | Committed cluster YAML |
| [sensitive/](sensitive/README.md) | Cloud keys and Terraform outputs (not git; S3) |
| [infra/](infra/README.md) | Day 0 — Kind, AWS EC2, OpenStack |
| [scripts/](scripts/README.md) | `up.sh` / `down.sh` / kubeadm / S3 |

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig

cd ../k8s-gitops
./bootstrap/bootstrap.sh
./scripts/gitops/start.sh dev
```

Guides: [docs/README.md](docs/README.md)
