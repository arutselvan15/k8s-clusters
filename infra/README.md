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
./scripts/infra/up.sh aws
./scripts/infra/up.sh openstack
```

## Environments

| Environment | What Terraform creates | Kubeconfig |
|-------------|------------------------|------------|
| [`terraform/environments/kind`](terraform/environments/kind/) | Kind cluster `dev`, host ports 8080/8443 | `.kube/kind-dev.yaml` |
| [`terraform/environments/ec2`](terraform/environments/ec2/) | VPC, SG, EC2, SSH key ([STEPS.md](terraform/environments/ec2/STEPS.md)) | `.kube/aws-dev.yaml` after kubeadm |
| [`terraform/environments/openstack`](terraform/environments/openstack/) | Ports, VMs on an existing Neutron net ([STEPS.md](terraform/environments/openstack/STEPS.md)) | `.kube/os-dev.yaml` after kubeadm |

kubeadm is **not** Terraform. After `./scripts/infra/up.sh aws` or `openstack`, run `./scripts/infra/kubeadm/up.sh` (OpenStack: `-i .kube/os-inventory.env`).

Kind cluster name is **`dev`** (not `kind-dev`) so the kubeconfig context stays readable.

## Kind

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml
```

Re-apply is safe. **Day 0 + Day 1:** `./scripts/bootstrap/up.sh`

Teardown: `./scripts/infra/down.sh kind`

## AWS / OpenStack

```bash
./scripts/infra/up.sh aws && ./scripts/infra/kubeadm/up.sh
source scripts/lib/kubeconfig-setup.sh .kube/aws-dev.yaml

./scripts/infra/up.sh openstack && ./scripts/infra/kubeadm/up.sh -i .kube/os-inventory.env
source scripts/lib/kubeconfig-setup.sh .kube/os-dev.yaml
```

AWS: `.aws/credentials` + `.aws/config` (gitignored).  
OpenStack: `.openstack/clouds.yaml` + `.openstack/config` (gitignored). Terraform **looks up** `network_name`; it does not create or destroy that network.

Teardown: `./scripts/infra/down.sh aws -y` / `./scripts/infra/down.sh openstack -y`

## Prerequisites

```bash
brew install kind kubectl helm gettext terraform
brew link --force gettext
```

`./scripts/lib/require-tools.sh terraform kubectl kind` (Kind) or `terraform aws` (EC2).

## Next (Day 1)

```bash
source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml
./bootstrap/bootstrap.sh dev
```

## Docs

[docs/README.md](../docs/README.md) · Day 0 guides: [docs/infra/](../docs/infra/) · Then common [bootstrap](../docs/bootstrap/) and [gitops](../docs/gitops/)
