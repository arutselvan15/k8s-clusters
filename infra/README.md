# Day 0 — Infrastructure

Provision a Kubernetes cluster with **Terraform only**. Nothing here installs Argo CD, ingress, or other platform apps.

```text
infra/terraform/
├── modules/cluster-kind/
└── environments/
    ├── kind/            # local Kind
    ├── ec2/             # AWS VMs → kubeadm
    └── openstack/       # OpenStack VMs → kubeadm
```

```bash
./scripts/infra/up.sh kind
./scripts/infra/up.sh aws default
./scripts/infra/up.sh openstack default
```

## Environments

| Environment | What Terraform creates | Kubeconfig |
|-------------|------------------------|------------|
| [`terraform/environments/kind`](terraform/environments/kind/) | Kind cluster `dev`, host ports 8080/8443 | `clusters/kind/kubeconfig` |
| [`terraform/environments/ec2`](terraform/environments/ec2/) | VPC, SG, EC2, SSH key ([STEPS.md](terraform/environments/ec2/STEPS.md)) | `clusters/<cluster_name>/kubeconfig` after kubeadm |
| [`terraform/environments/openstack`](terraform/environments/openstack/) | Ports, VMs on an existing Neutron net ([STEPS.md](terraform/environments/openstack/STEPS.md)) | `clusters/<cluster_name>/kubeconfig` after kubeadm |

kubeadm is **not** Terraform. After `./scripts/infra/up.sh aws default` or `openstack default`, run `./scripts/infra/kubeadm/up.sh default`.

Kind cluster name is **`dev`** (not `kind-dev`) so the kubeconfig context stays readable.

## Kind

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
```

Re-apply is safe. **Day 0 + Day 1:** `./scripts/bootstrap/up.sh`

Teardown: `./scripts/infra/down.sh kind`

## AWS / OpenStack

```bash
./scripts/infra/up.sh aws default && ./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-aws/kubeconfig

./scripts/infra/up.sh openstack default && ./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-os/kubeconfig
```

AWS: `config/aws/credentials` + `cli.conf` + `clusters/*.yaml` (gitignored).  
OpenStack: `config/openstack/clouds.yaml` + `clusters/*.yaml` (gitignored). Terraform **looks up** `network_name`; it does not create or destroy that network.

Inputs vs outputs: [config/README.md](../config/README.md) · [clusters/README.md](../clusters/README.md)

Teardown: `./scripts/infra/down.sh aws default -y` / `./scripts/infra/down.sh openstack default -y`

## Prerequisites

```bash
brew install kind kubectl helm gettext terraform
brew link --force gettext
```

`./scripts/lib/require-tools.sh terraform kubectl kind` (Kind) or `terraform aws` (EC2).

## Next (Day 1)

```bash
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
./bootstrap/bootstrap.sh dev
```

## Docs

[docs/README.md](../docs/README.md) · Day 0 guides: [docs/infra/](../docs/infra/) · Then common [bootstrap](../docs/bootstrap/) and [gitops](../docs/gitops/)
