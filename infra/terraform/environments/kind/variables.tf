variable "cluster_name" {
  type        = string
  description = "Kind cluster name (dev, stg, or prod). Do not prefix with kind-."
}

variable "kubernetes_version" {
  type        = string
  description = "kindest/node image tag without the leading v (e.g. 1.32.2)."
}

variable "control_plane_nodes" {
  type        = number
  description = "Kind control-plane node count."
}

variable "worker_nodes" {
  type        = number
  description = "Worker count. 0 = control-plane only."
}

variable "kubeconfig_path" {
  type        = string
  description = "Absolute path for the kubeconfig file (sensitive/kind/kubeconfig)."
}

variable "http_host_port" {
  type        = number
  description = "Host port forwarded to container 80 on the first control-plane node."
}

variable "https_host_port" {
  type        = number
  description = "Host port forwarded to container 443 on the first control-plane node."
}
