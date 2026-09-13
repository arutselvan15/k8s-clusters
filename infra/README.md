# Infrastructure

Terraform for Kind, AWS EC2, and OpenStack. Kubernetes on VMs is kubeadm ([`../scripts/infra/kubeadm/`](../scripts/README.md)), not Terraform.

```text
infra/terraform/
├── modules/cluster-kind/
└── environments/
    ├── kind/         # laptop
    ├── ec2/          # AWS VMs → kubeadm
    └── openstack/    # OpenStack VMs → kubeadm
```

Commands: [`../scripts/infra/`](../scripts/README.md). Inputs: [`../clusters/`](../clusters/README.md). Outputs: [`../sensitive/`](../sensitive/README.md).

## Kind

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig
```

Knobs: [`../clusters/kind/k8s-kind/config.yaml`](../clusters/kind/k8s-kind/config.yaml). Same as `./scripts/infra/up.sh kind k8s-kind`.

Teardown: `./scripts/infra/down.sh kind`

Host ports **8080 → 80** and **8443 → 443**.

## AWS

Keys: `sensitive/aws/credentials` and `sensitive/aws/cli.conf`. Knobs: [`../clusters/aws/k8s-aws/config.yaml`](../clusters/aws/k8s-aws/config.yaml).

```bash
./scripts/infra/up.sh aws k8s-aws
# Kubernetes is independent: ./scripts/infra/kubeadm/up.sh aws k8s-aws
```

Checklist (compute): [terraform/environments/ec2/STEPS.md](terraform/environments/ec2/STEPS.md). Kubernetes: [docs/infra/kubeadm.md](../docs/infra/kubeadm.md). Teardown VMs: `./scripts/infra/down.sh aws k8s-aws -y`

## OpenStack

Auth: `sensitive/openstack/clouds.yaml`. Knobs: cluster YAML (`image_name`, `node_flavor`, existing `network_name`, `octavia_lbs`). Example: [`../clusters/openstack/k8s-ocp/config.yaml`](../clusters/openstack/k8s-ocp/config.yaml).

```bash
./scripts/infra/up.sh openstack k8s-ocp
# Kubernetes is independent: ./scripts/infra/kubeadm/up.sh openstack k8s-ocp
```

Terraform **looks up** the Neutron network; it does not create or destroy it.

Checklist: [terraform/environments/openstack/STEPS.md](terraform/environments/openstack/STEPS.md). Debug CLI: [docs/infra/openstack.md](../docs/infra/openstack.md#cli-cheat-sheet-debug). Teardown: `./scripts/infra/down.sh openstack k8s-ocp -y`

S3 backup of `sensitive/` is offered by `./scripts/infra/up.sh` and `./scripts/infra/down.sh` (not by the per-cloud scripts).

Guides: [docs/infra/](../docs/infra/)
