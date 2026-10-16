#!/usr/bin/env bash
# Bootstrap: wait until the masters run the control plane without bootstrap.
#
# Runs on: jump host (openshift-install wait-for bootstrap-complete).
# Takes 20-40 minutes. Safe to Ctrl-C and re-run; it only watches.
#
# Why this is the interesting part for networking: masters register as nodes
# but stay NotReady until the selected CNI is ready. With Cilium, bootstrap
# applies the cilium-* manifests and its DaemonSet writes config into Multus'
# CNI directory; with OVNKubernetes, CNO deploys the built-in OVN components.
#
# While it waits, from the jump host:
#   export KUBECONFIG=~/ocp/<cluster>/install/auth/kubeconfig
#   oc get nodes -w
#   oc -n cilium get pods -o wide       # when openshift.cni is Cilium
#   openstack server list            # bootstrap + masters, then workers
# Bootstrap logs (from the laptop, through the jump host):
#   ssh -i <ssh.pem> -J ubuntu@<jump FIP> core@<bootstrap IP> \
#     journalctl -b -f -u release-image.service -u bootkube.service
# If it times out: openshift-install gather bootstrap --dir install

ocp_load_outputs
ocp_remote 70-bootstrap.sh "OCP_CNI=${OCP_CNI}"
