variable "cluster_name" {
  type        = string
  description = "Kind cluster name (dev, stg, or prod). Do not prefix with kind-."
}

variable "kubernetes_version" {
  type        = string
  description = "kindest/node image tag without the leading v (e.g. 1.32.2)."
}

variable "control_plane_nodes" {
  type    = number
  default = 1
}

variable "worker_nodes" {
  type        = number
  default     = 0
  description = "Worker count. 0 = control-plane only (matches the original Kind YAML)."
}

variable "kubeconfig_path" {
  type        = string
  description = "Absolute path for the kubeconfig file."
}

variable "extra_port_mappings" {
  type = list(object({
    container_port = number
    host_port      = number
    protocol       = optional(string, "TCP")
  }))
  default     = []
  description = "Host ports forwarded into the first control-plane node (ingress)."
}
