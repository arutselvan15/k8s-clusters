# OpenStack

Terraform creates VMs on an **existing** Neutron network. It does not create a network, subnet, router, or floating IP, and it does not install Kubernetes.

Kubernetes is a separate step using the shared kubeadm scripts ([kubeadm.md](./kubeadm.md)) — the same ones AWS uses. The cloud only decides how you got SSH and `cluster.env`.

| Layer | Command | Owns |
|-------|---------|------|
| Compute | `./scripts/infra/up.sh openstack <id>` | VMs, ports, security group, keypair, Octavia LBs |
| Kubernetes | `./scripts/infra/kubeadm/up.sh openstack <id>` | kubeadm, CNI, kubeconfig |
| Cloud controller (optional) | `./scripts/infra/openstack/occm.sh <id>` | `type: LoadBalancer` Services |

## Quick start

```bash
mkdir -p sensitive/openstack
cp sensitive/openstack/clouds.yaml.example sensitive/openstack/clouds.yaml
chmod 600 sensitive/openstack/clouds.yaml
# set image_name, node_flavor, network_name in clusters/openstack/<id>/config.yaml

./scripts/infra/up.sh openstack <id>              # VMs. Done when SSH works.
./scripts/infra/kubeadm/up.sh openstack <id>      # Kubernetes. Done when nodes are Ready.
source scripts/lib/kubeconfig-setup.sh sensitive/openstack/<id>/kubeconfig
```

SSH uses the instance **fixed IP**, so your laptop must be able to reach that tenant network (campus or VPN).

## Cluster config reference

One file per cluster: `clusters/openstack/<id>/config.yaml`. Everything marked required must be present — the scripts fail fast on a missing key rather than guessing. "Optional" keys can be left out entirely.

### Top level

| Key | Required | Details |
|-----|----------|---------|
| `cluster_name` | optional | Names the nodes (`<name>-cp`, `<name>-wk-N`) and the output directory `sensitive/openstack/<name>/`. Defaults to the directory id. Letters, digits, `.`, `_`, `-`. |
| `cloud` | **required** | Must match a key under `clouds:` in `sensitive/openstack/clouds.yaml`. Exported as `OS_CLOUD`. |

Application credentials are already project-scoped — do not add `project_name` under `auth` unless your cloud requires it.

### `terraform:`

| Key | Required | Details |
|-----|----------|---------|
| `image_name` | **required** | Glance image name. Horizon: Compute → Images. |
| `node_flavor` | **required** | Nova flavor for control plane and workers. |
| `network_name` | **required** | Existing Neutron network, looked up not created. |
| `worker_nodes` | **required** | Worker count. `0` gives a control-plane-only cluster. |
| `admin_cidr` | **required** | Who may reach SSH and the Kubernetes API. Tighten to `YOUR.IP/32` when you leave the lab default. |
| `ssh_user` | **required** | SSH user baked into the image (`ubuntu` for the Ubuntu images). |
| `ssh_port` | **required** | SSH ingress port, normally `22`. |
| `kubernetes_api_port` | **required** | API ingress port, normally `6443`. |
| `root_volume_gb` | **required** | Boot volume size. Nodes boot from volume, so flavors with no local disk still work. |
| `volume_delete_on_termination` | **required** | Delete the boot volume with the instance. `false` leaves volumes behind that count against quota. |
| `image_most_recent` | **required** | When several images share `image_name`, take the newest. |
| `ssh_key_algorithm` | **required** | `ED25519` or `RSA`. The private key is generated into `sensitive/openstack/<name>/ssh.pem`. |
| `availability_zone` | **required** | The key must exist; an empty value lets the Nova scheduler choose. |
| `subnet_name` | conditional | A specific subnet on `network_name`. Required when `octavia_lbs` is non-empty or OCCM is enabled, because the tenant network has several subnets. |
| `octavia_lbs` | optional | Terraform-managed load balancers. Empty or absent creates none. See below. |
| `octavia_lb_flavor` | optional | Octavia flavor for every LB in the list. Defaults to `Octavia_2vCPUx2GB`; empty uses the cloud default. |

