variable "cloud" {
  type        = string
  description = "Cloud name in k8s-clusters/sensitive/openstack/clouds.yaml."
}

variable "cluster_name" {
  type        = string
  description = "OpenShift metadata.name. Prefixes every resource here (<cluster_name>-net, -jump, ...)."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path for the generated SSH private key (sensitive/openshift/<cluster_name>/ssh.pem)."
}

variable "ssh_key_algorithm" {
  type        = string
  description = "tls_private_key algorithm (ED25519 or RSA)."
}

variable "admin_cidrs" {
  type        = list(string)
  description = "Who may SSH to the jump host. One rule per CIDR."
}

variable "network_mode" {
  type        = string
  description = "create = build a tenant network, router and floating IPs. existing = join a provider network that already routes."

  validation {
    condition     = contains(["create", "existing"], var.network_mode)
    error_message = "network_mode must be create or existing."
  }
}

variable "existing_network" {
  type        = string
  default     = ""
  description = "network_mode=existing: name of the provider network to join."
}

variable "existing_subnet" {
  type        = string
  default     = ""
  description = "network_mode=existing: name of the subnet on it that the jump host, nodes and VIPs use."
}

variable "network_cidr" {
  type        = string
  default     = ""
  description = "network_mode=create: machine network for jump host, bootstrap, masters, workers and both VIPs."
}

variable "dhcp_start" {
  type        = string
  default     = ""
  description = "network_mode=create: first address of the DHCP allocation pool."
}

variable "dhcp_end" {
  type        = string
  default     = ""
  description = "network_mode=create: last address of the DHCP allocation pool. VIPs must be outside the pool."
}

variable "dns_nameservers" {
  type        = list(string)
  default     = []
  description = "network_mode=create: upstream resolvers handed out by DHCP."
}

variable "external_network" {
  type        = string
  default     = ""
  description = "network_mode=create: existing external network for the router gateway and floating IPs."
}

variable "jumphost_image" {
  type        = string
  description = "Glance image for the jump host."
}

variable "jumphost_image_most_recent" {
  type        = bool
  description = "If several Glance images share jumphost_image, use the newest."
}

variable "jumphost_flavor" {
  type        = string
  description = "Nova flavor for the jump host."
}

variable "jumphost_root_volume_gb" {
  type        = number
  description = "Jump host boot volume (GiB). Holds the installer, RHCOS download and logs. 0 boots from the flavor's local disk and uses no Cinder quota."
}
