# sensitive/ — secrets and Terraform outputs (S3, not git)

This folder is **gitignored**. Back it up with `./scripts/sensitive/s3.sh`.

```text
sensitive/
├── aws/
│   ├── credentials, cli.conf
│   └── k8s-aws/           # ssh.pem, cluster.env, kubeconfig, tfstate
├── openstack/
│   ├── clouds.yaml
│   └── k8s-ocp/
└── kind/                    # kubeconfig + terraform.tfstate
```

Cluster YAML stays in [`clusters/`](../clusters/README.md) and is committed.

```bash
# set bucket in clusters/backup.yaml
./scripts/sensitive/s3.sh init
./scripts/sensitive/s3.sh push
./scripts/sensitive/s3.sh pull    # new laptop (AWS keys first)
```

Do not paste PEM, kubeconfig, or access keys into chat.
