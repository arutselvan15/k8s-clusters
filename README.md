# k8s-clusters

Kubernetes clusters on **Kind**, **AWS EC2**, or **OpenStack**. Cloud **compute** is Terraform; **Kubernetes on those VMs** is kubeadm, in a separate step (not EKS).

| Path | Role |
|------|------|
| [clusters/](clusters/README.md) | Committed cluster YAML |
| [sensitive/](sensitive/README.md) | Credentials and generated outputs (not git) |
| [infra/](infra/README.md) | Terraform |
| [scripts/](scripts/README.md) | `up.sh` / `down.sh` / kubeadm / S3 |

```bash
./scripts/infra/up.sh kind k8s-kind
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp
```

How it works, kubeconfig, teardown, and S3: **[docs/](docs/README.md)**.
