# OpenShift on OpenStack with selectable CNI

OpenShift **4.22** installed by `openshift-install` (IPI) on OpenStack. Select either the built-in **OVNKubernetes** CNI or **Cilium 1.19** before the first boot. The build is split into ten phases you run one at a time; each phase prints what it is about to do and why before it does it.

This is a separate flow from the kubeadm clusters in [openstack.md](./openstack.md): OpenShift brings its own OS (RHCOS), its own control plane and its own machine management, so nothing here reuses `kubeadm/`.

## Who owns what

| Layer | Created by | Destroyed by |
|-------|-----------|--------------|
| Jump host, and the network, subnet, router and 3 floating IPs when `terraform.network.mode` is `create` | Terraform (phase 10, [`infra/terraform/environments/openshift`](../../infra/terraform/environments/openshift)) | `down.sh <id> infra` |
| RHCOS image, bootstrap/master/worker VMs, ports, security groups, server groups, registry volume | `openshift-install` on the jump host (phase 60) | `down.sh <id> cluster` |
| OVNKubernetes | OpenShift Cluster Network Operator | with the cluster |
| Cilium | install manifests (phase 50), applied by the bootstrap node | with the cluster |

The installer runs on the jump host because it must reach the API and ingress VIPs on the machine network while it waits. Your laptop only talks to OpenStack (Terraform, preflight) and SSHes to the jump host.

## Two network modes

`terraform.network.mode` decides how much of the network the lab builds, and that choice follows the project's quota.

```text
mode: create  (arselvan-ocp-alln)

laptop ──ssh──> jump FIP ──> <cluster>-jump ─┐
laptop ──https──> API FIP ──> API VIP ───────┤ <cluster>-subnet (10.20.0.0/24)
laptop ──https──> ingress FIP ──> ingress VIP┤   masters x3, workers x2
                                             └─ <cluster>-router ──SNAT──> quay.io, registry.redhat.io

mode: existing  (fms-lab-rtp)

laptop ──ssh────> <cluster>-jump ─┐
laptop ──https──> API VIP ────────┤ tenant-internal-direct-subnet1 (64.102.178.0/23)
laptop ──https──> ingress VIP ────┤   masters x3, workers x2
                                  └─ the subnet's own gateway ──> quay.io, registry.redhat.io
```

| | `create` | `existing` |
|---|---|---|
| Terraform builds | network, subnet, router, jump host, 3 FIPs | the jump host, nothing else |
| Needs quota for | networks, subnets, routers, floating IPs | none of them |
| Machine network | `terraform.network.cidr`, private to the cluster | `terraform.network.subnet`, read back from OpenStack in phase 10 |
| Node egress | the router's SNAT | the provider subnet's gateway |
| Reaching the cluster | floating IPs | the VIPs themselves, which are already routable |
| `install-config` gets | `externalNetwork`, `apiFloatingIP`, `ingressFloatingIP` | none of the three |

`existing` exists because a project can be given compute quota and no network quota at all. It has one sharp edge: the VIPs are two addresses on a subnet you share with other projects, whose ports you cannot see. Pick them, confirm they answer nothing, and install soon after — phase 00 checks only that they are inside the subnet and unused by your own project.

## Before phase 00

1. **Application credential for the target project.** Credentials are bound to one project. In Horizon, switch to `arselvan-lab-alln`, then *Identity → Application Credentials → Create*, and add an entry under `clouds:` in `sensitive/openstack/clouds.yaml` named exactly as `cloud:` in the cluster config:

   ```yaml
   clouds:
     arselvan-lab-alln:
       auth:
         auth_url: https://cloud-alln-1.cisco.com:5000
         application_credential_id: <from Horizon>
         application_credential_secret: <from Horizon>
       region_name: "cloud-alln-1"
       interface: "public"
       identity_api_version: 3
       auth_type: "v3applicationcredential"
   ```

   Phase 20 copies only this entry to the jump host. The installer also stores it in the cluster (`kube-system/openstack-credentials`) because the OpenStack cloud provider and machine-api use it to create volumes and worker VMs, so use a credential you can revoke on its own.

2. **Pull secret.** Download from [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret) to `sensitive/openshift/pull-secret.json`. A no-cost account gives a 60-day evaluation per cluster.

3. **Laptop tools:** `terraform`, `openstack`, `helm`, `yq` (v4), `jq`, `ssh`. Nothing OpenShift-specific is installed on the laptop.

## Run it

