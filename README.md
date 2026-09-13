# k8s-clusters

Day 0 cluster · Day 1 Argo CD · Day 2 apps from Git. Same bootstrap and GitOps on Kind, AWS, and OpenStack.

| Path | Role |
|------|------|
| [clusters/](clusters/README.md) | Committed cluster YAML |
| [sensitive/](sensitive/README.md) | Secrets and Terraform outputs (not git; S3) |
| [infra/](infra/README.md) | Day 0 — Kind, AWS EC2, OpenStack |
| [bootstrap/](bootstrap/README.md) | Day 1 — Argo CD |
| [gitops/](gitops/README.md) | Day 2 — apps from Git |
| [scripts/](scripts/README.md) | `up.sh` / `down.sh` / kubeadm / S3 |

Kind (Day 0 + Day 1): `./scripts/bootstrap/up.sh`

Guides: [docs/README.md](docs/README.md)
