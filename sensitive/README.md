# sensitive/ — secrets and Terraform outputs (S3, not git)

This folder is **gitignored**. Back it up with `./scripts/sensitive/s3.sh`.

Argo CD repo Secrets live in **[k8s-gitops](../../k8s-gitops)/sensitive/bootstrap/**, not here.

```text
sensitive/
├── aws/
│   ├── credentials, cli.conf
│   └── k8s-aws/           # ssh.pem, cluster.env, kubeconfig, tfstate
├── openstack/
│   ├── clouds.yaml
│   └── k8s-ocp/
└── kind/
    └── k8s-kind/          # kubeconfig, terraform.tfstate (removed by down.sh)
```

Cluster YAML stays in [`clusters/`](../clusters/README.md) and is committed.

```bash
# set bucket in clusters/backup.yaml
./scripts/sensitive/s3.sh init
./scripts/sensitive/s3.sh push --prune
./scripts/sensitive/s3.sh pull    # new laptop (AWS keys first)
```

After `./scripts/infra/up.sh`, `./scripts/infra/down.sh`, `./scripts/infra/kubeadm/up.sh`, or `kubeadm/reset.sh`, the script asks **Push to S3 with prune? [y/N]**. `yes` runs `push --prune`; `no` skips. Non-interactive: `K8S_PLAT_S3_BACKUP=yes` or `no`.

Do not paste PEM, kubeconfig, or access keys into chat.
