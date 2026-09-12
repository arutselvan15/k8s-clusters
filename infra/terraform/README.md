# Terraform (Day 0)

One root module per **environment**. Do not mix providers.

```text
infra/terraform/
├── modules/
│   └── cluster-kind/
└── environments/
    ├── kind/            # Kind on the laptop
    ├── ec2/             # kubeadm on EC2
    └── openstack/       # kubeadm on OpenStack
```

## kind

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml
```

Host ports **8080 → 80** and **8443 → 443** on the control-plane node (Argo UI later: https://argocd.dev:8443). Teardown: `./scripts/infra/down.sh kind`

## ec2

Checklist: **[environments/ec2/STEPS.md](environments/ec2/STEPS.md)**

```bash
cp .aws/credentials.example .aws/credentials && chmod 600 .aws/credentials
cp .aws/config.example .aws/config
./scripts/infra/up.sh aws
./scripts/infra/kubeadm/up.sh
source scripts/lib/kubeconfig-setup.sh .kube/aws-dev.yaml
```

## openstack

Checklist: **[environments/openstack/STEPS.md](environments/openstack/STEPS.md)**

```bash
cp .openstack/clouds.yaml.example .openstack/clouds.yaml && chmod 600 .openstack/clouds.yaml
cp .openstack/config.example .openstack/config
./scripts/infra/up.sh openstack
./scripts/infra/kubeadm/up.sh -i .kube/os-inventory.env
source scripts/lib/kubeconfig-setup.sh .kube/os-dev.yaml
```

Terraform does **not** create or destroy the existing Neutron network.

## Install Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version   # >= 1.5
```

## Day 1

```bash
source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml   # or aws-dev / os-dev
./bootstrap/bootstrap.sh dev
```

Docs: [docs/README.md](../../docs/README.md)
