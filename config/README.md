# Config — inputs (gitignored local copies)

Lab **inputs** live here. Generated **outputs** live in [`clusters/<cluster_name>/`](../clusters/README.md).

You can keep **many** cluster YAML files. Each `up` / `kubeadm` run uses **exactly one** (the argument).

```text
config/
├── aws/
│   ├── credentials              # AWS keys (never commit) — shared
│   ├── cli.conf                 # AWS CLI: region, output — shared
│   └── clusters/
│       ├── default.yaml.example
│       ├── default.yaml         # gitignored; first-run copy
│       └── lab.yaml             # another cluster; pass `lab` at build
└── openstack/
    ├── clouds.yaml              # Keystone auth (never commit) — shared
    └── clusters/
        ├── default.yaml.example
        └── default.yaml

clusters/<cluster_name>/         # scripts write these
├── kubeconfig
├── ssh.pem
├── cluster.env
├── terraform.tfstate
└── known_hosts
```

```bash
cp config/aws/credentials.example config/aws/credentials && chmod 600 config/aws/credentials
cp config/aws/cli.conf.example config/aws/cli.conf
cp config/aws/clusters/default.yaml.example config/aws/clusters/default.yaml

cp config/openstack/clouds.yaml.example config/openstack/clouds.yaml && chmod 600 config/openstack/clouds.yaml
cp config/openstack/clusters/default.yaml.example config/openstack/clusters/default.yaml

./scripts/infra/up.sh aws default
./scripts/infra/kubeadm/up.sh default

./scripts/infra/up.sh aws lab          # config/aws/clusters/lab.yaml
./scripts/infra/kubeadm/up.sh lab
```

In each cluster YAML set `cluster_name`, `control_plane_prefix`, and `worker_prefix`. Cloud objects are named `{cluster_name}-{control_plane_prefix}` and `{cluster_name}-{worker_prefix}-N`. Outputs go to `clusters/<cluster_name>/`. Use a unique `cluster_name` per live cluster.

Do not mix AWS keys into cluster YAML. Do not put PEM files or kubeconfig under `config/`.
