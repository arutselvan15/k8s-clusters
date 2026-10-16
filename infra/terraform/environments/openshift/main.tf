# OpenShift lab, phase 10. Terraform owns only what the installer does not:
# the machine network, its router, the jump host, and the two floating IPs the
# installer attaches to the API and ingress VIPs. Every cluster VM, port and
# security group is created (and later destroyed) by openshift-install.
# Auth: clouds.yaml via OS_CLIENT_CONFIG_FILE (scripts/lib/os-env.sh).
#
# Two network modes, selected by terraform.network.mode in the cluster config:
#
#   create    self-service tenant network + router + 3 floating IPs. Needs
#             network, subnet, router and floatingip quota.
#   existing  land on a shared provider network that already routes. Nothing
#             is created but the jump host port, so a project with zero
#             network/router/floatingip quota can still build a cluster. The
#             jump host is reached on its fixed IP and the VIPs are reached
#             directly, so there are no floating IPs anywhere in the flow.

data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}

locals {
  create_network = var.network_mode == "create"
}

data "openstack_images_image_v2" "jumphost" {
  name        = var.jumphost_image
  most_recent = var.jumphost_image_most_recent
}

data "openstack_compute_flavor_v2" "jumphost" {
  name = var.jumphost_flavor
}

# mode=create only: the router gateway and the floating IP pool.
data "openstack_networking_network_v2" "external" {
  count    = local.create_network ? 1 : 0
  name     = var.external_network
  external = true
}

# mode=existing: the provider network and the one subnet the cluster lands on.
data "openstack_networking_network_v2" "existing" {
  count = local.create_network ? 0 : 1
  name  = var.existing_network
}

data "openstack_networking_subnet_v2" "existing" {
  count      = local.create_network ? 0 : 1
  name       = var.existing_subnet
  network_id = data.openstack_networking_network_v2.existing[0].id
}

# Machine network. install-config points controlPlanePort at this subnet, and
# machineNetwork must equal its CIDR.
resource "openstack_networking_network_v2" "ocp" {
  count          = local.create_network ? 1 : 0
  name           = "${var.cluster_name}-net"
  admin_state_up = true
}

resource "openstack_networking_subnet_v2" "ocp" {
  count           = local.create_network ? 1 : 0
  name            = "${var.cluster_name}-subnet"
  network_id      = openstack_networking_network_v2.ocp[0].id
  cidr            = var.network_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers

  allocation_pool {
    start = var.dhcp_start
    end   = var.dhcp_end
  }
}

# SNAT for node egress (quay.io, registry.redhat.io) and the floating IP path.
# mode=existing has neither: the provider subnet's gateway already routes.
resource "openstack_networking_router_v2" "ocp" {
  count               = local.create_network ? 1 : 0
  name                = "${var.cluster_name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external[0].id
}

resource "openstack_networking_router_interface_v2" "ocp" {
  count     = local.create_network ? 1 : 0
  router_id = openstack_networking_router_v2.ocp[0].id
  subnet_id = openstack_networking_subnet_v2.ocp[0].id
}

locals {
  network_id   = local.create_network ? openstack_networking_network_v2.ocp[0].id : data.openstack_networking_network_v2.existing[0].id
  network_name = local.create_network ? openstack_networking_network_v2.ocp[0].name : data.openstack_networking_network_v2.existing[0].name
  subnet_id    = local.create_network ? openstack_networking_subnet_v2.ocp[0].id : data.openstack_networking_subnet_v2.existing[0].id
  subnet_name  = local.create_network ? openstack_networking_subnet_v2.ocp[0].name : data.openstack_networking_subnet_v2.existing[0].name
  machine_cidr = local.create_network ? var.network_cidr : data.openstack_networking_subnet_v2.existing[0].cidr
}

# Jump host: SSH in from admin_cidrs only. Outbound is unrestricted (default).
resource "openstack_networking_secgroup_v2" "jumphost" {
  name        = "${var.cluster_name}-jump-sg"
  description = "OpenShift lab jump host: SSH and ICMP from admin_cidrs"
}

resource "openstack_networking_secgroup_rule_v2" "jumphost_ssh" {
  for_each          = toset(var.admin_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumphost.id
}

resource "openstack_networking_secgroup_rule_v2" "jumphost_icmp" {
  for_each          = toset(var.admin_cidrs)
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  remote_ip_prefix  = each.value
  security_group_id = openstack_networking_secgroup_v2.jumphost.id
}

# One key for the jump host (ubuntu) and the RHCOS nodes (core, via
# install-config sshKey). The private half never leaves the laptop: node SSH
# goes through the jump host with ProxyJump.
resource "tls_private_key" "lab" {
  algorithm = var.ssh_key_algorithm
}

resource "openstack_compute_keypair_v2" "lab" {
  name       = "${var.cluster_name}-ssh"
  public_key = tls_private_key.lab.public_key_openssh
}

resource "local_file" "ssh_private_key" {
  content         = tls_private_key.lab.private_key_openssh
  filename        = abspath(var.ssh_private_key_path)
  file_permission = "0600"
}

resource "openstack_networking_port_v2" "jumphost" {
  name               = "${var.cluster_name}-jump"
  network_id         = local.network_id
  admin_state_up     = true
  security_group_ids = [openstack_networking_secgroup_v2.jumphost.id]

  fixed_ip {
    subnet_id = local.subnet_id
  }
}

# jumphost_root_volume_gb = 0 boots from the flavor's local disk and uses no
# Cinder quota at all; anything else boots from a volume of that size.
resource "openstack_compute_instance_v2" "jumphost" {
  name      = "${var.cluster_name}-jump"
  flavor_id = data.openstack_compute_flavor_v2.jumphost.id
  key_pair  = openstack_compute_keypair_v2.lab.name
  image_id  = var.jumphost_root_volume_gb > 0 ? null : data.openstack_images_image_v2.jumphost.id

  dynamic "block_device" {
    for_each = var.jumphost_root_volume_gb > 0 ? [1] : []

    content {
      uuid                  = data.openstack_images_image_v2.jumphost.id
      source_type           = "image"
      destination_type      = "volume"
      volume_size           = var.jumphost_root_volume_gb
      boot_index            = 0
      delete_on_termination = true
    }
  }

  network {
    port = openstack_networking_port_v2.jumphost.id
  }

  metadata = {
    role = "openshift-jumphost"
  }

  depends_on = [openstack_networking_router_interface_v2.ocp]
}

resource "openstack_networking_floatingip_v2" "jumphost" {
  count       = local.create_network ? 1 : 0
  pool        = var.external_network
  description = "${var.cluster_name} jump host"
}

resource "openstack_networking_floatingip_associate_v2" "jumphost" {
  count       = local.create_network ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.jumphost[0].address
  port_id     = openstack_networking_port_v2.jumphost.id

  depends_on = [openstack_networking_router_interface_v2.ocp]
}

# Allocated here, attached by openshift-install (apiFloatingIP /
# ingressFloatingIP) to the VIP ports it creates. Fixed addresses let you write
# /etc/hosts before the cluster exists.
resource "openstack_networking_floatingip_v2" "api" {
  count       = local.create_network ? 1 : 0
  pool        = var.external_network
  description = "${var.cluster_name} API (api.<cluster>.<base_domain>)"
}

resource "openstack_networking_floatingip_v2" "ingress" {
  count       = local.create_network ? 1 : 0
  pool        = var.external_network
  description = "${var.cluster_name} ingress (*.apps.<cluster>.<base_domain>)"
}
