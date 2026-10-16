#!/usr/bin/env bash
# Install: wait for workers, ingress, console and every ClusterOperator.
#
# Runs on: jump host (openshift-install wait-for install-complete).
# Takes 20-40 minutes. Safe to Ctrl-C and re-run.
#
# Why: bootstrap-complete only means the control plane is self-hosted. Now
# the machine-api creates the worker VMs from MachineSets, the ingress
# router pods take the ingress VIP (and your ingress FIP), the image registry
# gets its Cinder PVC, and ~30 ClusterOperators must report Available.
#
# While it waits, from the jump host (KUBECONFIG as in phase 70):
#   oc get clusteroperators          # watch AVAILABLE turn True
#   oc get machines -n openshift-machine-api
#   oc get csr                       # node certs (auto-approved during install)
#
# The kubeadmin password is written to install/auth/kubeadmin-password and is
# not echoed here; phase 90 copies it to the laptop.

ocp_load_outputs
ocp_remote 80-install.sh
