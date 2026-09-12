# Infra (Day 0)

Provision a Kubernetes **API**. Nothing here installs Argo CD or platform apps.

Pick **one** environment. After `kubectl get nodes` works, go to [bootstrap](../bootstrap/) (common) then [gitops](../gitops/) (common).

| Environment | Guide | What Terraform creates | Then |
|-------------|--------|------------------------|------|
| **Kind** | [kind.md](./kind.md) | Local Kind cluster `dev`, host ports 8080/8443 | Cluster is ready |
| **AWS EC2** | [aws.md](./aws.md) + [aws-kubeadm.md](./aws-kubeadm.md) | VPC, SG, EC2 | `./scripts/infra/kubeadm/up.sh default` |
| **OpenStack** | [openstack.md](./openstack.md) | Ports, VMs on an **existing** Neutron net | `./scripts/infra/kubeadm/up.sh default` |

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws default
./scripts/infra/up.sh openstack default
```

Code: [`infra/terraform/environments/`](../../infra/terraform/environments/). Dispatcher: [`scripts/infra/up.sh`](../../scripts/infra/up.sh).

kubeadm is **not** Terraform. The same remote scripts install Kubernetes on AWS and OpenStack VMs.

Inputs (`config/`) vs outputs (`clusters/`): [config/README.md](../../config/README.md) · [clusters/README.md](../../clusters/README.md)

**Next (every environment):** [bootstrap](../bootstrap/) → [gitops](../gitops/)
