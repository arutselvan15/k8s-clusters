# Docs

Tools and secrets: [prerequisites.md](./prerequisites.md). Per-cloud guides: [infra/](./infra/).

```text
docs/
├── README.md              # this file — layout, commands, backup
├── prerequisites.md
└── infra/
    ├── kind.md
    ├── aws.md
    ├── kubeadm.md
    ├── openstack.md
    └── openshift.md       # OpenShift 4.22 + selectable CNI, phase by phase
```

## Layout

| Path | Git? | Contents |
|------|------|----------|
| `clusters/<platform>/<id>/config.yaml` | yes | Knobs (`cluster_name`, node counts, CIDRs, flavors) |
| `clusters/backup.yaml` | yes | S3 targets, same fields for AWS and OpenStack COS (not keys) |
| `sensitive/<platform>/` | no | Cloud credentials |
| `sensitive/<platform>/<cluster_name>/` | no | kubeconfig, SSH PEM, `cluster.env`, Terraform state |

CLI id = directory name under `clusters/<platform>/`. If that platform has exactly one config, you can omit the id.

Terraform creates Kind clusters or cloud VMs. On AWS and OpenStack, **compute** (`./scripts/infra/up.sh`) and **Kubernetes** (`./scripts/infra/kubeadm/up.sh`) are independent — see [infra/](./infra/). OpenStack Terraform **looks up** an existing Neutron network; destroy does not delete it.

## Commands

```bash
# Kind
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
kubectl get nodes

# AWS — VMs (compute only)
./scripts/infra/up.sh aws k8s-aws
# Kubernetes (independent): ./scripts/infra/kubeadm/up.sh aws k8s-aws

# OpenStack — VMs (compute only)
./scripts/infra/up.sh openstack k8s-ocp
# Kubernetes (independent): ./scripts/infra/kubeadm/up.sh openstack k8s-ocp
```

Configs: [`clusters/kind/k8s-kind/config.yaml`](../clusters/kind/k8s-kind/config.yaml), [`clusters/aws/k8s-aws/config.yaml`](../clusters/aws/k8s-aws/config.yaml), [`clusters/openstack/k8s-ocp/config.yaml`](../clusters/openstack/k8s-ocp/config.yaml).

Kind maps host ports **8080 → 80** and **8443 → 443**.

## Teardown

```bash
./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
./scripts/infra/down.sh openstack k8s-ocp -y
```

Kind `down.sh` removes the cluster and `sensitive/kind/<cluster_name>/`. AWS/OpenStack `down.sh` destroys VMs; it does not delete OpenStack’s existing Neutron network. Cloud keys under `sensitive/aws/` and `sensitive/openstack/` stay.

## S3 backup of `sensitive/`

AWS keys stay in `sensitive/aws/s3.credentials`. OpenStack object-store keys stay in `sensitive/openstack/s3.credentials` (copy [`s3.credentials.example`](../sensitive/openstack/s3.credentials.example)). Named backup targets and the default target are in [`clusters/backup.yaml`](../clusters/backup.yaml). After `up.sh` / `down.sh` / kubeadm up or reset, the script asks to push with prune.

```bash
./scripts/sensitive/s3.sh init
./scripts/sensitive/s3.sh push --prune
./scripts/sensitive/s3.sh pull    # new laptop (AWS keys first)

# Same fields as the AWS target. Fill bucket and endpoint, then:
./scripts/sensitive/s3.sh push --target openstack-s3 --prune
```

Selection precedence is `--target`, `K8S_PLAT_S3_TARGET`, then the configured default. Non-interactive: `K8S_PLAT_S3_BACKUP=yes` or `no`. Folder map: [sensitive/README.md](../sensitive/README.md).
