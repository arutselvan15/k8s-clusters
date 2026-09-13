# Day 0 — Kind

**Question answered:** “Is there a cluster and can `kubectl` talk to it?”

Nothing in Day 0 installs Argo CD, ingress, or cert-manager. After this environment is up, Day 1 and Day 2 are the **same** in **[k8s-gitops](../../../k8s-gitops)** as on AWS or OpenStack.

## Mental model

```text
Your Mac
   │
   └── Docker
         └── Kind cluster (name from clusters/kind/<id>/config.yaml)
                   └── Kubernetes API
```

Kind runs real Kubernetes inside a container. Networking and storage differ from cloud VMs; GitOps apps do not.

## What this repo creates

| Artifact | Path |
|----------|------|
| Terraform env | [`infra/terraform/environments/kind`](../../infra/terraform/environments/kind/) |
| Kind module | [`infra/terraform/modules/cluster-kind`](../../infra/terraform/modules/cluster-kind/) |
| Cluster YAML | [`clusters/kind/k8s-kind/config.yaml`](../../clusters/kind/k8s-kind/config.yaml) |
| Kubeconfig output | `sensitive/kind/<cluster_name>/kubeconfig` (gitignored locally) |

Dev Kind maps **host** ports from [`clusters/kind/k8s-kind/config.yaml`](../../clusters/kind/k8s-kind/config.yaml):

```yaml
terraform:
  http_host_port: 8080   # → container 80
  https_host_port: 8443  # → container 443
```

That is why later ingress on Kind is often **https://…:8443**, not `:443`.

## Commands

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
kubectl get nodes
```

Re-running `./scripts/infra/up.sh kind` is safe: Terraform apply refreshes the cluster and kubeconfig.

## After Kind is Ready

Use the **common** Day 1 / Day 2 path (only the kubeconfig path changes):

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
../k8s-gitops/bootstrap/bootstrap.sh
../k8s-gitops/scripts/gitops/start.sh dev
```

AWS and OpenStack Day 0: [aws.md](./aws.md), [openstack.md](./openstack.md). Dispatcher: [`scripts/infra/up.sh`](../../scripts/infra/up.sh).

## Teardown

```bash
./scripts/infra/down.sh kind
```

Removes the cluster and deletes `sensitive/kind/<cluster_name>/` (kubeconfig and Terraform state). Prompts to push `sensitive/` to S3 with prune. Platform credentials under `sensitive/aws/` and `sensitive/openstack/` are left in place.

## Checklist — you understood Day 0 when you can explain

- [ ] What Kind is vs “Kubernetes in the cloud”
- [ ] Where kubeconfig lives and why `KUBECONFIG` must be set
- [ ] Why Kind maps host ports 8080 and 8443

**Next:** [k8s-gitops](../../../k8s-gitops)
