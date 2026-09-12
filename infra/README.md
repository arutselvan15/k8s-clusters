# Day 0 — Infrastructure

Provision a Kubernetes **API**. This tree is Terraform only. Argo CD and apps are [bootstrap](../bootstrap/README.md) and [gitops](../gitops/README.md).

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

Knobs: [`../clusters/kind/dev/config.yaml`](../clusters/kind/dev/config.yaml) (`cluster_name: dev`). `./scripts/infra/up.sh kind` is the same as `./scripts/infra/up.sh kind dev`.

Day 0 + Day 1: `./scripts/bootstrap/up.sh`. Teardown: `./scripts/infra/down.sh kind`

Host ports **8080 → 80** and **8443 → 443**. Cluster name is **`dev`**.

## AWS

Keys: `sensitive/aws/credentials` and `sensitive/aws/cli.conf`. Knobs: [`../clusters/aws/k8s-aws/config.yaml`](../clusters/aws/k8s-aws/config.yaml).

```bash
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
```

Checklist: [terraform/environments/ec2/STEPS.md](terraform/environments/ec2/STEPS.md). Teardown: `./scripts/infra/down.sh aws k8s-aws -y`

## OpenStack

Auth: `sensitive/openstack/clouds.yaml`. Knobs: [`../clusters/openstack/k8s-ocp/config.yaml`](../clusters/openstack/k8s-ocp/config.yaml) (`image_name`, `node_flavor`, existing `network_name`).

```bash
./scripts/infra/up.sh openstack k8s-ocp
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
```

Terraform **looks up** the Neutron network; it does not create or destroy it.

Checklist: [terraform/environments/openstack/STEPS.md](terraform/environments/openstack/STEPS.md). Teardown: `./scripts/infra/down.sh openstack k8s-ocp -y`

kubeadm is **not** Terraform. Same scripts on AWS and OpenStack after Day 0 writes `cluster.env`.

S3 backup of `sensitive/` is offered by `./scripts/infra/up.sh` and `./scripts/infra/down.sh` (not by the per-cloud scripts).

## Next

```bash
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig   # or aws / openstack path above
./bootstrap/bootstrap.sh
```

Guides: [docs/infra/](../docs/infra/)
