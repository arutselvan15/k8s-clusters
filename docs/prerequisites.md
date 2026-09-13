# Prerequisites

Do this once before `./scripts/infra/up.sh`.

## Tools

```bash
brew install kind kubectl terraform
```

AWS also needs the AWS CLI (`brew install awscli`). OpenStack uses `clouds.yaml` (no extra CLI required for Terraform).

Or run [`scripts/lib/require-tools.sh`](../scripts/lib/require-tools.sh) with the tools that environment needs (for example `terraform kubectl kind`).

## Secrets

Copy examples under `sensitive/` and fill them locally. Do not commit filled files.

```bash
cp sensitive/aws/credentials.example sensitive/aws/credentials
cp sensitive/aws/cli.conf.example sensitive/aws/cli.conf
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/aws/credentials sensitive/openstack/clouds.yaml
```

## Kubeconfig

After a cluster is up:

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
```

**Next:** [pick an environment](./infra/README.md)
