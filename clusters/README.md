# clusters/ — committed inputs

One directory per cluster. **Do not put keys, PEM, kubeconfig, or Terraform state here.** Those go in [`sensitive/`](../sensitive/README.md).

```text
clusters/
├── backup.yaml                      # S3 targets (AWS and OpenStack COS, same fields)
├── kind/
│   └── k8s-kind/config.yaml      # ./scripts/infra/up.sh kind   (or kind k8s-kind)
├── aws/
│   └── k8s-aws/config.yaml       # ./scripts/infra/up.sh aws k8s-aws
├── openstack/
│   └── k8s-ocp/config.yaml       # ./scripts/infra/up.sh openstack k8s-ocp
└── openshift/
    ├── arselvan-ocp-alln/config.yaml      # ./scripts/infra/openshift/ocp.sh arselvan-ocp-alln
    └── fms-lab-rtp/config.yaml            # ./scripts/infra/openshift/ocp.sh fms-lab-rtp
```

OpenStack clouds file: copy [`sensitive/openstack/clouds.yaml.example`](../sensitive/openstack/clouds.yaml.example) → `sensitive/openstack/clouds.yaml`.

CLI id = directory name. `cluster_name` in the YAML should match. AWS/OpenStack nodes: `{cluster_name}-cp`, `{cluster_name}-wk-N`. Outputs: `sensitive/<platform>/<cluster_name>/`.

## Add a cluster

```bash
cp -R clusters/aws/k8s-aws clusters/aws/k8s-aws-2
# edit cluster_name (and knobs) in clusters/aws/k8s-aws-2/config.yaml
./scripts/infra/up.sh aws k8s-aws-2
```

If a platform has more than one cluster dir, pass the id (`./scripts/infra/up.sh aws k8s-aws`).

## What lives where

| File | Git? | Used by |
|------|------|---------|
| `kind/*/config.yaml` | yes | Kind Terraform knobs (`cluster_name`, node counts, version) |
| `aws/*/config.yaml` | yes | Terraform + kubeadm knobs |
| `openstack/*/config.yaml` | yes | same (`cloud:` must match a key in `clouds.yaml`) |
| `backup.yaml` | yes | S3 targets, same fields per store; `default` or `--target` switches |
| `sensitive/aws/s3.credentials` | no | AWS CLI / Terraform |
| `sensitive/openstack/clouds.yaml` | no | OpenStack Keystone auth |
| `sensitive/openstack/s3.credentials` | no | OpenStack object-store S3 keys |

See [infra/README.md](../infra/README.md)
