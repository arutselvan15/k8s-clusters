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
source scripts/lib/kubeconfig-setup.sh sensitive/kind/kubeconfig
```

Host ports **8080 → 80** and **8443 → 443** on the control-plane node (Argo UI later: https://argocd.dev:8443). Teardown: `./scripts/infra/down.sh kind`

## ec2

Checklist: **[environments/ec2/STEPS.md](environments/ec2/STEPS.md)**

```bash
mkdir -p sensitive/aws
# credentials + cli.conf live in sensitive/aws/
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
```

## openstack

Checklist: **[environments/openstack/STEPS.md](environments/openstack/STEPS.md)**

```bash
mkdir -p sensitive/openstack
cp clusters/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml && chmod 600 sensitive/openstack/clouds.yaml
./scripts/infra/up.sh openstack k8s-ocp
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
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
source scripts/lib/kubeconfig-setup.sh sensitive/kind/kubeconfig   # or sensitive/<env>/<cluster_name>/kubeconfig
./bootstrap/bootstrap.sh dev
```

Docs: [docs/README.md](../../docs/README.md)
