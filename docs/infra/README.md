# Infra (Day 0)

Provision a Kubernetes **API**. Nothing here installs Argo CD or platform apps.

Pick **one** environment. After `kubectl get nodes` works, go to **[k8s-gitops](../../../k8s-gitops)** (Day 1 bootstrap, then Day 2 gitops).

| Environment | Guide | What Terraform creates | Then |
|-------------|--------|------------------------|------|
| **Kind** | [kind.md](./kind.md) | Local Kind cluster `dev`, host ports 8080/8443 | Cluster is ready |
| **AWS EC2** | [aws.md](./aws.md) + [aws-kubeadm.md](./aws-kubeadm.md) | VPC, SG, EC2 | `./scripts/infra/kubeadm/up.sh aws k8s-aws` |
| **OpenStack** | [openstack.md](./openstack.md) | Ports, VMs on an **existing** Neutron net | `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` |

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp
```

Code: [`infra/terraform/environments/`](../../infra/terraform/environments/). Dispatcher: [`scripts/infra/up.sh`](../../scripts/infra/up.sh).

kubeadm is **not** Terraform. The same remote scripts install Kubernetes on AWS and OpenStack VMs.

S3: after `up.sh` / `down.sh` (and kubeadm up/reset) you are asked to `push --prune`. Bucket name: `clusters/backup.yaml`.

Inputs (`clusters/`) vs outputs (`sensitive/`): [clusters/README.md](../../clusters/README.md) · [sensitive/README.md](../../sensitive/README.md)

**Next (every environment):** [k8s-gitops](../../../k8s-gitops)
