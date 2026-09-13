# Platform lifecycle

Cluster build is **k8s-clusters**. Bootstrap and GitOps are **[k8s-gitops](../../k8s-gitops)**.

```text
Day 0  this repo     kind · aws (ec2) · openstack
Day 1  k8s-gitops    Argo CD + Git repo Secrets
Day 2  k8s-gitops    Apps from Git (keeps growing)
```

Index: [README.md](./README.md) · Resume: [continue.md](./continue.md)

| Phase | Question | Where |
|-------|----------|--------|
| **Day 0** | Is there a cluster? | `scripts/infra/up.sh`, kubeadm, Terraform |
| **Day 1** | Can Git manage the cluster? | `k8s-gitops/bootstrap/` |
| **Day 2** | What runs on the cluster? | `k8s-gitops/gitops/` |

Kubeconfig after Day 0: `sensitive/<platform>/<cluster_name>/kubeconfig`.

## Environments (Day 0)

| Environment | Dispatcher | After Terraform | Kubeconfig |
|-------------|------------|-----------------|------------|
| `kind` | `./scripts/infra/up.sh kind` | Cluster is ready | `sensitive/kind/<cluster_name>/kubeconfig` |
| `ec2` | `./scripts/infra/up.sh aws k8s-aws` | `./scripts/infra/kubeadm/up.sh aws k8s-aws` | `sensitive/aws/<cluster_name>/kubeconfig` |
| `openstack` | `./scripts/infra/up.sh openstack k8s-ocp` | `./scripts/infra/kubeadm/up.sh openstack k8s-ocp` | `sensitive/openstack/<cluster_name>/kubeconfig` |

```bash
./scripts/infra/up.sh kind
source scripts/lib/kubeconfig-setup.sh sensitive/kind/<cluster_name>/kubeconfig

cd ../k8s-gitops
./bootstrap/bootstrap.sh
git push origin main
./scripts/gitops/start.sh dev
```

Teardown Day 0 only (GitOps stays in the gitops repo). After destroy, the dispatcher prompts to push `sensitive/` to S3 with prune:

```bash
./scripts/infra/down.sh kind
./scripts/infra/down.sh aws k8s-aws -y
./scripts/infra/down.sh openstack k8s-ocp -y
```

OpenStack Terraform **looks up** `network_name`; destroy does **not** delete that network.

New platform apps: add them in **k8s-gitops**, not here.
