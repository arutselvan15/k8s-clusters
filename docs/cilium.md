# CNI: Calico or Cilium

**Decision.** `cni` in the cluster YAML selects the pod network. `calico` stays the default. `cilium` is supported and brings eBPF service handling plus Hubble.

**Cilium BGP and ECMP are not viable on the OpenStack lab and are not implemented.** That is a limit of the tenant network, not of the CNI, so switching CNI does not unlock it. Octavia + OCCM remains the way traffic reaches the cluster. The evidence is in [Why BGP/ECMP is out](#why-bgpecmp-is-out) — read that before proposing it again.

```yaml
kubeadm:
  pod_cidr: 192.168.0.0/16
  cni: calico        # or cilium
```

Fixed at `kubeadm init`, exactly like `cloud_provider`: `cilium` skips the kube-proxy addon, and that phase does not run twice. Changing `cni` on a live cluster means rebuilding the Kubernetes layer (the VMs stay up):

```bash
./scripts/infra/up.sh            openstack <id>   # rewrites cluster.env
./scripts/infra/kubeadm/reset.sh openstack <id>
./scripts/infra/kubeadm/up.sh    openstack <id>
```

`cni: cilium` needs `helm` on your laptop. Nothing extra is installed on the nodes.

---

## What each one gives you

| | calico | cilium |
|---|---|---|
| Install | one manifest, pinned by tag | Helm chart, pinned by version |
| Service handling | kube-proxy (iptables) | eBPF, no kube-proxy |
| Encapsulation here | IPIP cross-subnet | VXLAN |
| Policy | Kubernetes NetworkPolicy + Calico CRDs | adds L7 (HTTP verb/path) and DNS (`toFQDNs`) |
| Flow visibility | none built in | Hubble relay + UI |
| Debugging | `iptables-save` | `cilium-dbg`, eBPF maps |

**Reasons to pick cilium:** Hubble is the real one — flow-level visibility and a service map with no Calico OSS equivalent. Then eBPF service handling with no iptables chain to read, and DNS/L7-aware policy. Its Gateway API implementation could also retire `envoy-gateway` and `gateway-api-crds` from k8s-apps, though it would still need a `LoadBalancer` Service and therefore still one Octavia LB.

**Reasons to stay on calico:** it is one `kubectl apply` with no Helm dependency, iptables is far easier to reason about than eBPF maps, and it is what most enterprise clusters ship. Transparent WireGuard encryption is a wash — both have it.

### Settings that are specific to this lab

Set in `k8s_plat_install_cilium` ([kubeadm/lib.sh](../scripts/infra/kubeadm/lib.sh)):

- `kubeProxyReplacement=true` with `k8sServiceHost`/`k8sServicePort` — with no kube-proxy there is no ClusterIP path to the API server, so the agent needs the endpoint directly.
- `loadBalancer.mode=snat` — **do not switch to DSR.** DSR answers the client with the VIP as source address, and Neutron port security drops packets a port is not allowed to source. Same root cause as the BGP problem below.
- `routingMode=tunnel` / `tunnelProtocol=vxlan` — the pod CIDR is not routable on the tenant network, so it has to be encapsulated. Calico's IPIP does the same job.
- `ipam.mode=kubernetes` — honours `pod_cidr` via the per-node `podCIDR` kubeadm hands out.
- `operator.replicas=1` — the default 2 cannot spread on a one-worker lab.

`hubble-relay` and `hubble-ui` ship without control-plane tolerations, so on a `worker_nodes: 0` cluster they stay Pending forever. That is why the install gates on `rollout status daemonset/cilium` instead of `helm --wait`, which would block on them.

No security group change was needed for either CNI: the `self` rule in [main.tf](../infra/terraform/environments/openstack/main.tf) already allows every protocol within the group, covering VXLAN 8472, Cilium health 4240, and Calico's IPIP (protocol 4).

---

## Why BGP/ECMP is out

The proposal was to let Cilium advertise a VIP over BGP so the fabric could ECMP across nodes, dropping Octavia from the path. Two independent blockers, both verified against the live tenant:

**1. There is no BGP service to peer with.** `openstack extension list --network` returns no `bgp`, `bgp_dragent`, `bgp-speaker`, or dynamic-routing extension. What it does return is `cisco-apic`, `cisco-apic-l3`, `group-policy`, and `servicechain` — this is a Cisco ACI fabric. Cilium's BGP control plane needs a neighbor, and the ACI leaf is not something the tenant can configure. Getting one means asking the network team for an L3Out with the Kubernetes nodes as external BGP peers. That is a ticket, not a commit.

**2. Port security drops VIP-sourced traffic.** `tenant-internal-direct-net` has `port_security_enabled: true`, so Neutron discards any packet a VM sources from an address that is not a fixed IP or an allowed-address-pair on its port. Even with a BGP session established, return traffic sourced from the VIP would never leave the node.

ECMP follows from the first: equal-cost paths are a property of the upstream router's table, and with no session nothing is advertising into it.

This is the same wall MetalLB already hit — `common/apps.yaml` in k8s-apps disables it because "port security blocks L2 ARP for MetalLB VIPs."

**What that costs us.** BGP/ECMP would have removed the Octavia load-balancer quota ceiling (2 on this project, already spent on ingress-nginx and one Envoy Gateway) and taken the amphora out of the data path. That is the actual prize, and it stays out of reach.

### The one path still open

The `allowed-address-pairs` extension **is** enabled. Adding an AAP entry for a VIP on each node's Neutron port makes the anti-spoofing drop go away, which would let either MetalLB L2 mode or Cilium's `l2announcements` hold a VIP without spending Octavia quota. Caveats: L2 only, so one node answers at a time and there is still no ECMP, and ACI's handling of gratuitous ARP on endpoint moves may still interfere. Untested — but unlike BGP it is entirely within our control.

---

## Operating a cilium cluster

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief
kubectl -n kube-system exec ds/cilium -- cilium-dbg service list     # replaces kube-proxy
kubectl -n kube-system port-forward svc/hubble-ui 12000:80
kubectl get ds -n kube-system kube-proxy                             # expected: NotFound
```

`kubeadm/reset.sh` deletes the leftover `cilium_host`/`cilium_net`/`cilium_vxlan` and `vxlan.calico` links, so switching `cni` on the same VMs is repeatable. A CNI switch is still cleaner on fresh VMs if you have the quota.
