# OpenStack

Same split as AWS: **Terraform = VMs**, **kubeadm = Kubernetes**.

Checklist: [infra/terraform/environments/openstack/STEPS.md](../../infra/terraform/environments/openstack/STEPS.md).

```bash
mkdir -p sensitive/openstack
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/openstack/clouds.yaml
# set image_name, node_flavor, network_name in clusters/openstack/k8s-ocp/config.yaml
./scripts/infra/up.sh openstack k8s-ocp
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
```

`cloud:` in `clusters/openstack/k8s-ocp/config.yaml` must match a key under `clouds:` in `clouds.yaml`. Application credentials are already project-scoped — do not add `project_name` in auth unless your cloud requires it.

Terraform **looks up** `network_name` (for example `tenant-internal-direct-net`). It does **not** create a network, subnet, router, or floating IP. SSH uses the instance **fixed IP**; your laptop must be able to reach that tenant net (campus/VPN).

**Tear down:** `./scripts/infra/down.sh openstack k8s-ocp -y` deletes VMs, ports, security group, and keypair. **It does not delete the existing network.**

Same kubeadm remote scripts as AWS. Reset Kubernetes only: `./scripts/infra/kubeadm/reset.sh openstack k8s-ocp`.

**CodeGuard:** never commit `clouds.yaml` or paste `application_credential_secret` into chat.

**Done when:** `kubectl get nodes` works. SSH uses the instance **fixed IP**; your laptop must reach that tenant net.
