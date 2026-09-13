# Prerequisites

Do this once. The same tools and habits apply on Kind, AWS, and OpenStack.

## What you are building

A **reusable platform**:

- **Day 0** — a cluster exists (`./scripts/infra/up.sh` → Kind, AWS, or OpenStack)
- **Day 1** — Argo CD can read your Git repo (`bootstrap/` — **common**)
- **Day 2** — platform apps are declared in Git (`gitops/` — **common**, grows)

See [platform-lifecycle.md](./platform-lifecycle.md).

## Tools

```bash
brew install kind kubectl helm gettext terraform
brew link --force gettext                 # if envsubst missing
```

AWS also needs the AWS CLI (`brew install awscli`). OpenStack uses `clouds.yaml` (no extra CLI required for Terraform).

Or run [`scripts/lib/require-tools.sh`](../scripts/lib/require-tools.sh) — used by [`scripts/bootstrap/up.sh`](../scripts/bootstrap/up.sh) and `scripts/infra/up.sh`.

Optional for a custom Argo admin password: `htpasswd` (e.g. Apache `httpd` tools).

## Secrets (Day 1)

`sensitive/bootstrap/bootstrap.env` (optional) and `sensitive/bootstrap/secrets/*.yaml` (repo Secrets). Copy `*.yaml.example` to `*.yaml`.

## Kubeconfig habit

Point the shell at the cluster you just built, then run the same bootstrap and GitOps commands:

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig    # Kind
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig     # AWS after kubeadm
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig      # OpenStack after kubeadm
```

GitOps profile **`dev`** (`./scripts/gitops/start.sh dev`, `gitops/clusters/dev/`) is the GitOps folder name, not a second Kind cluster.

**Next:** [Day 0 — pick an environment](./infra/README.md)
