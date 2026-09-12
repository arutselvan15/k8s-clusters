# k8s-platform

Reusable platform: **Day 0 infra** (Kind, AWS EC2, or OpenStack) · **Day 1 bootstrap** (common) · **Day 2 GitOps** (common, grows with apps).

After a cluster exists, only the kubeconfig path changes. Do not fork bootstrap or GitOps per cloud.

```text
scripts/
  lib/                 # kubeconfig, require-tools, cloud env
  infra/               # Day 0 — kind | aws | openstack + kubeadm
  bootstrap/up.sh      # Kind convenience: Day 0 + Day 1
  gitops/              # Day 2 — start.sh, chainsaw.sh
```

Details: [scripts/README.md](scripts/README.md) · Model: [docs/platform-lifecycle.md](docs/platform-lifecycle.md)

---

## Quick start (Kind)

```bash
chmod +x scripts/infra/*.sh scripts/infra/*/*.sh scripts/infra/kubeadm/remote/*.sh \
  scripts/bootstrap/*.sh scripts/gitops/*.sh scripts/lib/*.sh \
  bootstrap/bootstrap.sh bootstrap/argocd/install.sh
```

Optional: copy [`bootstrap/env/bootstrap.env.example`](bootstrap/env/bootstrap.env.example) → `bootstrap.env`.

```bash
./scripts/bootstrap/up.sh

git push origin main

source scripts/lib/kubeconfig-setup.sh .kube/kind-dev.yaml
./scripts/gitops/start.sh dev
```

When **`argocd-server-tls`** is Ready, run **`./bootstrap/bootstrap.sh dev`** again → **https://argocd.dev:8443** (`127.0.0.1 argocd.dev` in `/etc/hosts`).

Day 0 only: `./scripts/infra/up.sh kind`

---

## Day 0 — AWS or OpenStack (VMs, then kubeadm)

```bash
cp .aws/credentials.example .aws/credentials && chmod 600 .aws/credentials
cp .aws/config.example .aws/config
./scripts/infra/up.sh aws
./scripts/infra/kubeadm/up.sh
source scripts/lib/kubeconfig-setup.sh .kube/aws-dev.yaml

cp .openstack/clouds.yaml.example .openstack/clouds.yaml && chmod 600 .openstack/clouds.yaml
cp .openstack/config.example .openstack/config
./scripts/infra/up.sh openstack
./scripts/infra/kubeadm/up.sh -i .kube/os-inventory.env
source scripts/lib/kubeconfig-setup.sh .kube/os-dev.yaml
```

Checklists: [ec2/STEPS.md](infra/terraform/environments/ec2/STEPS.md), [openstack/STEPS.md](infra/terraform/environments/openstack/STEPS.md).

---

## Teardown

```bash
./scripts/infra/down.sh kind
./scripts/infra/down.sh aws -y
./scripts/infra/down.sh openstack -y   # does not delete the existing tenant network
```

---

## Documentation

Start at **[docs/README.md](./docs/README.md)**. Resume with [docs/continue.md](./docs/continue.md).

| Topic | Doc |
|--------|-----|
| Reusable model | [docs/platform-lifecycle.md](./docs/platform-lifecycle.md) |
| Day 0 — Kind / AWS / OpenStack | [docs/infra/](./docs/infra/) |
| Day 1 — bootstrap (common) | [docs/bootstrap/](./docs/bootstrap/) |
| Day 2 — GitOps apps (common) | [docs/gitops/](./docs/gitops/) |
| Scripts | [scripts/README.md](./scripts/README.md) |
| Code runbooks | [infra/README.md](./infra/README.md) · [bootstrap/README.md](./bootstrap/README.md) · [gitops/README.md](./gitops/README.md) |