```bash
./scripts/infra/openshift/ocp.sh <id>                  # next pending phase only (default)
./scripts/infra/openshift/ocp.sh <id> status           # done / NEXT / pending
./scripts/infra/openshift/ocp.sh <id> explain 50       # read a phase without running it
./scripts/infra/openshift/ocp.sh <id> 50               # re-run one phase
./scripts/infra/openshift/ocp.sh <id> all              # every remaining phase
./scripts/infra/openshift/ocp.sh <id> all 50           # remaining phases up to and including 50
```

The cluster id is the directory name under `clusters/openshift/`: `arselvan-ocp-alln` (project `arselvan-lab-alln`) or `fms-lab-rtp` (project `fms-lab-rtp`). It may be omitted only while one config dir exists. A phase refuses to run until the phases before it are done; `--force` overrides that. Completion is recorded in `sensitive/openshift/<cluster>/phases/`.

| Phase | Where | Time | What you learn |
|-------|-------|------|----------------|
| `00-preflight` | laptop | 2–4 min | What OpenShift needs from the project: flavors, quota, external network |
| `10-infra` | laptop | 3–5 min | The pieces IPI does *not* create when you bring your own network |
| `20-jumphost` | jump | 2–3 min | How the installer authenticates and resolves the cluster names; whether nodes have egress |
| `30-tools` | jump | 1–2 min | The installer binary *is* the release: digest and RHCOS URL are baked in |
| `40-install-config` | laptop → jump | seconds | Every field that matters for OpenStack + Cilium |
| `50-manifests` | laptop + jump | ~1 min | How a third-party CNI gets in before the cluster exists |
| `60-create` | jump | ~5 min, then background | Order of operations inside `create cluster` |
| `70-bootstrap` | jump | 20–40 min | Temporary control plane, etcd formation, Cilium making nodes Ready |
| `80-install` | jump | 20–40 min | MachineSets, ingress, ClusterOperators |
| `90-verify` | jump + laptop | 5–10 min | Cilium status, kube-proxy-free Services, connectivity checks |

Phases 70 and 80 only watch; Ctrl-C and re-run them any time. The real work started in phase 60 keeps running on the jump host (`tail -f ~/ocp/<cluster>/create.log`).

## Select the CNI before phase 40

Set `openshift.cni` in `clusters/openshift/<id>/config.yaml`. The file is grouped like the kubeadm configs: `terraform` owns the jump host and machine network, `openshift` owns the cluster, and `openshift.cilium` is used only when `cni` is `Cilium`.

```yaml
openshift:
  cni: OVNKubernetes # built-in; no extra CNI manifests
  # cni: Cilium      # upstream chart rendered in phase 50
  cilium:
    version: "1.19.8"
```

The default is `OVNKubernetes` when the key is absent; this lab configuration explicitly selects `Cilium`. The choice is embedded in `install-config.yaml` and cannot be switched on a live cluster—destroy and rebuild the Kubernetes layer instead. `openshift.cilium.*` is required and used only with `cni: Cilium`; phase 50 skips Helm rendering for `OVNKubernetes`.

## Sizing in `arselvan-lab-alln`

| | Count | vCPU | RAM | Boot volume |
|---|---|---|---|---|
| jump host | 1 | 2 | 8 GB | 50 GB |
| bootstrap (deleted after phase 70) | 1 | 4 | 16 GB | 120 GB |
| masters | 3 | 4 | 16 GB | 120 GB |
| workers | 2 | 4 | 16 GB | 120 GB |
| image registry PVC (no Swift on this cloud) | | | | 100 GB |
| **Peak during install** | 7 VMs | 26 | 104 GB | 8 volumes, 870 GB |

Plus 3 floating IPs, 1 network, 1 router. Phase 00 compares this with `openstack quota show --usage` and stops if the project is short.

## Sizing in `fms-lab-rtp`

This project has no network, subnet, router or floating IP quota, and 450 GB of Cinder of which 350 GB is CBS. It is built around the shared provider network `tenant-internal-direct-net`, whose subnets hand out routable addresses directly. `mode: existing` and `root_volume_gb: 0` are what make a cluster fit:

| | Count | vCPU | RAM | Boot disk |
|---|---|---|---|---|
| jump host | 1 | 2 | 8 GB | 50 GB flavor disk |
| bootstrap (deleted after phase 70) | 1 | 4 | 16 GB | 50 GB flavor disk |
| masters | 3 | 4 | 16 GB | 50 GB flavor disk |
| workers | 2 | 4 | 16 GB | 50 GB flavor disk |
| image registry PVC (no Swift on this cloud) | | | | 100 GB CBS |
| **Peak during install** | 7 VMs | 26 | 104 GB | 1 volume, 100 GB |

