# Day 0 — Kind

**Question answered:** “Is there a cluster and can `kubectl` talk to it?”

Nothing in Day 0 installs Argo CD, ingress, or cert-manager. After this environment is up, [bootstrap](../bootstrap/) and [gitops](../gitops/) are the **same** as on AWS or OpenStack.

## Mental model

```text
Your Mac
   │
   └── Docker
         └── Kind “dev” cluster (control-plane node)
                   └── Kubernetes API
```

Kind runs real Kubernetes inside a container. Networking and storage differ from cloud VMs; GitOps apps do not.

## What this repo creates

| Artifact | Path |
|----------|------|
| Terraform env | [`infra/terraform/environments/kind`](../../infra/terraform/environments/kind/) |
| Kind module | [`infra/terraform/modules/cluster-kind`](../../infra/terraform/modules/cluster-kind/) |
| Cluster YAML | [`clusters/kind/dev/config.yaml`](../../clusters/kind/dev/config.yaml) |
| Kubeconfig output | `sensitive/kind/kubeconfig` (gitignored locally) |

Dev Kind maps **host** ports from [`clusters/kind/dev/config.yaml`](../../clusters/kind/dev/config.yaml):

```yaml
terraform:
  http_host_port: 8080   # → container 80
  https_host_port: 8443  # → container 443
```

That is why the Argo UI later is **https://argocd.dev:8443**, not `:443`.

## Commands

**Shortcut (Day 0 + Day 1 in one script):**

```bash
./scripts/bootstrap/up.sh
```

**Day 0 only:**

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/kubeconfig
kubectl get nodes
```

Re-running `./scripts/infra/up.sh kind` is safe: Terraform apply refreshes the cluster and kubeconfig.

## After Kind is Ready

Use the **common** Day 1 / Day 2 path (only the kubeconfig path changes):

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/kubeconfig
./bootstrap/bootstrap.sh dev
./scripts/gitops/start.sh dev
```

AWS and OpenStack Day 0: [aws.md](./aws.md), [openstack.md](./openstack.md). Dispatcher: [`scripts/infra/up.sh`](../../scripts/infra/up.sh).

## Teardown

```bash
./scripts/infra/down.sh kind
```

Removes the cluster and `sensitive/kind/kubeconfig`. Prompts to push `sensitive/` to S3 with prune.

## Checklist — you understood Day 0 when you can explain

- [ ] What Kind is vs “Kubernetes in the cloud”
- [ ] Where kubeconfig lives and why `KUBECONFIG` must be set
- [ ] Why dev uses host ports 8080 and 8443

**Next:** [Day 1 — bootstrap (common)](../bootstrap/README.md) (or you already ran it via `scripts/bootstrap/up.sh`)
