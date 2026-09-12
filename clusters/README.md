# Clusters — generated outputs

This directory is **created by scripts**. Do not commit files here (see `.gitignore`).

Each live cluster uses `cluster_name` from the YAML you passed to `./scripts/infra/up.sh`.

| After Day 0 | After kubeadm |
|-------------|----------------|
| `clusters/<cluster_name>/ssh.pem`, `cluster.env`, `terraform.tfstate` | `kubeconfig` |
| Kind: `clusters/kind/kubeconfig` | (Kind is already Kubernetes) |

Edit **`config/<platform>/clusters/<id>.yaml`**, not this folder.

```bash
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
source scripts/lib/kubeconfig-setup.sh clusters/k8s-aws/kubeconfig
source scripts/lib/kubeconfig-setup.sh clusters/k8s-os/kubeconfig
```
