# Day 0 — OpenStack

Same split as AWS: **Terraform = VMs**, **kubeadm = Kubernetes**. After nodes are Ready, [bootstrap](../bootstrap/) and [gitops](../gitops/) are **common**.

Checklist: [infra/terraform/environments/openstack/STEPS.md](../../infra/terraform/environments/openstack/STEPS.md).

```bash
cp config/openstack/clouds.yaml.example config/openstack/clouds.yaml
cp config/openstack/clusters/default.yaml.example config/openstack/clusters/default.yaml
chmod 600 config/openstack/clouds.yaml
# set cloud, image_name, node_flavor, network_name (existing Neutron net)
./scripts/infra/up.sh openstack default
./scripts/infra/kubeadm/up.sh default
source scripts/lib/kubeconfig-setup.sh clusters/k8s-os/kubeconfig
```

`cloud:` in `config/openstack/clusters/default.yaml` must match a key under `clouds:` in `clouds.yaml`. Application credentials are already project-scoped — do not add `project_name` in auth unless your cloud requires it.

Terraform **looks up** `network_name` (for example `tenant-internal-direct-net`). It does **not** create a network, subnet, router, or floating IP. SSH uses the instance **fixed IP**; your laptop must be able to reach that tenant net (campus/VPN).

**Tear down:** `./scripts/infra/down.sh openstack default -y` deletes VMs, ports, security group, and keypair. **It does not delete the existing network.**

Same kubeadm remote scripts as AWS. Reset Kubernetes only: `./scripts/infra/kubeadm/reset.sh default`.

**CodeGuard:** never commit `clouds.yaml` or paste `application_credential_secret` into chat.

**Next:** [bootstrap](../bootstrap/) then [gitops](../gitops/) (same commands as Kind/AWS). Ingress `LoadBalancer` vs Kind `hostPort` is a values overlay, not a separate GitOps stack.
