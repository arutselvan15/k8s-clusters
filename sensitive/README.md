# sensitive/ — secrets and Terraform outputs (S3, not git)

This folder is **gitignored**. Back it up with `./scripts/sensitive/s3.sh`.

```text
sensitive/
├── aws/
│   ├── s3.credentials, cli.conf
│   └── k8s-aws/           # ssh.pem, cluster.env, kubeconfig, tfstate
├── openstack/
│   ├── clouds.yaml            # Keystone auth
│   ├── s3.credentials         # object-store S3 keys (copy from *.example)
│   └── k8s-ocp/
├── openshift/
│   ├── pull-secret.json   # console.redhat.com, shared by every OpenShift cluster
│   ├── arselvan-ocp-alln/ # ssh.pem, cluster.env, tfstate, install-config.yaml,
│   │                      # manifests/, kubeconfig, kubeadmin-password, phases/
│   └── fms-lab-rtp/       # same, one directory per OpenShift cluster
└── kind/
    └── k8s-kind/          # kubeconfig, terraform.tfstate (removed by down.sh)
```

Cluster YAML stays in [`clusters/`](../clusters/README.md) and is committed.

```bash
# configure backup targets in clusters/backup.yaml
./scripts/sensitive/s3.sh init
./scripts/sensitive/s3.sh push --prune
./scripts/sensitive/s3.sh pull    # default target; new laptop (AWS keys first)

# OpenStack COS uses the same target fields. Fill bucket and endpoint, then:
cp sensitive/openstack/s3.credentials.example sensitive/openstack/s3.credentials
chmod 600 sensitive/openstack/s3.credentials
./scripts/sensitive/s3.sh push --target openstack-s3 --prune
./scripts/sensitive/s3.sh pull --target openstack-s3
```

The selected target is, in order: `--target`, `K8S_PLAT_S3_TARGET`, then the `default` target in `clusters/backup.yaml`. After `./scripts/infra/up.sh`, `./scripts/infra/down.sh`, `./scripts/infra/kubeadm/up.sh`, or `kubeadm/reset.sh`, the script asks **Push to S3 with prune? [y/N]**. `yes` runs `push --prune` against that selected target; `no` skips. Non-interactive: `K8S_PLAT_S3_BACKUP=yes` or `no`.

Do not paste PEM, kubeconfig, or access keys into chat.
