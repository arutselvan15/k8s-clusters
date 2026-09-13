# k8s-clusters

Build and tear down Kubernetes clusters: **Kind** (laptop), **AWS EC2**, or **OpenStack**. Cloud VMs get Kubernetes from **kubeadm** (not EKS, not managed OpenStack Kubernetes).

Committed knobs live in [`clusters/`](clusters/README.md). Keys, kubeconfigs, SSH PEMs, and Terraform state live in [`sensitive/`](sensitive/README.md) (gitignored; optional S3 backup).

| Path | Role |
|------|------|
| [clusters/](clusters/README.md) | Cluster YAML (`clusters/<platform>/<id>/config.yaml`) |
| [sensitive/](sensitive/README.md) | Credentials and generated outputs |
| [infra/](infra/README.md) | Terraform (Kind / EC2 / OpenStack) |
| [scripts/](scripts/README.md) | `up.sh` / `down.sh` / kubeadm / S3 |
| [docs/](docs/README.md) | Guides |

CLI id = directory name under `clusters/<platform>/`. If a platform has exactly one config, you can omit the id.

## Prerequisites

```bash
brew install kind kubectl terraform
```

AWS also needs the AWS CLI (`brew install awscli`). OpenStack Terraform reads `sensitive/openstack/clouds.yaml` (no extra CLI required).

Copy examples, then fill them locally (never commit the filled files):

```bash
cp sensitive/aws/credentials.example sensitive/aws/credentials
cp sensitive/aws/cli.conf.example sensitive/aws/cli.conf
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/aws/credentials sensitive/openstack/clouds.yaml
```

## Kind

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/k8s-kind/kubeconfig
kubectl get nodes
```

Config: [`clusters/kind/k8s-kind/config.yaml`](clusters/kind/k8s-kind/config.yaml). Host ports **8080 → 80** and **8443 → 443**.

Teardown: `./scripts/infra/down.sh kind` (deletes the cluster and `sensitive/kind/<cluster_name>/`).

## AWS EC2 + kubeadm

```bash
./scripts/infra/up.sh aws k8s-aws
./scripts/infra/kubeadm/up.sh aws k8s-aws
source scripts/lib/kubeconfig-setup.sh sensitive/aws/k8s-aws/kubeconfig
kubectl get nodes
```

Terraform creates VMs only. kubeadm installs Kubernetes. Knobs: [`clusters/aws/k8s-aws/config.yaml`](clusters/aws/k8s-aws/config.yaml). Detail: [docs/infra/aws.md](docs/infra/aws.md), [aws-kubeadm.md](docs/infra/aws-kubeadm.md).

Teardown: `./scripts/infra/down.sh aws k8s-aws -y`

## OpenStack + kubeadm

```bash
./scripts/infra/up.sh openstack k8s-ocp
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
kubectl get nodes
```

Terraform looks up an **existing** Neutron network (`network_name` in config). It does not create or destroy that network. Knobs: [`clusters/openstack/k8s-ocp/config.yaml`](clusters/openstack/k8s-ocp/config.yaml). Detail: [docs/infra/openstack.md](docs/infra/openstack.md).

Teardown: `./scripts/infra/down.sh openstack k8s-ocp -y`

## S3 backup of `sensitive/`

Bucket name is in [`clusters/backup.yaml`](clusters/backup.yaml) (not keys). After `up.sh` / `down.sh` / kubeadm up or reset, the script asks to push with prune.

```bash
./scripts/sensitive/s3.sh init
./scripts/sensitive/s3.sh push --prune
./scripts/sensitive/s3.sh pull    # new laptop (AWS keys first)
```

Non-interactive: `K8S_PLAT_S3_BACKUP=yes` or `no`.
