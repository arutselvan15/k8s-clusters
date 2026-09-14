# Infra

Two independent layers on AWS and OpenStack: **compute** (VMs) and **Kubernetes** (kubeadm). Kind is local and includes the API in one step.

| Environment | Compute (VMs / Kind) | Kubernetes |
|-------------|----------------------|------------|
| **Kind** | [kind.md](./kind.md) — `./scripts/infra/up.sh kind` | Included (Kind creates the API) |
| **AWS EC2** | [aws.md](./aws.md) — `./scripts/infra/up.sh aws k8s-aws` | [kubeadm.md](./kubeadm.md) — `./scripts/infra/kubeadm/up.sh aws k8s-aws` |
| **OpenStack** | [openstack.md](./openstack.md) — `./scripts/infra/up.sh openstack k8s-ocp` | Same kubeadm scripts — `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` |

`up.sh` never runs kubeadm. `kubeadm/up.sh` never runs Terraform.

Optional on OpenStack: the Cloud Controller Manager (`./scripts/infra/openstack/occm.sh <id>`) lets `type: LoadBalancer` Services create their own Octavia LBs — see [openstack.md](./openstack.md#openstack-cloud-controller-manager-optional).

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/up.sh openstack k8s-ocp
```

Code: [`infra/terraform/environments/`](../../infra/terraform/environments/). Dispatcher: [`scripts/infra/up.sh`](../../scripts/infra/up.sh).

S3: after `up.sh` / `down.sh` (and kubeadm up/reset) you are asked to `push --prune`. Bucket name: `clusters/backup.yaml`.

Inputs (`clusters/`) vs outputs (`sensitive/`): [clusters/README.md](../../clusters/README.md) · [sensitive/README.md](../../sensitive/README.md)
