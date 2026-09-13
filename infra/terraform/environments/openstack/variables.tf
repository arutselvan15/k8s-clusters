variable "cloud" {
  type        = string
  description = "Cloud name in k8s-clusters/sensitive/openstack/clouds.yaml."
}

variable "cluster_name" {
  type        = string
  description = "From the cluster id passed to up.sh. Nodes are {cluster_name}-cp and {cluster_name}-wk-N."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path for the generated SSH private key (sensitive/<env>/<cluster_name>/ssh.pem)."
}

variable "admin_cidr" {
  type        = string
  description = "Who may SSH and reach the Kubernetes API."
}

variable "ssh_port" {
  type        = number
  description = "SSH ingress port."
}

variable "kubernetes_api_port" {
  type        = number
  description = "Kubernetes API ingress port."
}

variable "network_name" {
  type        = string
  description = "Existing Neutron network to attach VMs to (not created)."
}

variable "image_name" {
  type        = string
  description = "Glance image name. Horizon: Compute → Images."
}

variable "image_most_recent" {
  type        = bool
  description = "If multiple Glance images share image_name, use the newest."
}

variable "node_flavor" {
  type        = string
  description = "Nova flavor for control plane and workers."
}

variable "worker_nodes" {
  type        = number
  description = "Worker VM count (0 = control-plane only)."
}

variable "root_volume_gb" {
  type        = number
  description = "Boot volume size (GiB). Volume-boot so flavors with 0 local disk still work."
}

variable "volume_delete_on_termination" {
  type        = bool
  description = "Delete the boot volume when the instance is deleted."
}

variable "ssh_user" {
  type        = string
  description = "SSH user on the image."
}

variable "ssh_key_algorithm" {
  type        = string
  description = "tls_private_key algorithm (ED25519 or RSA)."
}

variable "availability_zone" {
  type        = string
  description = "Optional Nova AZ. Empty = let the scheduler choose."
}
