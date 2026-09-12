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
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig
```

Host ports **8080 → 80** and **8443 → 443** on the control-plane node (Argo UI later: https://argocd.dev:8443). Teardown: `./scripts/infra/down.sh kind`

## ec2

Checklist: **[environments/ec2/STEPS.md](environments/ec2/STEPS.md)**

```bash
cp config/aws/credentials.example config/aws/credentials && chmod 600 config/aws/credentials
cp config/aws/cli.conf.example config/aws/cli.conf
cp config/aws/clusters/default.yaml.example config/aws/clusters/default.yaml
./scripts/infra/up.sh aws default
./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-aws/kubeconfig
```

## openstack

Checklist: **[environments/openstack/STEPS.md](environments/openstack/STEPS.md)**

```bash
cp config/openstack/clouds.yaml.example config/openstack/clouds.yaml && chmod 600 config/openstack/clouds.yaml
cp config/openstack/clusters/default.yaml.example config/openstack/clusters/default.yaml
./scripts/infra/up.sh openstack default
./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-os/kubeconfig
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
source scripts/lib/kubeconfig-setup.sh clusters/kind/kubeconfig   # or aws-dev / os-dev
./bootstrap/bootstrap.sh dev
```

Docs: [docs/README.md](../../docs/README.md)
