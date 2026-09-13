# OpenStack (compute)

**This doc is VMs only.** Terraform creates instances on an **existing** Neutron network. It does **not** install Kubernetes.

Kubernetes is a **separate, optional** step — same kubeadm scripts as AWS: [kubeadm.md](./kubeadm.md).

```bash
mkdir -p sensitive/openstack
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/openstack/clouds.yaml
# set image_name, node_flavor, network_name in clusters/openstack/k8s-ocp/config.yaml
./scripts/infra/up.sh openstack k8s-ocp
```

Done when you can SSH to a node. Later, independent of Terraform:

```bash
./scripts/infra/kubeadm/up.sh openstack k8s-ocp
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/k8s-ocp/kubeconfig
```

`cloud:` in `clusters/openstack/k8s-ocp/config.yaml` must match a key under `clouds:` in `clouds.yaml`. Application credentials are already project-scoped — do not add `project_name` in auth unless your cloud requires it.

Terraform **looks up** `network_name` (for example `tenant-internal-direct-net`). It does **not** create a network, subnet, router, or floating IP. SSH uses the instance **fixed IP**; your laptop must be able to reach that tenant net (campus/VPN).

Set `octavia_lbs` in the cluster YAML: each list item is one Octavia VIP (TCP 80/443). Length of the list is N LBs; OpenStack load-balancer quota still caps how many can exist. Name one `ingress` to match k8s-apps NodePorts. VIPs land in `cluster.env` as `OCTAVIA_LB_VIP_<NAME>` (and `INGRESS_LB_VIP` if that name exists). Empty list skips Octavia. Do not also create these LBs with OCCM.

**Tear down compute:** `./scripts/infra/down.sh openstack k8s-ocp -y` deletes VMs, ports, security group, keypair, and the Octavia LB if it was enabled. **It does not delete the existing network.** Kubernetes only (keep VMs): `./scripts/infra/kubeadm/reset.sh openstack k8s-ocp`.

**CodeGuard:** never commit `clouds.yaml` or paste `application_credential_secret` into chat.

**Done when (compute):** SSH to a node works. Kubernetes Ready is a separate step ([kubeadm.md](./kubeadm.md)).
