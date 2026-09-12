# clusters/ — committed inputs

One directory per cluster. **Do not put keys, PEM, kubeconfig, or Terraform state here.** Those go in [`sensitive/`](../sensitive/README.md).

```text
clusters/
├── backup.yaml                      # S3 bucket name for ./scripts/sensitive/s3.sh
├── aws/
│   └── k8s-aws/config.yaml       # ./scripts/infra/up.sh aws k8s-aws
└── openstack/
    ├── clouds.yaml.example          # copy once → sensitive/openstack/clouds.yaml
    └── k8s-ocp/config.yaml       # ./scripts/infra/up.sh openstack k8s-ocp
```

CLI id = directory name. `cluster_name` in the YAML should match. Nodes: `{cluster_name}-cp`, `{cluster_name}-wk-1`, `{cluster_name}-wk-2`, …. Outputs: `sensitive/<aws|openstack>/<cluster_name>/`.

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
| `aws/*/config.yaml` | yes | Terraform + kubeadm knobs |
| `openstack/*/config.yaml` | yes | same (`cloud:` must match a key in `clouds.yaml`) |
| `backup.yaml` | yes | `./scripts/sensitive/s3.sh` bucket name only; offer after cluster build |
| `sensitive/aws/credentials` | no | AWS CLI / Terraform |
| `sensitive/openstack/clouds.yaml` | no | OpenStack provider |

Day 0: [infra/README.md](../infra/README.md)