Nothing boots from Cinder, so the registry's PVC is the only volume. That is the point: six 100 GB root volumes would need 600 GB of CBS and the project has 350. The cost is that each node has a 50 GB disk where OpenShift asks for 100 GB, so phase 00 warns, image garbage collection runs more often and etcd has less headroom. Raise `openshift.root_volume_gb` to 100 if the CBS quota ever grows.

Instances (7 of 7), cores (26 of 28) and RAM (104 of 112 GB) sit at the ceiling: the project fits exactly one cluster of this shape and nothing else. Watch `security_group_rules` as well — the limit is 60 with 6 in use, the jump host's group adds about 6, and the installer's master and worker groups together are roughly 45. If phase 60 fails on rule quota, cut `terraform.admin_cidr` to a single CIDR and ask for a larger rule limit, which is a far smaller request than network quota.

## Names and DNS

There is no DNS zone for `base_domain`, so `/etc/hosts` stands in for it:

- **Jump host** (phase 20): `api` and `api-int` point at the API VIP; console and OAuth names point at the ingress VIP. The jump host sits on the machine network, so it uses the VIPs directly.
- **Nodes**: nothing to do. On OpenStack, OpenShift runs CoreDNS, keepalived and HAProxy as static pods on the nodes. They answer `api-int` and `*.apps` and move the VIPs on failover.
- **Laptop** (printed by phase 90): `api` → API FIP; console/oauth/downloads → ingress FIP. With `mode: existing` there are no FIPs, so both point at the VIPs instead and you need a route to the machine network. Add any route hostname you create the same way.

## Cilium: what is different from the Isovalent tutorial

The [Isovalent tutorial](https://isovalent.com/blog/post/deploying-red-hat-openshift-with-cilium/) uses the **CLife** operator manifests, which are the Red Hat-certified path but need an Isovalent customer login. This lab renders the **upstream Cilium Helm chart** into the same install-manifest hook instead:

| Topic | Tutorial (CLife) | This lab (`openshift.cilium.source: helm`) |
|-------|------------------|----------------------------------|
| Support | Red Hat + Isovalent, certified CNI | Community; Red Hat will not support the pod network |
| Lifecycle | CLife operator reconciles a `CiliumConfig` | Static manifests; upgrade with `helm template` + `oc apply` |
| Namespace | operator-managed | `cilium`, `openshift.io/run-level: "0"` so SCC admission skips the privileged agents |
| kube-proxy off | `deployKubeProxy: false` patched into `cluster-network-02-config.yml` | `deployKubeProxy` set on the **operator** Network (`cluster-network-03-config.yml`); that is the API the field belongs to |
| API endpoint | patched into CLife Deployment + Subscription | `k8sServiceHost: api-int.<cluster>.<domain>` in the chart values |

Common to both: `cni.confPath=/var/run/multus/cni/net.d`, `cni.binPath=/var/lib/cni/bin`, `cni.exclusive=false` (Multus stays the node's CNI entry point), cluster-pool IPAM equal to `clusterNetwork`, VXLAN on UDP 4789 (already open in the installer's security groups), cluster health on 9940.

One extra change here: Hubble listens on **9941** instead of 4244, because the installer's node security groups only open 9000–9999 between nodes.

Switching to CLife later means replacing the `cilium-*` files in phase 50 with the Isovalent release manifests; nothing else in the flow changes.

## Teardown

```bash
./scripts/infra/openshift/down.sh                 # cluster, then infra (asks before each)
./scripts/infra/openshift/down.sh arselvan-ocp-alln cluster   # only openshift-install destroy cluster
./scripts/infra/openshift/down.sh arselvan-ocp-alln infra     # only Terraform; refuses while a cluster exists
```

Order matters: the cluster's ports live on the Terraform network, and only the jump host's `install/metadata.json` knows the cluster's infra ID. `infra` refuses to run until `cluster` has, unless you pass `--force`, which orphans the VMs.

## When something hangs

| Symptom | Look at |
|---------|---------|
| Phase 60 exits early | `tail -50 ~/ocp/<cluster>/create.log` — quota, flavor or network validation |
| No VMs after 10 min | RHCOS upload to Glance; `openstack image list --name <infra-id>-rhcos` |
| Phase 70 times out at "Waiting for the Kubernetes API" | bootstrap VM: `ssh -J ubuntu@<jump> core@<bootstrap IP> journalctl -b -f -u bootkube.service` |
| Masters stay NotReady | `oc -n cilium get pods -o wide`, `oc -n cilium logs ds/cilium -c cilium-agent`; image pulls from quay.io |
| Phase 80 times out | `oc get co` — the operator that is not Available names the problem |
| Anything | `openshift-install gather bootstrap --dir ~/ocp/<cluster>/install` (bootstrap still alive) or `oc adm must-gather` |
