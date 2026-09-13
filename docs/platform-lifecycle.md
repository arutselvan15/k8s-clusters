# Cluster lifecycle

This repo creates a Kubernetes API on Kind, AWS EC2, or OpenStack.

| Environment | Create VMs / Kind | Install Kubernetes | Kubeconfig |
|-------------|-------------------|--------------------|------------|
| Kind | `./scripts/infra/up.sh kind` | Kind does it | `sensitive/kind/<cluster_name>/kubeconfig` |
| AWS | `./scripts/infra/up.sh aws k8s-aws` | `./scripts/infra/kubeadm/up.sh aws k8s-aws` | `sensitive/aws/<cluster_name>/kubeconfig` |
| OpenStack | `./scripts/infra/up.sh openstack k8s-ocp` | `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` | `sensitive/openstack/<cluster_name>/kubeconfig` |

- **Kind:** local Docker. Terraform applies the Kind cluster.
- **AWS / OpenStack:** Terraform creates VMs only. kubeadm on those VMs is a separate step. Not EKS.
- **OpenStack:** Terraform **looks up** `network_name`. Destroy does **not** delete that Neutron network.

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig
kubectl get nodes
```

Teardown:

```bash
./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
./scripts/infra/down.sh openstack k8s-ocp -y
```

After destroy, the dispatcher prompts to push `sensitive/` to S3 with prune.

Index: [README.md](./README.md)
