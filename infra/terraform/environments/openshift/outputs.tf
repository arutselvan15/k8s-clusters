output "project_name" {
  value = data.openstack_identity_auth_scope_v3.current.project_name
}

output "network_name" {
  value = local.network_name
}

output "subnet_name" {
  value = local.subnet_name
}

# machineNetwork in install-config. With network_mode=existing this is read
# back from the provider subnet instead of being declared in the config.
output "machine_cidr" {
  value = local.machine_cidr
}

output "jumphost_fixed_ip" {
  value = openstack_networking_port_v2.jumphost.all_fixed_ips[0]
}

# Where every later phase SSHes: the floating IP when there is one, otherwise
# the fixed IP, which is routable on a provider network.
output "jumphost_ssh_ip" {
  value = local.create_network ? openstack_networking_floatingip_v2.jumphost[0].address : openstack_networking_port_v2.jumphost.all_fixed_ips[0]
}

output "jumphost_floating_ip" {
  value = local.create_network ? openstack_networking_floatingip_v2.jumphost[0].address : ""
}

output "api_floating_ip" {
  value = local.create_network ? openstack_networking_floatingip_v2.api[0].address : ""
}

output "ingress_floating_ip" {
  value = local.create_network ? openstack_networking_floatingip_v2.ingress[0].address : ""
}

output "ssh_private_key_path" {
  value = local_file.ssh_private_key.filename
}

output "ssh_public_key" {
  value = trimspace(tls_private_key.lab.public_key_openssh)
}
