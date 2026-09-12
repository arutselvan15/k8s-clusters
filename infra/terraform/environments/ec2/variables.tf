variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type        = string
  default     = "default"
  description = "Profile name in k8s-platform/sensitive/aws/credentials."
}

variable "cluster_name" {
  type        = string
  description = "From the cluster id passed to up.sh. Nodes are {cluster_name}-cp and {cluster_name}-wk-N."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Local path for the generated SSH private key (sensitive/<env>/<cluster_name>/ssh.pem)."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Private IPv4 range for the lab VPC."
}

variable "admin_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Who may SSH (22) and reach the Kubernetes API (6443). Lab default is open."
}

variable "node_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 size for control plane and workers."
}

variable "worker_nodes" {
  type        = number
  default     = 1
  description = "Worker EC2 count (>= 1). First worker is aws_instance.worker; extras are extra_workers."
}
