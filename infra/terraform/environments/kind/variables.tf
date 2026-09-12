variable "cluster_name" {
  type    = string
  default = "dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.32.2"
}

variable "control_plane_nodes" {
  type    = number
  default = 1
}

variable "worker_nodes" {
  type        = number
  default     = 0
  description = "Control-plane only for the local lab."
}