### `kubeadm:`

| Key | Required | Details |
|-----|----------|---------|
| `kubernetes_version` | **required** | Minor version pinned on every node, e.g. `"1.32"`. Quote it so YAML keeps it a string. |
| `pod_cidr` | **required** | Pod network. `192.168.0.0/16` avoids overlapping the AWS VPC range. |
| `cni` | optional | `calico` (default) or `cilium`. `cilium` also skips the kube-proxy addon, so like `cloud_provider` it is fixed at `kubeadm init` — changing it needs `kubeadm/reset.sh` first, and requires `helm` on your laptop. See [cilium.md](../cilium.md). |
| `cloud_provider` | optional | `external` makes kubelet run `--cloud-provider=external` so OCCM can manage the nodes and create load balancers. Absent or empty means kubelet manages nothing. |

### Octavia load balancers

Each item in `octavia_lbs` is one VIP with TCP listeners on 80 and 443, and consumes one project load-balancer quota:

```yaml
  octavia_lbs:
    - name: ingress
      http_node_port: 30080     # optional, default 30080
      https_node_port: 30443    # optional, default 30443
```

`name` is required and must be lowercase alphanumeric with optional hyphens; names must be unique. NodePorts must fall in 30000–32767; the convention here is service port plus 30000, and they must match the NodePorts the app actually exposes in k8s-apps.

VIPs land in `cluster.env` as `OCTAVIA_LB_VIP_<NAME>`, plus `INGRESS_LB_VIP` when a LB is named `ingress`.

> **Pick one owner for load balancers.** Either list them under `octavia_lbs` with fixed NodePorts, or set `cloud_provider: external` and let OCCM create them per Service. Doing both double-books the quota.

## OpenStack Cloud Controller Manager (optional)

OCCM lets a `type: LoadBalancer` Service create its own Octavia LB and receive the VIP as an external IP, instead of you pre-declaring LBs in Terraform. Without it, `type: LoadBalancer` stays `<pending>` forever.

It needs `kubeadm.cloud_provider: external` set **before** the cluster is bootstrapped. `kubeadm init` and `join` are skipped once a node is bootstrapped, so on an existing cluster refresh the inventory and rebuild the Kubernetes layer — the VMs stay up:

```bash
./scripts/infra/up.sh            openstack <id>   # rewrites cluster.env
./scripts/infra/kubeadm/reset.sh openstack <id>
./scripts/infra/kubeadm/up.sh    openstack <id>
./scripts/infra/openstack/occm.sh <id>
```

Nodes come up Ready but carry `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule` until OCCM clears it, so most workloads stay Pending until that last command runs. Both CNIs tolerate the taint, so the pod network still starts.

`occm.sh` resolves `subnet_name` to a subnet id, writes `cloud.conf` into gitignored `sensitive/openstack/<name>/`, creates the `cloud-config` Secret from that file, and installs the chart with `secret.create=false` so the credential never enters Helm values. It is safe to re-run. Chart `2.32.0` matches Kubernetes 1.32 — the chart's major.minor tracks the Kubernetes minor; override with `OCCM_CHART_VERSION`.

Two `[LoadBalancer]` settings in the generated `cloud.conf` are not defaults and are what make this work here:

- `internal-lb=true` — the VIP is already a routable address on this subnet, so no floating IP is wanted. Leaving `floating-network-id` unset is not enough: OCCM then auto-discovers an external network and tries to allocate a floating IP, which fails when the project `floatingip` quota is 0.
- `manage-security-groups=true` — OCCM allocates a NodePort per Service, so the Terraform security group cannot know the ports in advance. This makes OCCM open exactly the ports it uses on the nodes' Neutron ports.

Then switch the app to a LoadBalancer Service. In k8s-apps, `overlays/cluster/<id>/ingress-nginx.yaml`:

```yaml
controller:
  service:
    type: LoadBalancer
```

