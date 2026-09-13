# Prerequisites

Do this once. Day 0 is this repo; Day 1–2 are **[k8s-gitops](../../k8s-gitops)**.

## What you are building

- **Day 0** — a cluster exists (`./scripts/infra/up.sh` → Kind, AWS, or OpenStack)
- **Day 1** — Argo CD can read **k8s-gitops** (`bootstrap/` in that repo)
- **Day 2** — platform apps are declared in **k8s-gitops** (`gitops/`)

See [platform-lifecycle.md](./platform-lifecycle.md).

## Tools

```bash
brew install kind kubectl terraform
```

AWS also needs the AWS CLI (`brew install awscli`). OpenStack uses `clouds.yaml` (no extra CLI required for Terraform).

Or run [`scripts/lib/require-tools.sh`](../scripts/lib/require-tools.sh).

## Secrets

- **This repo:** `sensitive/aws/`, `sensitive/openstack/` (cloud keys). Copy `*.example`.
- **k8s-gitops:** `sensitive/bootstrap/secrets/*.yaml` (Argo repo Secrets). Copy `*.example`.

## Kubeconfig habit

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig    # Kind
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
```

GitOps profile **`dev`** is the folder `k8s-gitops/gitops/clusters/dev/`, not a second Kind cluster.

**Next:** [Day 0 — pick an environment](./infra/README.md)
