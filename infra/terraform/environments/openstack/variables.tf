variable "cloud" {
  type        = string
  default     = "lab"
  description = "Cloud name in k8s-platform/config/openstack/clouds.yaml."
}

variable "cluster_name" {
  type        = string
  default     = "k8s-os"
  description = "Cluster identity and OpenStack object prefix."
}

variable "control_plane_prefix" {
  type        = string
  default     = "cp"
  description = "Control-plane name: {cluster_name}-{control_plane_prefix}."
}

variable "worker_prefix" {
  type        = string
  default     = "wk"
  description = "Worker name: {cluster_name}-{worker_prefix}-N."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path for the generated SSH private key (clusters/<cluster_name>/ssh.pem)."
}

variable "admin_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Who may SSH (22) and reach the Kubernetes API (6443). Lab default is open."
}

variable "network_name" {
  type        = string
  description = "Existing Neutron network to attach VMs to (not created). Example: tenant-internal-direct-net."
}

variable "image_name" {
  type        = string
  description = "Glance image name. Horizon: Compute → Images."
}

variable "node_flavor" {
  type        = string
  description = "Nova flavor for control plane and workers."
}

variable "worker_nodes" {
  type        = number
  default     = 1
  description = "Worker VM count (0 = control-plane only)."
}

variable "root_volume_gb" {
  type        = number
  default     = 20
  description = "Boot volume size (GiB). Volume-boot so flavors with 0 local disk still work."
}

variable "ssh_user" {
  type        = string
  default     = "ubuntu"
  description = "SSH user on the image (ubuntu for Ubuntu cloud images)."
}

variable "availability_zone" {
  type        = string
  default     = ""
  description = "Optional Nova AZ. Empty = let the scheduler choose."
}
