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

**Done when (compute):** SSH to a node works. Kubernetes Ready is a separate step ([kubeadm.md](./kubeadm.md)).

---

## CLI cheat sheet (debug)

Auth is `sensitive/openstack/clouds.yaml` (gitignored). Do not print secrets. The CLI on this cloud is often slow (30–150s).

```bash
export OS_CLIENT_CONFIG_FILE=$PWD/sensitive/openstack/clouds.yaml OS_CLOUD=openstack
# OS_CLOUD must match cloud: in clusters/openstack/<id>/config.yaml
```

**Who / quota**

```bash
openstack token issue -f value -c project_id -c user_id -c expires
openstack quota show -f yaml
openstack loadbalancer quota show
```

**Compute + Neutron (nodes)**

```bash
openstack server list
openstack server show arselvan-k8s-cp
openstack port list --server arselvan-k8s-cp
openstack security group show arselvan-k8s-sg
openstack security group rule list arselvan-k8s-sg
openstack network show tenant-internal-direct-net
openstack subnet list --network tenant-internal-direct-net
openstack subnet show tenant-internal-direct-subnet7
```

**Octavia — provisioning vs operating**

`provisioning_status=ACTIVE` means the object exists. `operating_status=ERROR` usually means **health monitors cannot TCP to members** (nothing listening on the NodePorts, or SG/path from amphora to the nodes).

```bash
openstack loadbalancer list
openstack loadbalancer show arselvan-k8s-ingress
openstack loadbalancer listener list --loadbalancer arselvan-k8s-ingress
openstack loadbalancer pool list --loadbalancer arselvan-k8s-ingress
openstack loadbalancer member list --pool arselvan-k8s-ingress-http
openstack loadbalancer healthmonitor list
openstack loadbalancer amphora list --loadbalancer arselvan-k8s-ingress
openstack loadbalancer stats show arselvan-k8s-ingress
openstack loadbalancer status show arselvan-k8s-ingress
```

Replace `arselvan-k8s-ingress` with `arselvan-k8s-envoy` (or `openstack loadbalancer list -f value -c name`). Member `operating_status` `ONLINE` vs `ERROR`/`OFFLINE` is the health check.

**Match Terraform NodePorts on the cluster**

```bash
export KUBECONFIG=$PWD/sensitive/openstack/arselvan-k8s/kubeconfig
kubectl get svc -A
# NodePort Services should show 30080:80 / 30443:443 (ingress) etc.

ssh -i sensitive/openstack/arselvan-k8s/ssh.pem ubuntu@$(grep CONTROL_PLANE_HOST= sensitive/openstack/arselvan-k8s/cluster.env | cut -d= -f2) \
  'ss -lnt | grep -E ":30080|:30443|:30090|:30453" || echo "no nodeports listening"'
```

**Hit the VIP** (from a host that can reach the tenant net; VIP is in `cluster.env`)

```bash
set -a && source sensitive/openstack/arselvan-k8s/cluster.env && set +a
curl -sv --connect-timeout 5 "http://${INGRESS_LB_VIP}/" -o /dev/null
curl -skv --connect-timeout 5 "https://${INGRESS_LB_VIP}/" -o /dev/null
```

**CodeGuard:** never commit `clouds.yaml` or paste `application_credential_secret` into chat.