```bash
cd ../k8s-apps && ./scripts/apps.sh install ingress-nginx --cluster <id>
kubectl -n ingress-nginx get svc -w      # EXTERNAL-IP appears within a minute or two
curl -s -o /dev/null -w '%{http_code}\n' http://<external-ip>/   # 404 from the default backend is success
```

The VIP is owned by OCCM, so recreating the Service gets a new address.

**Troubleshooting.** `EXTERNAL-IP` stuck on `<pending>` with `OverQuota ... 'floatingip'` in the logs means `internal-lb=true` is missing. An LB that is `ACTIVE` while `operating_status` is `ERROR` means the health monitor cannot reach the NodePort — check `manage-security-groups=true` and that `openstack security group list | grep lb-sg` shows a group. `cloud.conf` is read at startup: `occm.sh` restarts the DaemonSet, but force a Service resync with `kubectl -n ingress-nginx annotate svc ingress-nginx-controller occm-resync="$(date +%s)" --overwrite`. `Error initialising Routes support: router-id not set` is expected and harmless, since the CNI handles pod routing.

```bash
kubectl -n kube-system logs -l app=openstack-cloud-controller-manager --tail=100
kubectl get nodes -o custom-columns='NODE:.metadata.name,PROVIDER:.spec.providerID,TAINTS:.spec.taints[*].key'
```

To remove it: `helm -n kube-system uninstall openstack-ccm`, drop `cloud_provider` from the cluster YAML, restore `type: NodePort`, and rebuild. `prepare.sh` removes `/etc/default/kubelet` when `cloud_provider` is unset. Delete any leftover `kube_service_*` load balancers.

## Teardown

```bash
./scripts/infra/down.sh openstack <id> -y          # VMs, ports, security group, keypair, Octavia LBs
./scripts/infra/kubeadm/reset.sh openstack <id>    # Kubernetes only, VMs stay
```

Neither deletes the existing Neutron network. LBs created by OCCM are owned by Kubernetes, not Terraform — delete those Services first, or clean up the `kube_service_*` LBs by hand.

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

**Compute + Neutron**

```bash
openstack server list
openstack server show <cluster>-cp
openstack port list --server <cluster>-cp
openstack security group show <cluster>-sg
openstack security group rule list <cluster>-sg
openstack network show tenant-internal-direct-net
openstack subnet list --network tenant-internal-direct-net
```

**Octavia — provisioning vs operating**

`provisioning_status=ACTIVE` means the object exists. `operating_status=ERROR` usually means health monitors cannot reach the members: nothing is listening on the NodePort, or the security group blocks the path from the amphora to the nodes.

```bash
openstack loadbalancer list
LB=$(openstack loadbalancer list -f value -c name | head -1)
openstack loadbalancer show "$LB"
openstack loadbalancer listener list --loadbalancer "$LB"
openstack loadbalancer pool list --loadbalancer "$LB"
openstack loadbalancer member list <pool-id>       # ONLINE vs ERROR/OFFLINE is the health check
openstack loadbalancer amphora list --loadbalancer "$LB"
openstack loadbalancer status show "$LB"
```

**From the cluster side**

```bash
export KUBECONFIG=$PWD/sensitive/openstack/<id>/kubeconfig
kubectl get svc -A
kubectl get nodes -o wide

ssh -i sensitive/openstack/<id>/ssh.pem ubuntu@$(grep CONTROL_PLANE_HOST= sensitive/openstack/<id>/cluster.env | cut -d= -f2) \
  'ss -lnt | grep -E ":3[0-2][0-9]{3}" || echo "no nodeports listening"'
```

**Hit the VIP** from a host that can reach the tenant net:

```bash
curl -sv  --connect-timeout 5 "http://<vip>/"  -o /dev/null
curl -skv --connect-timeout 5 "https://<vip>/" -o /dev/null
```

**CodeGuard:** never commit `clouds.yaml` or `cloud.conf`, and never paste `application_credential_secret` into chat.
